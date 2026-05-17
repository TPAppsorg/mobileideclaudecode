import Foundation

/// Segments agent text delimited by `[thought: true] … [thought: false]` (and aliases)
/// into **Thinking** vs main answer Markdown, with heuristics when the model omits closing tags
/// or pastes the final reply inside the "thought" span.
struct ParsedAgentDisplay: Equatable {
    let reasoningText: String?
    let answerText: String
    /// Client-side: raw (normalized) text contained `[thought:…]`, `<thinking>`, etc. — i.e. a deliberate reasoning wire format, not inferred layout alone.
    let usesExplicitThoughtDelimiters: Bool
    /// When both reasoning and answer exist: put main answer **above** thinking only if substantive prose appeared **before** the first `[thought: true]` in stream order (lead reply + thinking). Pure “thinking then tail answer” stays `false` (thinking on top).
    let preferAnswerBeforeReasoning: Bool
}

enum AgentReasoningParser {
    /// `[thought: true|false|on|off]` case-insensitive.
    private static let thoughtTagRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)\[thought:\s*(true|false|on|off)\s*\]"#)
    }()
    
    /// Gemini bridge turns `tool_use` events into lines like `• read_file path`.
    private static let toolProgressLineRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\s*•\s+\S"#)
    }()
    
    private static let markdownHeadingBreakRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\n\n#{1,6}\s"#)
    }()
    
    private static let horizontalRuleBreakRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\n\n-{3,}\s*\n\n"#)
    }()
    
    private static let numberedListBreakRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\n\n\d+\.\s"#)
    }()
    
    private static let conversationalAnswerBreakRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\n\n(?i)(here(?:'s| is)\b|in summary\b|to summarize\b|the answer(?: is)?\b|short answer\b|итог\b|ответ\b)"#,
        )
    }()
    
    /// Common model pattern: `**Summary:**` or `**Answer**` after tool traces.
    private static let boldLeadBreakRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\n\n\*\*"#)
    }()

    /// Model status lines often leak inside an unclosed `[thought: true]…` span after real reasoning.
    private static let finalizeStatusBreakRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\n\n(?i)(?:finaliz(?:e|ing)\b|finalising\b|wrapping\s+up\b|finishing(?:\s+up)?\b|almost\s+done\b|финализиру(?:ю|ет|ция)?\b|заверш(?:аю|ение)\b|подводим\s+итог)\b"#,
        )
    }()

    /// Entire reasoning blob is just a short “finalizing…” status (no real thought body).
    private static let reasoningIsOnlyFinalizeStatusRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?is)\A\s*(?:finaliz(?:e|ing)\b|finalising\b|wrapping\s+up\b|finishing(?:\s+up)?\b|almost\s+done\b|финализиру(?:ю|ет|ция)?\b|заверш(?:аю|ение)\b|подводим\s+итог)\b[^\n]{0,280}\s*\Z"#,
        )
    }()

    /// First line of a tail after tools looks like a finalize banner (single newline after tool block).
    private static let finalizeLeadSingleLineRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?is)\A\s*(?:finaliz(?:e|ing)\b|finalising\b|wrapping\s+up\b|finishing(?:\s+up)?\b|almost\s+done\b|финализиру(?:ю|ет|ция)?\b|заверш(?:аю|ение)\b|подводим\s+итог)\b"#,
        )
    }()

    /// True when the model streamed a **real** user-facing lead before the first `[thought: true]` (answer-first layout). Short fillers like “OK.” do not flip this.
    private static func computePreferAnswerBeforeReasoning(
        normalized: String,
        matches: [NSTextCheckingResult],
        ns: NSString,
    ) -> Bool {
        guard let openIdx = matches.firstIndex(where: {
            let k = ns.substring(with: $0.range(at: 1)).lowercased()
            return k == "true" || k == "on"
        }) else { return false }
        let openLoc = matches[openIdx].range.location
        guard openLoc > 0 else { return false }
        let p = ns.substring(with: NSRange(location: 0, length: openLoc))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return false }
        if p.count >= 36 { return true }
        if p.hasPrefix("#") { return true }
        let plen = (p as NSString).length
        if plen > 0, boldLeadBreakRegex.firstMatch(in: p, options: [], range: NSRange(location: 0, length: plen)) != nil {
            return true
        }
        if p.contains("\n\n"), p.count >= 48 { return true }
        return false
    }

    static func parse(_ raw: String, isStreaming: Bool = false) -> ParsedAgentDisplay {
        let normalized = normalizeThoughtAliases(raw)
        let ns = normalized as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = thoughtTagRegex.matches(in: normalized, options: [], range: fullRange)
        
        if matches.isEmpty {
            if let split = splitLeadingToolProgressLines(normalized) {
                return peelAnswerTailFromReasoning(
                    ParsedAgentDisplay(
                        reasoningText: split.reasoningText,
                        answerText: split.answerText,
                        usesExplicitThoughtDelimiters: false,
                        preferAnswerBeforeReasoning: false,
                    ),
                    isStreaming: isStreaming,
                )
            }
            return ParsedAgentDisplay(
                reasoningText: nil,
                answerText: normalized,
                usesExplicitThoughtDelimiters: false,
                preferAnswerBeforeReasoning: false,
            )
        }
        
        var mainChunks: [String] = []
        var reasoningChunks: [String] = []
        var modeIsReasoning = false
        var cursor = 0
        
        for m in matches {
            let tagRange = m.range
            let kindRaw = ns.substring(with: m.range(at: 1)).lowercased()
            let opensReasoning = kindRaw == "true" || kindRaw == "on"
            let gap = NSRange(location: cursor, length: max(0, tagRange.location - cursor))
            let gapStr = gap.length > 0 ? ns.substring(with: gap) : ""
            if modeIsReasoning {
                reasoningChunks.append(gapStr)
            } else {
                mainChunks.append(gapStr)
            }
            modeIsReasoning = opensReasoning
            cursor = tagRange.location + tagRange.length
        }
        
        let tailLen = max(0, ns.length - cursor)
        let tailRange = NSRange(location: cursor, length: tailLen)
        let tail = tailLen > 0 ? ns.substring(with: tailRange) : ""
        if modeIsReasoning {
            reasoningChunks.append(tail)
        } else {
            mainChunks.append(tail)
        }
        
        var reasoningJoined = reasoningChunks.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let answerJoined = mainChunks.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        
        var reasoning: String? = reasoningJoined.isEmpty ? nil : reasoningJoined
        var answer = answerJoined.isEmpty ? " " : answerJoined

        let preferAnswerFirst = computePreferAnswerBeforeReasoning(normalized: normalized, matches: matches, ns: ns)

        let peeled = peelFinalAnswerOutOfReasoning(
            reasoning: reasoning,
            answer: answer,
            isStreaming: isStreaming,
            usesExplicitThoughtDelimiters: true,
            preferAnswerBeforeReasoning: preferAnswerFirst,
        )
        reasoning = peeled.reasoningText
        answer = peeled.answerText

        return ParsedAgentDisplay(
            reasoningText: reasoning,
            answerText: answer.isEmpty ? " " : answer,
            usesExplicitThoughtDelimiters: true,
            preferAnswerBeforeReasoning: preferAnswerFirst,
        )
    }
    
    // MARK: - Normalize tags
    
    private static func normalizeThoughtAliases(_ raw: String) -> String {
        var s = raw
        let ig = String.CompareOptions.caseInsensitive
        let pairs: [(String, String)] = [
            ("[/thought]", "[thought: false]"),
            ("\u{003C}/redacted_reasoning\u{003E}", "[thought: false]"),
            ("\u{003C}redacted_reasoning\u{003E}", "[thought: true]"),
            ("\u{003C}/thinking\u{003E}", "[thought: false]"),
            ("\u{003C}thinking\u{003E}", "[thought: true]"),
        ]
        for (a, b) in pairs {
            s = s.replacingOccurrences(of: a, with: b, options: ig, range: nil)
        }
        return s
    }
    
    // MARK: - Peel leaked final answer from reasoning
    
    /// When the model leaves prose that reads like the user-facing reply inside the reasoning span,
    /// move it to the answer (after existing answer prefix).
    private static func peelFinalAnswerOutOfReasoning(
        reasoning: String?,
        answer: String,
        isStreaming: Bool,
        usesExplicitThoughtDelimiters: Bool,
        preferAnswerBeforeReasoning: Bool,
    ) -> ParsedAgentDisplay {
        guard var r = reasoning?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
            return ParsedAgentDisplay(
                reasoningText: reasoning,
                answerText: answer,
                usesExplicitThoughtDelimiters: usesExplicitThoughtDelimiters,
                preferAnswerBeforeReasoning: preferAnswerBeforeReasoning,
            )
        }
        var a = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        if !isStreaming, reasoningIsEntirelyFinalizeStatusBlob(r) {
            a = appendAnswerSegment(prefix: a, suffix: r)
            r = ""
            let finalR: String? = r.isEmpty ? nil : r
            let finalA = a.isEmpty ? " " : a
            return ParsedAgentDisplay(
                reasoningText: finalR,
                answerText: finalA,
                usesExplicitThoughtDelimiters: usesExplicitThoughtDelimiters,
                preferAnswerBeforeReasoning: preferAnswerBeforeReasoning,
            )
        }

        struct PeelRule {
            let regex: NSRegularExpression
            let minTailChars: Int
        }

        if usesExplicitThoughtDelimiters {
            // Inside `[thought: true]…` the model writes normal Markdown (headings, **bold**, numbered steps).
            // Broad “answer leak” heuristics match that prose and dump the whole thought into `answerText`,
            // which makes the Thinking UI disappear. Only peel obvious status / finalize tails here.
            let narrowRules: [PeelRule] = [
                PeelRule(regex: finalizeStatusBreakRegex, minTailChars: isStreaming ? 24 : 10),
            ]
            for rule in narrowRules {
                if let (head, tail) = splitReasoningAtFirstMatch(r, regex: rule.regex, minTailChars: rule.minTailChars) {
                    r = head.trimmingCharacters(in: .whitespacesAndNewlines)
                    a = appendAnswerSegment(prefix: a, suffix: tail)
                }
            }
        } else {
            // Tool-preamble path (no explicit thought tags): keep stronger peels to lift a real reply out.
            var rules: [PeelRule] = [
                PeelRule(regex: markdownHeadingBreakRegex, minTailChars: 14),
                PeelRule(regex: horizontalRuleBreakRegex, minTailChars: 16),
                PeelRule(regex: boldLeadBreakRegex, minTailChars: 18),
                PeelRule(regex: numberedListBreakRegex, minTailChars: isStreaming ? 28 : 22),
                PeelRule(regex: conversationalAnswerBreakRegex, minTailChars: isStreaming ? 20 : 14),
                PeelRule(regex: finalizeStatusBreakRegex, minTailChars: isStreaming ? 24 : 10),
            ]
            for rule in rules {
                if let (head, tail) = splitReasoningAtFirstMatch(r, regex: rule.regex, minTailChars: rule.minTailChars) {
                    r = head.trimmingCharacters(in: .whitespacesAndNewlines)
                    a = appendAnswerSegment(prefix: a, suffix: tail)
                }
            }

            if let (head, tail) = peelTailAfterLeadingToolRunIfAnswerLike(r, isStreaming: isStreaming) {
                r = head.trimmingCharacters(in: .whitespacesAndNewlines)
                a = appendAnswerSegment(prefix: a, suffix: tail)
            }
        }

        let finalR: String? = r.isEmpty ? nil : r
        let finalA = a.isEmpty ? " " : a
        return ParsedAgentDisplay(
            reasoningText: finalR,
            answerText: finalA,
            usesExplicitThoughtDelimiters: usesExplicitThoughtDelimiters,
            preferAnswerBeforeReasoning: preferAnswerBeforeReasoning,
        )
    }

    /// Whole reasoning string is only a short “finalizing / wrapping up” banner (no real thought body).
    private static func reasoningIsEntirelyFinalizeStatusBlob(_ reasoning: String) -> Bool {
        let t = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 420 else { return false }
        let ns = t as NSString
        let len = ns.length
        let full = NSRange(location: 0, length: len)
        guard let m = reasoningIsOnlyFinalizeStatusRegex.firstMatch(in: t, options: [], range: full) else { return false }
        return NSEqualRanges(m.range, full)
    }
    
    private static func splitReasoningAtFirstMatch(
        _ reasoning: String,
        regex: NSRegularExpression,
        minTailChars: Int,
    ) -> (head: String, tail: String)? {
        let ns = reasoning as NSString
        let len = ns.length
        guard len > 0 else { return nil }
        let range = NSRange(location: 0, length: len)
        guard let m = regex.firstMatch(in: reasoning, options: [], range: range),
              m.range.location > 0
        else { return nil }
        
        let splitUTF16 = m.range.location
        let head = ns.substring(with: NSRange(location: 0, length: splitUTF16))
        let tail = ns.substring(from: splitUTF16)
        let tailTrim = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tailTrim.count >= minTailChars else { return nil }
        return (head, tailTrim)
    }
    
    private static func appendAnswerSegment(prefix: String, suffix: String) -> String {
        let p = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return p.isEmpty ? " " : p }
        if p.isEmpty { return s }
        return p + "\n\n" + s
    }
    
    /// After `• tool` split, the "answer" may still start with a heading that should stay in the main body only.
    private static func peelAnswerTailFromReasoning(_ split: ParsedAgentDisplay, isStreaming: Bool) -> ParsedAgentDisplay {
        peelFinalAnswerOutOfReasoning(
            reasoning: split.reasoningText,
            answer: split.answerText,
            isStreaming: isStreaming,
            usesExplicitThoughtDelimiters: split.usesExplicitThoughtDelimiters,
            preferAnswerBeforeReasoning: split.preferAnswerBeforeReasoning,
        )
    }
    
    // MARK: - Leading `• tool` lines
    
    private static func splitLeadingToolProgressLines(_ raw: String) -> ParsedAgentDisplay? {
        guard let (tools, rest) = partitionLeadingToolLines(raw) else { return nil }
        let reasoningJoined = tools.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reasoningJoined.isEmpty else { return nil }
        
        let restTrim = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = restTrim.isEmpty ? " " : restTrim
        return ParsedAgentDisplay(
            reasoningText: reasoningJoined,
            answerText: answer,
            usesExplicitThoughtDelimiters: false,
            preferAnswerBeforeReasoning: false,
        )
    }
    
    /// Leading `• tool` lines and everything after (trimmed rest may be empty).
    private static func partitionLeadingToolLines(_ raw: String) -> (tools: String, rest: String)? {
        let lines = raw.components(separatedBy: "\n")
        var i = lines.startIndex
        while i < lines.endIndex, lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
            i = lines.index(after: i)
        }
        guard i < lines.endIndex else { return nil }
        
        let first = lines[i]
        let firstLen = (first as NSString).length
        guard firstLen > 0,
              toolProgressLineRegex.firstMatch(in: first, range: NSRange(location: 0, length: firstLen)) != nil
        else { return nil }
        
        var chunk: [String] = []
        while i < lines.endIndex {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if chunk.isEmpty {
                    i = lines.index(after: i)
                    continue
                }
                let nextIdx = lines.index(after: i)
                if nextIdx < lines.endIndex {
                    let next = lines[nextIdx]
                    let nextLen = (next as NSString).length
                    let nextIsTool = nextLen > 0
                    && toolProgressLineRegex.firstMatch(in: next, range: NSRange(location: 0, length: nextLen)) != nil
                    if nextIsTool {
                        chunk.append(line)
                        i = lines.index(after: i)
                        continue
                    }
                }
                break
            }
            let len = (line as NSString).length
            let isTool = len > 0
            && toolProgressLineRegex.firstMatch(in: line, range: NSRange(location: 0, length: len)) != nil
            if isTool {
                chunk.append(line)
                i = lines.index(after: i)
                continue
            }
            break
        }
        
        let toolsJoined = chunk.joined(separator: "\n")
        let rest = lines[i...].joined(separator: "\n")
        return (toolsJoined, rest)
    }
    
    private static let numberedLineStartRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\d+\.\s"#)
    }()
    
    /// If reasoning is `• tools…` then user-facing prose, peel the prose when it clearly belongs in the answer.
    private static func peelTailAfterLeadingToolRunIfAnswerLike(
        _ reasoning: String,
        isStreaming: Bool,
    ) -> (head: String, tail: String)? {
        guard let (tools, rest) = partitionLeadingToolLines(reasoning) else { return nil }
        let tailT = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tailT.isEmpty else { return nil }
        
        let minLen = isStreaming ? 40 : 28
        if tailT.count < minLen {
            let allowShortFinalize = !isStreaming && tailOpensWithFinalizeBannerLine(tailT)
            guard allowShortFinalize else { return nil }
        }

        if reasoningContainsToolLine(tailT) { return nil }

        if isStreaming {
            // While streaming, only peel obvious answer tails so we don't steal in-progress "planning" prose.
            guard tailOpensWithStrongAnswerMarker(tailT) else { return nil }
        } else if !tailOpensLikeAnswerLead(tailT) {
            guard tailT.count >= 160 else { return nil }
        }
        
        let head = tools.trimmingCharacters(in: .whitespacesAndNewlines)
        return (head, tailT)
    }
    
    private static func reasoningContainsToolLine(_ text: String) -> Bool {
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            let len = (line as NSString).length
            if len > 0, toolProgressLineRegex.firstMatch(in: line, range: NSRange(location: 0, length: len)) != nil {
                return true
            }
        }
        return false
    }
    
    private static func tailOpensWithFinalizeBannerLine(_ tail: String) -> Bool {
        let firstLineRaw = tail.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let firstLine = firstLineRaw.trimmingCharacters(in: .whitespaces)
        let fl = (firstLine as NSString).length
        guard fl > 0 else { return false }
        return finalizeLeadSingleLineRegex.firstMatch(
            in: firstLine,
            options: [],
            range: NSRange(location: 0, length: fl),
        ) != nil
    }

    private static func tailOpensWithStrongAnswerMarker(_ tail: String) -> Bool {
        let t = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") || t.hasPrefix("**") { return true }
        let firstLineRaw = t.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let firstLine = firstLineRaw.trimmingCharacters(in: .whitespaces)
        let fl = (firstLine as NSString).length
        if fl > 0, numberedLineStartRegex.firstMatch(in: firstLine, range: NSRange(location: 0, length: fl)) != nil {
            return true
        }
        let probe = String(t.prefix(320))
        if conversationalAnswerBreakRegex.firstMatch(
            in: "\n\n" + probe,
            options: [],
            range: NSRange(location: 0, length: ("\n\n" + probe as NSString).length),
        ) != nil {
            return true
        }
        return false
    }
    
    private static func tailOpensLikeAnswerLead(_ tail: String) -> Bool {
        if tailOpensWithFinalizeBannerLine(tail) { return true }
        if tailOpensWithStrongAnswerMarker(tail) { return true }
        let t = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        let probe = String(t.prefix(200))
        return conversationalAnswerBreakRegex.firstMatch(
            in: "\n\n" + probe,
            options: [],
            range: NSRange(location: 0, length: ("\n\n" + probe as NSString).length),
        ) != nil
    }
}
