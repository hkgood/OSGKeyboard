// AppContextDetector.swift
// OSGKeyboard · Shared
//
// iOS Custom Keyboard Extensions run in a tight sandbox: we cannot
// read the foreground app's bundle ID, we cannot query
// `LSApplicationWorkspace`, and we cannot observe app switches.
// The only signals available to the extension are:
//
//   - the text already at the cursor (`textDocumentProxy`)
//   - the current keyboard input language
//   - the time of day (used as a very weak signal)
//
// So we infer context with a **3-fallback chain**:
//   1. **Heuristic on preceding text** — strongest signal when the
//      user has already typed enough. Catches code, email, chat,
//      and document. We only look at the tail of the preceding
//      text (up to `precedingScanWindow` characters) so a long
//      note does not spend cycles scanning the whole buffer.
//   2. **Cached value** — when the user just opened a new field
//      with no preceding text, reuse the last detection for up to
//      `cacheLifetime`. Most users type in the same app for a
//      while; this avoids a cold-start `unknown` that would force
//      a neutral-tone LLM call.
//   3. **Environmental fallback** — when both above miss, blend
//      input language + hour-of-day into a soft default.
//
// Anything we cannot resolve maps to `.unknown`, which the polish
// service translates to a neutral-tone prompt.

import Foundation

public struct AppContextDetector: Sendable {
    /// How many characters of the preceding text we scan for
    /// heuristic matches. Long enough to capture a code block, a
    /// mail header, or a chat thread; short enough to scan in O(n)
    /// on every keystroke.
    public let precedingScanWindow: Int

    /// How long a cached detection stays valid. 30 minutes matches
    /// the "typical typing session" length and means the cache
    /// rarely outlives a switch to a genuinely new app.
    public let cacheLifetime: TimeInterval

    public init(
        precedingScanWindow: Int = 2000,
        cacheLifetime: TimeInterval = 30 * 60
    ) {
        self.precedingScanWindow = precedingScanWindow
        self.cacheLifetime = cacheLifetime
    }

    public func detect(
        precedingText: String?,
        storedCache: (context: AppContext, observedAt: Date)?,
        now: Date = Date()
    ) -> AppContext {
        // Fallback 1: heuristic on preceding text. Even one strong
        // signal (indented line ending with `{`, `> ` quote,
        // email pattern) is enough — we never mix-and-match.
        if let preceding = precedingText, !preceding.isEmpty,
           let detected = heuristicDetect(preceding: preceding) {
            return detected
        }

        // Fallback 2: cache. We rely on the caller having written
        // a fresh detection to the App Group on every successful
        // pressBegan; we just consult the timestamp here.
        if let cached = storedCache,
           now.timeIntervalSince(cached.observedAt) < cacheLifetime {
            return cached.context
        }

        // Fallback 3: environmental. Not great, but better than
        // `unknown` for a polished experience.
        return environmentalFallback(now: now)
    }

    // MARK: - Heuristic detection

    /// Inspect the tail of the preceding text. The order of the
    /// branches is significant: more specific signals first (code,
    /// terminal) so they win over more generic ones (chat,
    /// document).
    internal func heuristicDetect(preceding: String) -> AppContext? {
        let tail = preceding.suffix(precedingScanWindow)
        guard !tail.isEmpty else { return nil }

        // Code: indented line + a code-y keyword in the recent past.
        // The two-condition test avoids false positives on indented
        // lists / block quotes.
        let codeKeywords = [
            "func ", "class ", "struct ", "enum ", "protocol ",
            "import ", "package ", "namespace ",
            "def ", "var ", "let ", "const ",
            "if (", "if (", "} else", "} catch",
            "=> {", "-> {",
        ]
        let hasIndentation = tail.contains("\n    ") || tail.contains("\t")
        let hasCodeKeyword = codeKeywords.contains(where: { tail.contains($0) })
        if hasIndentation, hasCodeKeyword {
            return .code
        }

        // Code: shebang / single-line comment / URL-with-query.
        if tail.hasPrefix("#!/") || tail.contains("\n#!/") {
            return .code
        }

        // Terminal: prompt markers (rough but rarely wrong on
        // dedicated terminal apps). `$ `, `# `, `❯ `, `➜ `.
        if tail.range(of: #"(^|\n)[$#❯➜] "#, options: .regularExpression) != nil {
            return .code
        }

        // Email: contains an email-shaped token in the recent past.
        // We deliberately keep the regex conservative to avoid
        // matching every "@" in code / handles.
        if tail.range(
            of: #"\b[\w.+-]+@[\w-]+\.[A-Za-z]{2,}\b"#,
            options: .regularExpression
        ) != nil {
            return .email
        }

        // Email: subject-style opening — "Subject:", "To:", "From:",
        // "Cc:", or common CN mail domains in the URL bar.
        let emailOpeners = ["Subject:", "Re: ", "Fwd: ", "From:", "To:"]
        if emailOpeners.contains(where: { tail.contains($0) }) {
            return .email
        }

        // Chat: lots of short lines, no big paragraphs.
        let lines = tail.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(20)
        if lines.count >= 3 {
            let nonEmpty = lines.filter { !$0.isEmpty }
            let allShort = nonEmpty.count >= 3
                && nonEmpty.allSatisfy { $0.count < 60 }
            if allShort {
                return .chat
            }
        }

        // Document: long unbroken paragraphs.
        let lastParagraph = tail.split(separator: "\n\n").last ?? ""
        if lastParagraph.count > 200 && !lastParagraph.contains("\n") {
            return .document
        }

        return nil
    }

    // MARK: - Environmental fallback

    /// Last-resort guess. Deliberately biased toward "document" /
    /// "email" over "chat" because people who can no longer be
    /// classified are usually writing something more formal than
    /// not — and the cost of over-classifying as chat is a casual
    /// prompt that we can easily recover from.
    internal func environmentalFallback(now: Date) -> AppContext {
        let hour = Calendar.current.component(.hour, from: now)
        // 9am-6pm: assume document / work context. 8pm-7am: assume
        // chat. Weekends: lean chat. The signal is weak but it
        // beats random.
        let isWorkHours = (9...18).contains(hour)
        let isWeekend = Calendar.current.isDateInWeekend(now)
        if isWorkHours, !isWeekend {
            return .document
        }
        if !isWorkHours || isWeekend {
            return .chat
        }
        return .unknown
    }
}
