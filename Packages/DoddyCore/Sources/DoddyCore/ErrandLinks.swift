import Foundation

// Links in a task handed over (ADR-716). Doddy's server reads the web for a task and can open any
// link it finds in the task's text, on any site. So text the agent read on a web page or in an email
// must not be able to put a link there. The user's words and Doddy's note never need one: the
// server finds its own pages. The phone refuses first, with a message that tells the agent to send
// the task again without links; the server refuses the same shapes (ADR-703) and checks again, so
// this is not the only line.
//
// Refused: a web address with a scheme (any "scheme://", in any case), "www.", a site name followed
// by a path, a query or a fragment (example.com/page, shop.pl?q=1), an IP address, `javascript:`,
// a `data:` address, and a markdown link. The spellings that dodge a plain match are folded first:
// full-width letters, invisible characters, a backslash for a slash, "[.]" or "(dot)" for a dot,
// and %2F-style escapes (also escaped twice). A bare site name such as allegro.pl, with nothing
// after it, stays allowed: the user may well say "check allegro.pl".

public enum LinkShape {
    /// True when `text` holds a link in one of the shapes above.
    public static func isIn(_ text: String) -> Bool {
        let flat = folded(text)
        let whole = NSRange(flat.startIndex..., in: flat)
        return patterns.contains { $0.firstMatch(in: flat, options: [], range: whole) != nil }
    }

    // MARK: Folding

    /// The text with the common ways of hiding a link removed, so the patterns below see it plainly.
    static func folded(_ text: String) -> String {
        // Full-width and other compatibility forms ("ｈｔｔｐｓ：／／") become plain ASCII.
        var out = text.precomposedStringWithCompatibilityMapping
        // Invisible characters can't split a scheme or a name in two.
        out = String(String.UnicodeScalarView(out.unicodeScalars.filter { !isInvisible($0) }))
        // Dots and slashes that look different but mean the same to a web address.
        for stop in ["\u{3002}", "\u{FF61}"] { out = out.replacingOccurrences(of: stop, with: ".") }
        for slash in ["\u{2044}", "\u{2215}", "\u{29F8}"] { out = out.replacingOccurrences(of: slash, with: "/") }
        // Escapes of the characters that make an address, opened up to three times over (%252F is a slash).
        for _ in 0..<3 {
            for (escaped, plain) in escapes { out = out.replacingOccurrences(of: escaped, with: plain, options: .caseInsensitive) }
            out = openingNumberedEntities(out)
        }
        // A browser reads a backslash as a slash.
        out = out.replacingOccurrences(of: "\\", with: "/")
        // Written-out punctuation: example[.]com, example(dot)com, https[:]//…
        for (spelled, plain) in defanged { out = out.replacingOccurrences(of: spelled, with: plain, options: .caseInsensitive) }
        return out
    }

    private static let defanged: [(String, String)] = [
        ("[.]", "."), ("(.)", "."), ("{.}", "."), ("[dot]", "."), ("(dot)", "."), ("{dot}", "."),
        ("[:]", ":"), ("(:)", ":"), ("[/]", "/"), ("(/)", "/"),
    ]

    /// `%25` first, so a twice-escaped slash (%252F) is a slash after the next pass; and the named
    /// entities of the same characters.
    private static let escapes: [(String, String)] = [
        ("%25", "%"), ("%2F", "/"), ("%3A", ":"), ("%2E", "."), ("%5C", "\\"),
        ("&sol;", "/"), ("&period;", "."), ("&colon;", ":"), ("&bsol;", "\\"),
    ]

    /// `&#47;` and `&#x2f;` become the character, when it is a printable ASCII one.
    private static func openingNumberedEntities(_ text: String) -> String {
        guard text.contains("&#"), let entity = try? NSRegularExpression(pattern: #"&#(x[0-9a-f]{1,2}|\d{1,3});"#, options: [.caseInsensitive])
        else { return text }
        var out = ""
        var last = text.startIndex
        for match in entity.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let digits = Range(match.range(at: 1), in: text) else { continue }
            let code = text[digits].lowercased().hasPrefix("x") ? Int(text[digits].dropFirst(), radix: 16) : Int(text[digits])
            out += text[last..<whole.lowerBound]
            if let code, (0x20..<0x7F).contains(code), let scalar = Unicode.Scalar(code) {
                out.unicodeScalars.append(scalar)
            } else {
                out += text[whole]
            }
            last = whole.upperBound
        }
        return out + text[last...]
    }

    /// Format characters (zero-width space and joiners, bidi marks, soft hyphen, BOM, word joiner),
    /// variation selectors and a few fillers: nothing a person reads, everything that can split a word.
    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.generalCategory == .format { return true }
        switch scalar.value {
        case 0x034F, 0x115F, 0x1160, 0x180B...0x180D, 0x3164, 0xFE00...0xFE0F, 0xFFA0: return true
        default: return false
        }
    }

    // MARK: The shapes

    /// A site name's parts: a label (letters of any script, digits, hyphens) and an ending (letters,
    /// or a punycode one).
    private static let label = #"[\p{L}\p{N}\-]+"#
    private static let ending = #"(?:[a-z]{2,}|xn--[a-z0-9\-]{2,})"#
    private static let octet = #"(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)"#

    /// Internal so a test can check that every pattern compiled: a broken one would silently check nothing.
    static let sources: [String] = [
        // https://…, HTTPS://…, ftp://…, hxxps://… : any scheme followed by "://".
        #"[a-z][a-z0-9+.\-]*://"#,
        // www. and www2.
        #"(?<![a-z0-9])www\d{0,3}\."#,
        // A site name with a path, a query or a fragment, no scheme: example.com/page, a.b.co.uk:8080/x,
        // shop.pl?q=1. A name on its own (allegro.pl) is not matched.
        "\(label)\\.\(ending)(?::\\d{1,5})?(?:/|[?#]\\S)",
        // An IPv4 address, written in decimals or as hex parts, with or without a path.
        "(?<![\\d.])\(octet)(?:\\.\(octet)){3}(?!\\d)(?!\\.\\d)",
        #"(?<![\w.])0x[0-9a-f]+(?:\.(?:0x[0-9a-f]+|\d+)){3}(?![\w])"#,
        // An IPv6 address in brackets, short ("::1") or in full.
        #"\[(?:[0-9a-f:.]*::[0-9a-f:.]*|(?:[0-9a-f]{1,4}:){7}[0-9a-f]{1,4})\]"#,
        // javascript:alert(1), vbscript:…
        #"(?<![a-z0-9])(?:javascript|vbscript)\s*:\S"#,
        // data:text/html,… and data:…;base64,… (not the word "data:" in "data: 12 listopada").
        #"(?<![a-z0-9])data:(?:[a-z0-9.+\-]+/[a-z0-9.+\-]+|;base64|,)"#,
        // [text](target): a bracket, a bracket, and a target that looks like an address or a path.
        #"\[[^\]\n]*\]\(\s*<?[^\s()<>]*[/.:#?@][^\s()<>]*"#,
    ]

    static let patterns: [NSRegularExpression] = sources.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }
}
