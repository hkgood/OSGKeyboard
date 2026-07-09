// MicVoiceAvailability+Keyboard.swift
// OSGKeyboard · Shared
//
// Derives keyboard mic availability from pipeline phase and host readiness.

import Foundation

public enum MicVoiceAvailabilityResolver {
    public static func resolve(
        phase: KeyboardState.Phase,
        micDisabled: Bool,
        hasFullAccess: Bool,
        appGroupAvailable: Bool,
        hostReady: Bool,
        isPreparingSession: Bool
    ) -> MicVoiceAvailability {
        switch phase {
        case .recording:
            return .recording
        case .processing, .requestingPermissions:
            return .processing
        case .error, .denied:
            return .unavailable(.hostNotReady)
        case .idle:
            break
        }

        if !appGroupAvailable {
            return .unavailable(.appGroupUnavailable)
        }
        if !hasFullAccess {
            return .unavailable(.noFullAccess)
        }
        if micDisabled {
            return .unavailable(.missingAPIKey)
        }
        if isPreparingSession {
            return .unavailable(.preparingSession)
        }
        if hostReady {
            return .ready
        }
        return .unavailable(.hostNotReady)
    }
}
