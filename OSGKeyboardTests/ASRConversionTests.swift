// ASRConversionTests.swift
// OSGKeyboard · Tests
//
// Locks in the Float32→Int16 PCM conversion that `SpeechAnalyzerASR`
// runs on the audio thread. The dictation transcriber's precondition
// (`"Audio sample data must be 16-bit signed integers"`) trips if
// the conversion is wrong, so the scaling + clipping math here is
// the difference between "Speech works" and "Speech crashes" — worth
// a regression test even though it's only ~3 lines of arithmetic.

import XCTest
@testable import OSGKeyboardShared

final class ASRConversionTests: XCTestCase {

    /// Edge cases: silence, full-scale positive, full-scale negative,
    /// mid-scale positive, mid-scale negative, and the "above unity"
    /// gain-overflow case. Each is the one number we'd most regret
    /// getting wrong.
    func testFloat32ToInt16EdgeCases() {
        runConversion(
            input: [0.0, 1.0, -1.0, 0.5, -0.5, 1.5, -1.5],
            expected: [0, 32767, -32767, 16384, -16384, 32767, -32768]
        )
    }

    /// Round-trip-ish: every Int16 in a small range should be
    /// reachable from a corresponding Float input. Locks the
    /// quantization step (1/32767) so a future "use a different
    /// scaling" change has to update this test.
    func testFloat32ToInt16RoundTrip() {
        var input = [Float]()
        var expected = [Int16]()
        for i in stride(from: -32768, through: 32767, by: 1024) {
            // Map Int16 back to its canonical Float source value:
            //   src = i / 32767.0 (so src=1.0 → i=32767, src=-1.0 → i=-32767).
            // We don't test i=-32768 because the asymmetric range
            // (Int16 is -32768...32767) means there is no Float
            // that decodes back to exactly -32768.
            let src = Float(i) / 32767.0
            input.append(src)
            expected.append(Int16(i))
        }
        runConversion(input: input, expected: expected)
    }

    /// Empty input must be a no-op. Guards against off-by-one in
    /// the loop and against `UnsafePointer` access on a zero-length
    /// array (which is undefined behaviour in C but valid in Swift).
    func testFloat32ToInt16Empty() {
        // `sourceCount == 0` with `nil` pointers is a no-op. The
        // function guards on `sourceCount > 0` before dereferencing
        // anything, so the nil pointers are safe.
        ASRServiceFactory.convertFloat32ToInt16(
            source: nil, sourceCount: 0, destination: nil
        )
        // Reaching here without crashing is the assertion.
    }

    // MARK: - Helper

    private func runConversion(input: [Float], expected: [Int16]) {
        precondition(input.count == expected.count, "test setup")
        var actual = [Int16](repeating: 0, count: expected.count)
        input.withUnsafeBufferPointer { src in
            actual.withUnsafeMutableBufferPointer { dst in
                ASRServiceFactory.convertFloat32ToInt16(
                    source: src.baseAddress,
                    sourceCount: src.count,
                    destination: dst.baseAddress
                )
            }
        }
        XCTAssertEqual(actual, expected)
    }
}
