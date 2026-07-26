// FlowPictureInPictureController.swift
// OSGKeyboard · Main App
//
// PiP keep-alive for Flow sessions: enqueues live waveform sample buffers
// so the host process stays eligible for multitasking while the mic is off
// between utterances.

import AVFoundation
import AVKit
import CoreMedia
import UIKit

@MainActor
final class FlowPictureInPictureController: NSObject {
    /// User closed the PiP window — host should end the Flow session.
    var onUserDismissed: (() -> Void)?

    private(set) var isPictureInPictureActive = false

    let displayLayer = AVSampleBufferDisplayLayer()

    private var pipController: AVPictureInPictureController?
    private var displayLink: CADisplayLink?
    private weak var hostView: UIView?
    private var waveformLevels: [Float] = Array(repeating: 0, count: 24)
    private var isStoppingProgrammatically = false
    private var frameIndex: Int64 = 0

    // MARK: - Host view

    func attachHostView(_ view: UIView) {
        hostView = view
        displayLayer.frame = view.bounds
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.removeFromSuperlayer()
        view.layer.addSublayer(displayLayer)
        configureControllerIfNeeded()
    }

    func updateHostLayoutIfNeeded() {
        guard let hostView else { return }
        displayLayer.frame = hostView.bounds
    }

    // MARK: - Lifecycle

    @discardableResult
    func start() -> Bool {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return false
        }
        configureControllerIfNeeded()
        startFramePump()
        guard pipController != nil else { return false }

        if pipController?.isPictureInPictureActive == true {
            isPictureInPictureActive = true
            return true
        }

        enqueueWaveformFrame()
        pipController?.startPictureInPicture()
        return true
    }

    func startAndWait(timeout: TimeInterval = 4) async -> Bool {
        if isPictureInPictureActive { return true }
        guard start() else { return false }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isPictureInPictureActive { return true }
            if pipController?.isPictureInPictureActive == true {
                isPictureInPictureActive = true
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return isPictureInPictureActive
    }

    func stop() {
        isStoppingProgrammatically = true
        stopFramePump()
        pipController?.stopPictureInPicture()
        displayLayer.flushAndRemoveImage()
        isPictureInPictureActive = false
        isStoppingProgrammatically = false
    }

    func updateWaveformLevels(_ levels: [Float]) {
        guard !levels.isEmpty else { return }
        waveformLevels = levels
    }

    // MARK: - Private

    private func configureControllerIfNeeded() {
        guard pipController == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = controller
    }

    private func startFramePump() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 24)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopFramePump() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        enqueueWaveformFrame()
        updateHostLayoutIfNeeded()

        if let pipController, !pipController.isPictureInPictureActive, pipController.isPictureInPicturePossible {
            pipController.startPictureInPicture()
        }
    }

    private func enqueueWaveformFrame() {
        guard let sampleBuffer = makeWaveformSampleBuffer(levels: resolvedLevels()) else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    private func resolvedLevels() -> [Float] {
        if waveformLevels.contains(where: { $0 > 0.02 }) {
            return waveformLevels
        }
        // Idle breathing animation between utterances.
        let phase = Float(frameIndex) * 0.12
        return (0..<waveformLevels.count).map { index in
            let wave = sin(phase + Float(index) * 0.45)
            return max(0.04, 0.04 + wave * 0.03)
        }
    }

    private func makeWaveformSampleBuffer(levels: [Float]) -> CMSampleBuffer? {
        let width = 320
        let height = 180
        frameIndex += 1

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
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
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        // Dark backdrop + accent waveform bars.
        context.setFillColor(UIColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let barCount = max(levels.count, 1)
        let barWidth = CGFloat(width) / CGFloat(barCount * 2)
        let accent = UIColor(red: 0.20, green: 0.78, blue: 0.55, alpha: 1)
        context.setFillColor(accent.cgColor)

        for (index, level) in levels.enumerated() {
            let clamped = CGFloat(min(max(level, 0), 1))
            let barHeight = max(6, clamped * CGFloat(height) * 0.72)
            let x = (CGFloat(index) * 2 + 0.5) * barWidth
            let rect = CGRect(
                x: x,
                y: (CGFloat(height) - barHeight) / 2,
                width: barWidth,
                height: barHeight
            )
            let path = UIBezierPath(roundedRect: rect, cornerRadius: barWidth * 0.35)
            context.addPath(path.cgPath)
            context.fillPath()
        }

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 24),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: 24),
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
        return sampleBuffer
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension FlowPictureInPictureController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        isPictureInPictureActive = true
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
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension FlowPictureInPictureController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        if playing {
            startFramePump()
        } else {
            stopFramePump()
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(value: 3600, timescale: 1))
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
