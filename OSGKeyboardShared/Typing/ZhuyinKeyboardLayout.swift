// ZhuyinKeyboardLayout.swift
// OSGKeyboard · Shared
//
// Standard Dachen key positions. The UI emits the visible symbol and the
// Rime bridge converts it to the ASCII key expected by the Zhuyin schema.

public enum ZhuyinKeyboardLayout {
    /// 37 phonetic symbols and four explicit tones. First tone uses Space.
    public static let rows: [[String]] = [
        ["ㄅ", "ㄉ", "ˇ", "ˋ", "ㄓ", "ˊ", "˙", "ㄚ", "ㄞ", "ㄢ", "ㄦ"],
        ["ㄆ", "ㄊ", "ㄍ", "ㄐ", "ㄔ", "ㄗ", "ㄧ", "ㄛ", "ㄟ", "ㄣ"],
        ["ㄇ", "ㄋ", "ㄎ", "ㄑ", "ㄕ", "ㄘ", "ㄨ", "ㄜ", "ㄠ", "ㄤ"],
        ["ㄈ", "ㄌ", "ㄏ", "ㄒ", "ㄖ", "ㄙ", "ㄩ", "ㄝ", "ㄡ", "ㄥ"]
    ]

    private static let keys: [Character: Character] = [
        "ㄅ": "1", "ㄆ": "q", "ㄇ": "a", "ㄈ": "z",
        "ㄉ": "2", "ㄊ": "w", "ㄋ": "s", "ㄌ": "x",
        "ㄍ": "e", "ㄎ": "d", "ㄏ": "c",
        "ㄐ": "r", "ㄑ": "f", "ㄒ": "v",
        "ㄓ": "5", "ㄔ": "t", "ㄕ": "g", "ㄖ": "b",
        "ㄗ": "y", "ㄘ": "h", "ㄙ": "n",
        "ㄧ": "u", "ㄨ": "j", "ㄩ": "m",
        "ㄚ": "8", "ㄛ": "i", "ㄜ": "k", "ㄝ": ",",
        "ㄞ": "9", "ㄟ": "o", "ㄠ": "l", "ㄡ": ".",
        "ㄢ": "0", "ㄣ": "p", "ㄤ": ";", "ㄥ": "/", "ㄦ": "-",
        "ˊ": "6", "ˇ": "3", "ˋ": "4", "˙": "7"
    ]

    private static let symbols = Dictionary(
        uniqueKeysWithValues: keys.map { ($0.value, $0.key) }
    )

    public static func key(for symbol: Character) -> Character? {
        keys[symbol]
    }

    /// Raw Dachen spelling must never leak into the host document when a
    /// composition is flushed by switching languages or input schemes.
    public static func displayText(for rawInput: String) -> String {
        String(rawInput.map { symbols[$0] ?? $0 })
    }
}
