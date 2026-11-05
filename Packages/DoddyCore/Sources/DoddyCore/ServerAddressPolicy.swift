import Foundation

/// Which Doddy server address the app may send its device ID and session to (ADR-720).
///
/// The device ID is the credential that mints session tokens on the server, and it stays in the
/// Keychain across a reinstall, so a typed string must not decide where it goes in a shipped build.
/// There the built-in address is the only one (the messaging server's address has worked the same
/// way since ADR-175). A development build may point somewhere else, but only over https, or over
/// http to this computer (the Simulator talking to a server on the same Mac).
///
/// iPhone only in practice (`DeviceSession`); DoddyCore holds it so the rule is tested on Linux.
public enum ServerAddressPolicy {
    /// The hosts that name this computer; only these may be reached without https, and only in a
    /// development build.
    static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    /// True when the app may talk to `url`: https with a host, or (development builds only) http to
    /// this computer. An address with a user name or password in it is never accepted: in
    /// `https://trusted.example@other.example` the host is the part after the `@`.
    public static func accepts(_ url: URL, debug: Bool) -> Bool {
        guard url.user == nil, url.password == nil, let host = hostName(of: url) else { return false }
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return debug && loopbackHosts.contains(host)
        default: return false
        }
    }

    /// The server address to use: the one built into the app, unless this is a development build
    /// and an address was typed in Settings. A typed address that `accepts` refuses gives nil (the
    /// screens then say the server isn't set up), never a silent fall back to another address.
    public static func resolve(typed: String?, builtIn: String?, debug: Bool) -> URL? {
        let typedText = (typed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let builtInText = (builtIn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = debug && !typedText.isEmpty ? typedText : builtInText
        guard !text.isEmpty, let url = URL(string: text), accepts(url, debug: debug) else { return nil }
        return url
    }

    /// Lower case, without the brackets of an IPv6 literal.
    private static func hostName(of url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return host.isEmpty ? nil : host
    }
}
