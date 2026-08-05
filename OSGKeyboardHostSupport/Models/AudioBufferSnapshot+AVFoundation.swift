// AudioBufferSnapshot+AVFoundation.swift
// OSGKeyboard · HostSupport
//
// AVAudioPCMBuffer → AudioBufferSnapshot copy helper. Kept out of Shared so
// the keyboard extension does not link AVFoundation for this type alone.

import AVFoundation
import Foundation
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

extension AudioBufferSnapshot {
    /// Construct from an `AVAudioPCMBuffer` by copying out the channel data.
    public init(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            self.init(samples: [], sampleRate: buffer.format.sampleRate)
            return
        }
        let n = Int(buffer.frameLength)
        var copy = [Float](repeating: 0, count: n)
        memcpy(&copy, channelData[0], n * MemoryLayout<Float>.size)
        self.init(samples: copy, sampleRate: buffer.format.sampleRate)
    }
}
