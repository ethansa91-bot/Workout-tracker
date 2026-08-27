import Foundation

/// The short code that links one user to another.
///
/// Codes get read aloud, typed from a photo, and copied out of messages, so the
/// alphabet deliberately excludes every character pair that looks alike in a sans-serif
/// font: `O`/`0`, `I`/`1`/`L`, `S`/`5`, `Z`/`2`, `B`/`8`. `normalize` then maps those
/// look-alikes back, so someone who types `0` where the code has `O` still succeeds
/// rather than seeing "no such user".
enum ShareCode {

    /// 24 unambiguous characters. 8 places → ~1.1×10¹¹ combinations, which is far more
    /// than enough to make guessing someone's code impractical.
    private static let alphabet = Array("ACDEFGHJKMNPQRTUVWXY34679")

    static let length = 8

    static func generate() -> String {
        let raw = String((0..<length).map { _ in alphabet.randomElement()! })
        return format(raw)
    }

    /// `XXXX-XXXX` — grouped because an 8-character run is materially harder to read
    /// back correctly than two groups of four.
    static func format(_ code: String) -> String {
        let bare = normalize(code)
        guard bare.count == length else { return bare }
        let middle = bare.index(bare.startIndex, offsetBy: 4)
        return "\(bare[bare.startIndex..<middle])-\(bare[middle...])"
    }

    /// Excluded characters mapped to the alphabet character they're genuinely confused
    /// with. Keys are only ever characters the alphabet *doesn't* contain, so a valid
    /// code can never be rewritten into a different valid code — the mapping is a
    /// one-way rescue for typos, not a general fold.
    private static let lookAlikes: [Character: Character] = [
        "0": "Q", "O": "Q",           // nearest round glyph in the alphabet
        "1": "7", "I": "J", "L": "J", // the classic one/eye/ell confusion
        "S": "3", "5": "3",
        "Z": "3", "2": "3",
        "B": "6", "8": "6",
    ]

    /// Strips formatting and folds look-alike characters onto the canonical alphabet.
    /// Every lookup and comparison goes through this, so a code typed by hand from a
    /// photo still matches what was stored.
    static func normalize(_ input: String) -> String {
        var result = ""
        for character in input.uppercased() where character.isLetter || character.isNumber {
            result.append(lookAlikes[character] ?? character)
        }
        return result
    }

    /// True when the input could be a code at all — used to reject obvious typos before
    /// spending a network round trip on them.
    static func isPlausible(_ input: String) -> Bool {
        let bare = normalize(input)
        return bare.count == length && bare.allSatisfy { alphabet.contains($0) }
    }
}
