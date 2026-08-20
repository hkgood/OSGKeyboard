// FlowPictureInPictureController.swift
// OSGKeyboard · Main App
//
// Low-profile PiP keep-alive for Flow sessions. Production uses a transparent,
// static AVPictureInPictureVideoCallViewController with a 0.1 pt content
// height, no frame pump, and no idle audio session. The legacy sample-buffer
// teaching animation remains as a code-level fallback.

import AVFoundation
import AVKit
import CoreMedia
import OSGKeyboardHostSupport
import UIKit

/// Why `startAndWait` could not prove an active PiP window.
enum FlowPiPStartFailure: Equatable, Sendable {
    case unsupported
    case hostNotReady
    case notPossible
    case systemRejected
    case timedOut

    var localizationKey: String {
        switch self {
        case .unsupported: return "flow.session.error.unsupported"
        case .hostNotReady: return "flow.session.error.hostNotReady"
        case .notPossible: return "flow.session.error.notPossible"
        case .systemRejected: return "flow.session.error.systemRejected"
        case .timedOut: return "flow.session.error.timedOut"
        }
    }
}

enum FlowPiPStartOutcome: Equatable, Sendable {
    case started
    case failed(FlowPiPStartFailure)
}

@MainActor
final class FlowPictureInPictureController: NSObject {
    /// User closed the PiP window — host should end the Flow session.
    var onUserDismissed: (() -> Void)?

    private(set) var isPictureInPictureActive = false
    /// True once a host UIView has been attached (may still be awaiting a window).
    private(set) var hasHostView = false

    let displayLayer = AVSampleBufferDisplayLayer()

    private var pipController: AVPictureInPictureController?
    private var videoCallContentController: AVPictureInPictureVideoCallViewController?
    private var transparentContentView: UIView?
    private var displayLink: CADisplayLink?
    private weak var hostView: UIView?
    private var isStoppingProgrammatically = false
    private var frameIndex: Int64 = 0
    private var animationStartedAt: CFTimeInterval?
    private var cachedLogo: CGImage?
    /// Last system failure reported by the PiP delegate (cleared on each start).
    private var lastSystemStartFailure: Error?

    /// Production route: a static, transparent VideoCall PiP. Unlike the
    /// sample-buffer teaching animation, this needs no video frame pump and can
    /// release AVAudioSession after PiP becomes active.
    private let usesLowPowerVideoCallPiP = true

    /// Community implementations confirm that VideoCall PiP accepts an extreme
    /// aspect ratio. The system may clamp its final width, but a 0.1 pt content
    /// height makes the surface visually negligible without private positioning
    /// APIs.
    private static let lowProfileContentSize = CGSize(width: 300, height: 0.1)

    private enum Canvas {
        static let width = 480
        static let height = 270
        static let fps: Int32 = 18
        /// Full teaching loop length (seconds).
        static let loopDuration: CFTimeInterval = 4.2
    }

    // MARK: - Host view

    func attachHostView(_ view: UIView) {
        hostView = view
        hasHostView = true
        if usesLowPowerVideoCallPiP {
            displayLayer.removeFromSuperlayer()
            return
        }
        let bounds = view.bounds
        displayLayer.frame = (bounds.width >= 1 && bounds.height >= 1)
            ? bounds
            : CGRect(x: 0, y: 0, width: 64, height: 36)
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.removeFromSuperlayer()
        view.layer.addSublayer(displayLayer)
        // Do not create AVPictureInPictureController here — it must be built
        // only after an active AVAudioSession (see `start()`).
    }

    func updateHostLayoutIfNeeded() {
        guard let hostView else { return }
        let bounds = hostView.bounds
        displayLayer.frame = (bounds.width >= 1 && bounds.height >= 1)
            ? bounds
            : CGRect(x: 0, y: 0, width: 64, height: 36)
    }

    /// Host layer is in a UIWindow — required before `startPictureInPicture()`.
    var isHostInWindowHierarchy: Bool {
        hostView?.window != nil
    }

    // MARK: - Lifecycle

    @discardableResult
    func start() async -> Bool {
        lastSystemStartFailure = nil
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return false
        }
        guard hasHostView else { return false }

        // Required before constructing the controller; without an active
        // session, `isPictureInPicturePossible` stays false forever.
        guard await activateAudioSessionForPiP() else {
            return false
        }

        // If a controller was somehow created before audio activation, rebuild.
        if pipController != nil, !didActivateAudioSessionBeforeController {
            pipController = nil
        }
        configureControllerIfNeeded()
        if !usesLowPowerVideoCallPiP {
            warmLogoCacheIfNeeded()
            animationStartedAt = CACurrentMediaTime()
            startFramePump()
        }
        guard pipController != nil else { return false }

        if pipController?.isPictureInPictureActive == true {
            isPictureInPictureActive = true
            releaseAudioSessionForLowPowerPiP()
            return true
        }

        if !usesLowPowerVideoCallPiP {
            // Prime a few frames before asking the system to start PiP.
            enqueueGuideFrame()
            enqueueGuideFrame()
            pipController?.invalidatePlaybackState()
        }
        pipController?.startPictureInPicture()
        return true
    }

    /// Waits until the host is windowed and PiP is actually active.
    /// Does not treat "armed but inactive" as success — that left sessions
    /// live while `hostReady` stayed false forever.
    func startAndWait(
        hostTimeout: TimeInterval = 3,
        activeTimeout: TimeInterval = 8
    ) async -> FlowPiPStartOutcome {
        if isPictureInPictureActive { return .started }

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return .failed(.unsupported)
        }

        let hostReady = await waitForHostInWindow(timeout: hostTimeout)
        guard hostReady else {
            return .failed(.hostNotReady)
        }

        lastSystemStartFailure = nil
        guard await start() else {
            stopFramePump()
            if lastSystemStartFailure != nil {
                return .failed(.systemRejected)
            }
            return .failed(hasHostView ? .notPossible : .hostNotReady)
        }

        let deadline = Date().addingTimeInterval(activeTimeout)
        while Date() < deadline {
            if isPictureInPictureActive { return .started }
            if pipController?.isPictureInPictureActive == true {
                isPictureInPictureActive = true
                return .started
            }
            if let pipController, pipController.isPictureInPicturePossible {
                pipController.startPictureInPicture()
            } else {
                pipController?.startPictureInPicture()
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if isPictureInPictureActive { return .started }
        if pipController?.isPictureInPictureActive == true {
            isPictureInPictureActive = true
            return .started
        }

        // Real failure — tear down so the next retry starts clean.
        let failure: FlowPiPStartFailure
        if lastSystemStartFailure != nil {
            failure = .systemRejected
        } else if pipController?.isPictureInPicturePossible != true {
            failure = .notPossible
        } else {
            failure = .timedOut
        }
        FlowDiagnostics.log(
            "PiP startAndWait failed: \(failure) possible=\(pipController?.isPictureInPicturePossible == true)"
        )
        stop()
        return .failed(failure)
    }

    func stop() {
        isStoppingProgrammatically = true
        stopFramePump()
        pipController?.stopPictureInPicture()
        if !usesLowPowerVideoCallPiP {
            displayLayer.sampleBufferRenderer.flush(
                removingDisplayedImage: true,
                completionHandler: nil
            )
        }
        isPictureInPictureActive = false
        animationStartedAt = nil
        lastSystemStartFailure = nil
        isStoppingProgrammatically = false
    }

    /// Nudge the sample-buffer source right before resigning active so
    /// `canStartPictureInPictureAutomaticallyFromInline` can take over.
    func prepareForBackgroundAutoStart() async {
        guard isPictureInPictureActive || pipController != nil else { return }
        if isPictureInPictureActive {
            releaseAudioSessionForLowPowerPiP()
            return
        }
        _ = await activateAudioSessionForPiP()
        if !usesLowPowerVideoCallPiP {
            startFramePump()
            enqueueGuideFrame()
            pipController?.invalidatePlaybackState()
        }
        // `canStartPictureInPictureAutomaticallyFromInline` is the primary
        // transition when the app backgrounds. This explicit request is a
        // foreground/inactive fallback and remains idempotent.
        pipController?.startPictureInPicture()
    }

    /// Keep the shared audio session eligible for PiP after capture stops its
    /// engine. After the first utterance the coordinator intentionally retains
    /// the stable playAndRecord category instead of flipping back to playback.
    @discardableResult
    func reassertKeepAliveAudioSession() async -> Bool {
        if usesLowPowerVideoCallPiP, isPictureInPictureActive {
            releaseAudioSessionForLowPowerPiP()
            return true
        }
        return await activateAudioSessionForPiP()
    }

    /// Kept for FlowSessionManager call sites; guide animation ignores live levels.
    func updateWaveformLevels(_ levels: [Float]) {
        _ = levels
    }

    // MARK: - Private

    /// Set once we successfully activate audio before building the controller.
    private var didActivateAudioSessionBeforeController = false

    @discardableResult
    private func activateAudioSessionForPiP() async -> Bool {
        // The first PiP start uses playback. After capture establishes a
        // playAndRecord route, the coordinator keeps that category active and
        // only stops the engine/tap between utterances.
        if await FlowAudioSessionCoordinator.shared.activatePlayback() {
            FlowDiagnostics.log("PiP audio session ready")
            return true
        }
        return false
    }

    private func waitForHostInWindow(timeout: TimeInterval) async -> Bool {
        if isHostInWindowHierarchy { return true }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isHostInWindowHierarchy { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return isHostInWindowHierarchy
    }

    private func configureControllerIfNeeded() {
        guard pipController == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        let contentSource: AVPictureInPictureController.ContentSource
        if usesLowPowerVideoCallPiP, #available(iOS 15.0, *),
           let hostView {
            let contentController = AVPictureInPictureVideoCallViewController()
            contentController.preferredContentSize = Self.lowProfileContentSize
            contentController.view.backgroundColor = .clear
            contentController.view.isOpaque = false
            contentController.view.layer.backgroundColor = UIColor.clear.cgColor
            contentController.view.layer.isOpaque = false
            contentController.view.clipsToBounds = true

            let transparentView = UIView(frame: contentController.view.bounds)
            transparentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            transparentView.backgroundColor = .clear
            transparentView.isOpaque = false
            transparentView.isUserInteractionEnabled = false
            transparentView.layer.backgroundColor = UIColor.clear.cgColor
            transparentView.layer.isOpaque = false
            transparentView.layer.opacity = 0
            contentController.view.addSubview(transparentView)

            videoCallContentController = contentController
            transparentContentView = transparentView
            contentSource = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: hostView,
                contentViewController: contentController
            )
        } else {
            contentSource = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
        }
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.requiresLinearPlayback = true
        pipController = controller
        didActivateAudioSessionBeforeController = true
    }

    private func releaseAudioSessionForLowPowerPiP() {
        guard usesLowPowerVideoCallPiP, isPictureInPictureActive else { return }
        stopFramePump()
        FlowAudioSessionCoordinator.shared.deactivate()
        FlowDiagnostics.log("low-profile PiP active — released audio session and frame pump")
    }

    private func startFramePump() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 12,
            maximum: 20,
            preferred: Float(Canvas.fps)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopFramePump() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        enqueueGuideFrame()
        updateHostLayoutIfNeeded()

        guard let pipController, !pipController.isPictureInPictureActive else { return }
        if frameIndex % Int64(Canvas.fps) == 0 {
            pipController.invalidatePlaybackState()
        }
        // Retry regardless of `isPictureInPicturePossible` — that flag often
        // lags behind a warm sample-buffer source.
        pipController.startPictureInPicture()
    }

    private func enqueueGuideFrame() {
        guard let sampleBuffer = makeGuideSampleBuffer() else { return }
        if displayLayer.sampleBufferRenderer.status == .failed {
            displayLayer.sampleBufferRenderer.flush()
        }
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
    }

    private func warmLogoCacheIfNeeded() {
        guard cachedLogo == nil else { return }
        let logoColor = UIColor.white
        if let brand = UIImage(named: "OSGBrandMark")?
            .withTintColor(logoColor, renderingMode: .alwaysOriginal)
            .cgImage {
            cachedLogo = brand
            return
        }
        cachedLogo = UIImage(named: "osglogo")?
            .withTintColor(logoColor, renderingMode: .alwaysOriginal)
            .cgImage
    }

    // MARK: - Frame rendering

    private func makeGuideSampleBuffer() -> CMSampleBuffer? {
        let width = Canvas.width
        let height = Canvas.height
        frameIndex += 1

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            // BGRA pixel buffer requires little-endian byte order; without it
            // R/B channels swap and greens render as purple.
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Flip to UIKit top-left coordinates for layout math.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        drawGuideFrame(in: context, width: width, height: height)

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Canvas.fps),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: Canvas.fps),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard let sampleBuffer else { return nil }
        // Required for sample-buffer PiP sources to present immediately.
        CMSetAttachment(
            sampleBuffer,
            key: kCMSampleAttachmentKey_DisplayImmediately,
            value: kCFBooleanTrue,
            attachmentMode: kCMAttachmentMode_ShouldNotPropagate
        )
        return sampleBuffer
    }

    private func drawGuideFrame(in context: CGContext, width: Int, height: Int) {
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)

        // White PiP backdrop.
        context.setFillColor(UIColor.white.cgColor)
        context.fill(canvas)

        // Soft phone silhouette — gives the “screen edge” a visual anchor.
        let phoneInset = CGFloat(22)
        let phoneRect = canvas.insetBy(dx: phoneInset, dy: phoneInset)
        let phonePath = UIBezierPath(roundedRect: phoneRect, cornerRadius: 28)
        context.setStrokeColor(UIColor(red: 0.898, green: 0.906, blue: 0.922, alpha: 1).cgColor)
        context.setLineWidth(2.5)
        context.addPath(phonePath.cgPath)
        context.strokePath()

        let cardSize = CGSize(width: 148, height: 96)
        let restOrigin = CGPoint(
            x: phoneRect.midX - cardSize.width * 0.55,
            y: phoneRect.midY - cardSize.height * 0.5
        )
        // Mostly off the right edge, leaving a peek strip (~28% visible).
        let tuckedOrigin = CGPoint(
            x: phoneRect.maxX - cardSize.width * 0.28,
            y: restOrigin.y
        )

        let progress = cardTravelProgress()
        let cardOrigin = CGPoint(
            x: restOrigin.x + (tuckedOrigin.x - restOrigin.x) * progress,
            y: restOrigin.y
        )
        let cardRect = CGRect(origin: cardOrigin, size: cardSize)

        // Clip so the tucked card disappears past the phone’s right edge.
        context.saveGState()
        context.addPath(phonePath.cgPath)
        context.clip()

        drawLogoCard(in: context, rect: cardRect, tuckProgress: progress)
        context.restoreGState()
    }

    private func drawLogoCard(in context: CGContext, rect: CGRect, tuckProgress: CGFloat) {
        let cardPath = UIBezierPath(roundedRect: rect, cornerRadius: 16)

        context.setFillColor(UIColor(red: 0.20, green: 0.78, blue: 0.55, alpha: 1).cgColor)
        context.addPath(cardPath.cgPath)
        context.fillPath()

        context.setStrokeColor(UIColor(red: 0.20, green: 0.78, blue: 0.55, alpha: 1).cgColor)
        context.setLineWidth(1.5)
        context.addPath(cardPath.cgPath)
        context.strokePath()

        // Native PiP shows a left chevron on the peek strip when tucked right.
        let arrowOpacity = max(0, min(1, (tuckProgress - 0.55) / 0.35))
        if arrowOpacity > 0.01 {
            drawEdgeChevron(in: context, cardRect: rect, opacity: arrowOpacity)
        }

        guard let logo = cachedLogo else { return }
        let logoOpacity = 1 - arrowOpacity
        guard logoOpacity > 0.01 else { return }

        let maxLogoSide = min(rect.width, rect.height) * 0.52
        let logoAspect = CGFloat(logo.width) / CGFloat(max(logo.height, 1))
        let logoSize: CGSize
        if logoAspect >= 1 {
            logoSize = CGSize(width: maxLogoSide, height: maxLogoSide / logoAspect)
        } else {
            logoSize = CGSize(width: maxLogoSide * logoAspect, height: maxLogoSide)
        }
        let logoRect = CGRect(
            x: rect.midX - logoSize.width / 2,
            y: rect.midY - logoSize.height / 2,
            width: logoSize.width,
            height: logoSize.height
        )

        // Unflip locally so the CGImage is not drawn upside-down.
        context.saveGState()
        context.setAlpha(logoOpacity)
        context.translateBy(x: logoRect.minX, y: logoRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(logo, in: CGRect(origin: .zero, size: logoSize))
        context.restoreGState()
    }

    /// Left-pointing chevron on the visible peek strip (like system PiP).
    private func drawEdgeChevron(
        in context: CGContext,
        cardRect: CGRect,
        opacity: CGFloat
    ) {
        // Anchor in the leftmost ~28% of the card — that strip stays on-screen
        // when tucked to the right edge.
        let peekWidth = cardRect.width * 0.28
        let center = CGPoint(
            x: cardRect.minX + peekWidth * 0.5,
            y: cardRect.midY
        )
        let halfH: CGFloat = 11
        let halfW: CGFloat = 7

        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x + halfW, y: center.y - halfH))
        path.addLine(to: CGPoint(x: center.x - halfW, y: center.y))
        path.addLine(to: CGPoint(x: center.x + halfW, y: center.y + halfH))

        context.saveGState()
        context.setStrokeColor(UIColor.white.withAlphaComponent(opacity).cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(path.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    /// 0 = rest (visible), 1 = tucked at right edge.
    private func cardTravelProgress() -> CGFloat {
        let started = animationStartedAt ?? CACurrentMediaTime()
        if animationStartedAt == nil {
            animationStartedAt = started
        }
        let t = (CACurrentMediaTime() - started)
            .truncatingRemainder(dividingBy: Canvas.loopDuration)

        // 0.0–0.6 rest → 0.6–2.0 slide out → 2.0–3.0 hold → 3.0–4.2 return
        if t < 0.6 {
            return 0
        }
        if t < 2.0 {
            return smoothstep((t - 0.6) / 1.4)
        }
        if t < 3.0 {
            return 1
        }
        return 1 - smoothstep((t - 3.0) / 1.2)
    }

    private func smoothstep(_ x: CGFloat) -> CGFloat {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension FlowPictureInPictureController: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPictureInPictureActive = true
        lastSystemStartFailure = nil
        releaseAudioSessionForLowPowerPiP()
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPictureInPictureActive = false
        stopFramePump()
        guard !isStoppingProgrammatically else { return }
        onUserDismissed?()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        // Sample-buffer fallback may need warm-up retries. VideoCall PiP uses
        // the automatic-inline path plus the bounded startAndWait fallback.
        lastSystemStartFailure = error
        FlowDiagnostics.log("PiP start attempt failed (will retry): \(error.localizedDescription)")
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension FlowPictureInPictureController: @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        if playing {
            if animationStartedAt == nil {
                animationStartedAt = CACurrentMediaTime()
            }
            startFramePump()
        } else {
            // Do not stop the frame pump on pause — sample-buffer PiP keep-alive
            // must keep feeding frames so auto-inline can resume.
            animationStartedAt = CACurrentMediaTime()
            startFramePump()
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        // Live / unbounded content — finite durations make PiP stuck loading.
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
