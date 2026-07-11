// CloudProviderRole.swift
// OSGKeyboard · Shared
//
// Distinguishes cloud ASR credentials from polish LLM credentials
// (OpenLess-style split).

import Foundation

public enum CloudProviderRole: String, Sendable, Equatable {
    case asr
    case polish
}
