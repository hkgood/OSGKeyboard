// HanScript.swift
// OSGKeyboard · Shared
//
// Canonical BMP Han ideograph predicate used by text-processing features.

enum HanScript {
    static func isIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    static func containsIdeograph(in text: String) -> Bool {
        text.unicodeScalars.contains(where: isIdeograph)
    }
}
