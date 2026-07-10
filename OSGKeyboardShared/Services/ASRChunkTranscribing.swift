// ASRChunkTranscribing.swift
// OSGKeyboard · Shared
//
// Minimal ASR surface for pipelined utterance chunking. Keeps
// `ChunkedUtterancePipeline` independent of iOS-only `SpeechAnalyzer`.

import Foundation

public enum ASRChunkResult: Sendable, Equatable {
    case success(String)
    case failure(String)
    case cancelled
}

/// One-shot chunk transcription used by `ChunkedUtterancePipeline`.
public protocol ASRChunkTranscribing: Sendable {
    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult
    func cancel()
    func resetForNewUtterance()
}

extension ASRChunkTranscribing {
    public func cancel() {}
    public func resetForNewUtterance() {}
}
