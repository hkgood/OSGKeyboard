// PCMSampleWavEncoder.swift
// OSGKeyboard · Shared
//
// Encodes mono Float32 PCM (@ 16 kHz) into a minimal WAV byte stream for
// cloud ASR multipart / base64 uploads.

import Foundation

public enum PCMSampleWavEncoder {
    public static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        guard !samples.isEmpty else {
            return encode(pcm16: [], sampleRate: sampleRate)
        }
        var pcm16 = [Int16]()
        pcm16.reserveCapacity(samples.count)
        for sample in samples {
            let scaled = sample * 32_767.0
            let clipped = Swift.max(-32_768.0, Swift.min(32_767.0, scaled))
            pcm16.append(Int16(clipped.rounded()))
        }
        return encode(pcm16: pcm16, sampleRate: sampleRate)
    }

    public static func encode(pcm16: [Int16], sampleRate: Int) -> Data {
        let byteRate = sampleRate * 2
        let dataSize = pcm16.count * MemoryLayout<Int16>.size
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func appendASCII(_ string: String) {
            data.append(contentsOf: string.utf8)
        }
        func appendLE32(_ value: UInt32) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendLE16(_ value: UInt16) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendLE32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendLE32(16)
        appendLE16(1) // PCM
        appendLE16(1) // mono
        appendLE32(UInt32(sampleRate))
        appendLE32(UInt32(byteRate))
        appendLE16(2) // block align
        appendLE16(16) // bits per sample
        appendASCII("data")
        appendLE32(UInt32(dataSize))

        pcm16.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            data.append(UnsafeBufferPointer(start: base, count: buffer.count))
        }
        return data
    }

    public static func dataURI(samples: [Float], sampleRate: Int = 16_000) -> String {
        let wav = encode(samples: samples, sampleRate: sampleRate)
        return "data:audio/wav;base64,\(wav.base64EncodedString())"
    }
}
