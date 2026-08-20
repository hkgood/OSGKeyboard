// ManagedGatewayScopePolicy.swift
// OSGKeyboard · Shared
//
// Computes the smallest grant needed by the currently enabled managed paths.

import Foundation

public enum ManagedGatewayScopePolicy {
    public static func scopes(engineMode: String) -> Set<ManagedGatewayCapability> {
        var scopes: Set<ManagedGatewayCapability> = [.polish, .assistant, .agent]
        if engineMode == "cloud" {
            scopes.insert(.asr)
        }
        return scopes
    }
}
