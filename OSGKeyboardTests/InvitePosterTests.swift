// InvitePosterTests.swift
// OSGKeyboardTests
//
// The poster is only useful if a camera can read it back, so these tests
// decode the generated QR code instead of only checking that an image exists.

import CoreImage
@testable import OSGKeyboard
import OSGKeyboardShared
import XCTest

final class InvitePosterTests: XCTestCase {
    private let inviteURL = URL(
        string: "https://osglab.com/i/Abcdefghij_1234567890-?source=server"
    )!

    func testQRCodeDecodesToTheExactInvitationLink() throws {
        let image = try XCTUnwrap(InviteQRCode.makeImage(for: inviteURL))

        XCTAssertEqual(decodedMessages(in: image), [inviteURL.absoluteString])
    }

    @MainActor
    func testPosterExportsAtFixedSizeAndStaysScannable() throws {
        let poster = try XCTUnwrap(
            InvitePosterRenderer.render(
                inviteURL: inviteURL,
                inviterName: nil,
                language: .chinese,
                colorScheme: .light
            )
        )

        XCTAssertEqual(poster.width, 1080)
        XCTAssertEqual(poster.height, 1440)
        XCTAssertEqual(decodedMessages(in: poster), [inviteURL.absoluteString])
        XCTAssertGreaterThan(cornerLuminance(of: poster), 0.95)
    }

    @MainActor
    func testDarkPosterWithShortCodeAndLongNameStaysScannable() throws {
        let poster = try XCTUnwrap(
            InvitePosterRenderer.render(
                inviteURL: inviteURL,
                shortCode: "K7M2-Q9XA",
                inviterName: "一位用户名比较长但仍然需要完整显示的朋友",
                language: .chinese,
                colorScheme: .dark
            )
        )

        XCTAssertEqual(poster.width, 1080)
        XCTAssertEqual(poster.height, 1440)
        XCTAssertEqual(decodedMessages(in: poster), [inviteURL.absoluteString])
        XCTAssertGreaterThan(
            darkPixelFraction(
                in: poster,
                crop: CGRect(x: 300, y: 600, width: 480, height: 500)
            ),
            0.15
        )
        // The graphite paper carries a subtle daylight wash, but remains
        // distinctly dark rather than approaching the warm-paper surface.
        XCTAssertLessThan(cornerLuminance(of: poster), 0.18)
    }

    private func decodedMessages(in image: CGImage) -> [String] {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        return (detector?.features(in: CIImage(cgImage: image)) ?? [])
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    private func cornerLuminance(of image: CGImage) -> Double {
        guard let corner = image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
            return -1
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (0.2126 * Double(pixel[0])
            + 0.7152 * Double(pixel[1])
            + 0.0722 * Double(pixel[2])) / 255
    }

    private func darkPixelFraction(in image: CGImage, crop: CGRect) -> Double {
        guard let cropped = image.cropping(to: crop) else { return 0 }
        let width = 120
        let height = 120
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }
        context.interpolationQuality = .none
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        let darkCount = (0..<(width * height)).count { index in
            let offset = index * 4
            return Int(pixels[offset])
                + Int(pixels[offset + 1])
                + Int(pixels[offset + 2]) < 3 * 100
        }
        return Double(darkCount) / Double(width * height)
    }
}
