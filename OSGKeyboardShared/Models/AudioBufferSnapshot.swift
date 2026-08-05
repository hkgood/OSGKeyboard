// AudioBufferSnapshot.swift
// OSGKeyboard · Shared
//
// Sendable wrapper around a Float32 audio buffer's raw samples.
// Lives in Shared (no AVFoundation) so utterance chunking stays extension-safe.
// The AVAudioPCMBuffer initializer lives in OSGKeyboardHostSupport.

import Foundation

public struct AudioBufferSnapshot: Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}
