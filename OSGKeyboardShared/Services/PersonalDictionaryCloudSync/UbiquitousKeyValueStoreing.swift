// UbiquitousKeyValueStoreing.swift
// OSGKeyboard · Shared
//
// Test seam around `NSUbiquitousKeyValueStore`.

import Foundation

public protocol UbiquitousKeyValueStoreing: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ value: Data?, forKey key: String)
    @discardableResult
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoreing {}
