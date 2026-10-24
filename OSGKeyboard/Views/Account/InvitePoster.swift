// InvitePoster.swift
// OSGKeyboard · Main App + Mac
//
// Shareable invitation artwork: the app icon, inviter name, a QR code for the
// account's invitation link, and the short code for friends who type it
// instead of scanning. The QR code is generated on device with Core Image,
// so the link is never sent anywhere to be rendered. The Mac target compiles
// this file at the source level (see project.yml), so it must stay free of
// UIKit and AppKit.

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

enum InviteQRCode {
    /// Pixels per QR module. Integer scaling keeps module edges sharp.
    fileprivate static let moduleScale: CGFloat = 12

    static func makeImage(for url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        // "M" (15%) survives chat-app recompression. Nothing is drawn over the
        // code, so a higher level would only shrink the modules.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: moduleScale, y: moduleScale)
        )
        // QRGenerator produces a one-channel image that SwiftUI can treat as a
        // template and recolor white in dark mode. Materialize explicit black
        // and white pixels so both poster appearances remain scannable.
        let falseColor = CIFilter.falseColor()
        falseColor.inputImage = scaled
        falseColor.color0 = CIColor.black
        falseColor.color1 = CIColor.white
        guard let colored = falseColor.outputImage else { return nil }
        return CIContext().createCGImage(colored, from: colored.extent)
    }
}

/// Fixed 3:4 layout so the exported image is the same on every device and
/// is never cropped in chat previews or Moments.
struct InvitePosterView: View {
    static let size = CGSize(width: 360, height: 480)

    let qrImage: CGImage
    let language: AppUILanguage?
    let inviterName: String?
    let colorScheme: ColorScheme
    /// `XXXX-XXXX`; lets a friend who cannot scan type the code instead.
    var shortCode: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            // Use the active Icon Composer artwork, not the horizontal logo.
            Image("AppIcon_Assets/OSGKeyboard Icon2")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text(
                SharedL10n.format(
                    "invite.poster.inviter",
                    language: language,
                    resolvedInviterName
                )
            )
                .font(.system(size: 18, weight: .medium, design: .default))
                .foregroundStyle(primaryContent)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .lineSpacing(3)
                .minimumScaleFactor(0.75)
                .padding(.top, 24)

            // Dark modules on a light card scan most reliably, including in
            // WeChat's long-press recognizer.
            InviteQRCodeView(image: qrImage)
                .frame(width: 156, height: 156)
                .padding(Spacing.sm)
                .background(
                    OSGColor.fixedLightContent,
                    in: Rectangle()
                )
                .padding(.top, 28)

            Text(SharedL10n.string("invite.poster.scan", language: language))
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(secondaryContent)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            if let shortCode {
                Text(SharedL10n.format("invite.poster.code", language: language, shortCode))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(primaryContent)
                    .padding(.top, 10)
            }

            Spacer(minLength: 32)
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(InvitePosterBackground(colorScheme: colorScheme))
    }

    private var resolvedInviterName: String {
        let trimmed = inviterName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty
            ? SharedL10n.string("invite.poster.defaultInviter", language: language)
            : trimmed
    }

    private var primaryContent: Color {
        colorScheme == .dark ? Color(white: 0.96) : Color(white: 0.08)
    }

    private var secondaryContent: Color {
        primaryContent.opacity(0.62)
    }
}

/// Draws each QR module as a vector rectangle. `ImageRenderer` can otherwise
/// reinterpret a CGImage as a template on complex dark backgrounds and erase
/// its black modules. Vector modules stay black in every appearance.
private struct InviteQRCodeView: View {
    private let sideCount: Int
    private let darkModules: [Bool]

    init(image: CGImage) {
        let matrix = Self.moduleMatrix(from: image)
        sideCount = matrix.sideCount
        darkModules = matrix.darkModules
    }

    var body: some View {
        Canvas { context, size in
            guard sideCount > 0 else { return }
            let moduleWidth = size.width / CGFloat(sideCount)
            let moduleHeight = size.height / CGFloat(sideCount)
            var modules = Path()

            for row in 0..<sideCount {
                for column in 0..<sideCount where darkModules[row * sideCount + column] {
                    modules.addRect(
                        CGRect(
                            x: CGFloat(column) * moduleWidth,
                            y: CGFloat(row) * moduleHeight,
                            width: moduleWidth,
                            height: moduleHeight
                        )
                    )
                }
            }
            context.fill(modules, with: .color(OSGColor.fixedDarkContent))
        }
        .background(OSGColor.fixedLightContent)
    }

    private static func moduleMatrix(
        from image: CGImage
    ) -> (sideCount: Int, darkModules: [Bool]) {
        let sideCount = max(image.width / Int(InviteQRCode.moduleScale), 1)
        var pixels = [UInt8](repeating: 0, count: sideCount * sideCount * 4)
        guard let context = CGContext(
            data: &pixels,
            width: sideCount,
            height: sideCount,
            bitsPerComponent: 8,
            bytesPerRow: sideCount * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (0, [])
        }
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: sideCount, height: sideCount)
        )
        let darkModules = (0..<(sideCount * sideCount)).map { index in
            let offset = index * 4
            let luminance = Int(pixels[offset])
                + Int(pixels[offset + 1])
                + Int(pixels[offset + 2])
            return luminance < 3 * 128
        }
        return (sideCount, darkModules)
    }
}

/// A restrained paper surface: warm Nordic stock in light mode and graphite
/// stock in dark mode. The daylight bands and fibers stay below text contrast,
/// so the background adds depth without becoming decoration.
private struct InvitePosterBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                base

                LinearGradient(
                    colors: daylightColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Ellipse()
                    .fill(topTrailingShadow)
                    .frame(width: 310, height: 250)
                    .offset(x: 178, y: -186)
                    .blur(radius: 62)

                Ellipse()
                    .fill(bottomLeadingShadow)
                    .frame(width: 300, height: 260)
                    .offset(x: -182, y: 224)
                    .blur(radius: 68)

                Rectangle()
                    .fill(diagonalShadow)
                    .frame(width: proxy.size.width * 1.55, height: 82)
                    .rotationEffect(.degrees(-18))
                    .offset(x: 72, y: -118)
                    .blur(radius: 34)

                paperFibers(in: proxy.size)
            }
        }
    }

    private var base: Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.054, blue: 0.050)
            : Color(red: 0.965, green: 0.953, blue: 0.922)
    }

    private var daylightColors: [Color] {
        if colorScheme == .dark {
            return [
                .white.opacity(0.085),
                .clear,
                .black.opacity(0.30)
            ]
        }
        return [
            .white.opacity(0.62),
            .clear,
            Color(red: 0.52, green: 0.48, blue: 0.41).opacity(0.18)
        ]
    }

    private var topTrailingShadow: Color {
        colorScheme == .dark
            ? .black.opacity(0.38)
            : Color(red: 0.43, green: 0.40, blue: 0.35).opacity(0.24)
    }

    private var bottomLeadingShadow: Color {
        colorScheme == .dark
            ? .black.opacity(0.28)
            : Color(red: 0.48, green: 0.44, blue: 0.37).opacity(0.15)
    }

    private var diagonalShadow: Color {
        colorScheme == .dark
            ? .white.opacity(0.055)
            : Color.black.opacity(0.055)
    }

    private func paperFibers(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<48, id: \.self) { index in
                Rectangle()
                    .fill(fiberColor)
                    .frame(width: 2 + 7 * fraction(index * 19), height: 0.35)
                    .position(
                        x: size.width * fraction(index * 37),
                        y: size.height * fraction(index * 61)
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private var fiberColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.025)
            : Color.black.opacity(0.025)
    }

    private func fraction(_ value: Int) -> CGFloat {
        CGFloat(value % 101) / 100
    }
}

enum InvitePosterRenderer {
    /// 3× the point layout: a 1080×1440 px image.
    static let exportScale: CGFloat = 3

    @MainActor
    static func render(
        inviteURL: URL,
        shortCode: String? = nil,
        inviterName: String? = nil,
        language: AppUILanguage?,
        colorScheme: ColorScheme
    ) -> CGImage? {
        guard let qrImage = InviteQRCode.makeImage(for: inviteURL) else { return nil }
        let renderer = ImageRenderer(
            content: InvitePosterView(
                qrImage: qrImage,
                language: language,
                inviterName: inviterName,
                colorScheme: colorScheme,
                shortCode: shortCode
            )
        )
        renderer.scale = exportScale
        return renderer.cgImage
    }
}
