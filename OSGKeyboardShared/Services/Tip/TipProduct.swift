// TipProduct.swift
// OSGKeyboard · Shared
//
// StoreKit product identifiers for optional voluntary tips.
// Tips are consumable IAP — they do not unlock features.

import Foundation

public enum TipProduct {
    /// ¥28 voluntary support tip (Consumable). Must match App Store Connect Product ID.
    public static let supportID = "ByRockyACoffee"

    public static var allProductIDs: [String] { [supportID] }

    /// UserDefaults key for optional UX: how many times the user tipped (not entitlements).
    public static let supportCountDefaultsKey = "tipSupportPurchaseCount"
}
