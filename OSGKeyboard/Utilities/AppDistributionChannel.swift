// AppDistributionChannel.swift
// OSGKeyboard · Main App
//
// Keeps internal tools available in local Debug and TestFlight builds only.

import Foundation

enum AppDistributionChannel {
    static var allowsInternalTools: Bool {
        allowsInternalTools(
            isDebugBuild: isDebugBuild,
            receiptURL: Bundle.main.appStoreReceiptURL
        )
    }

    static func allowsInternalTools(
        isDebugBuild: Bool,
        receiptURL: URL?
    ) -> Bool {
        isDebugBuild || receiptURL?.lastPathComponent == "sandboxReceipt"
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
