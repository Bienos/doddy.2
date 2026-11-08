import Foundation

/// Which commit a build was made from (7 Nov 2026 audit: "the git commit in Info.plist"). Xcode Cloud
/// writes its CI_COMMIT into the `DODDY_GIT_COMMIT` build setting (`ci_scripts/ci_post_clone.sh`),
/// and Info.plist carries it as `DoddyGitCommit`. Any other build carries `local`. Settings › About
/// shows the short form next to the version, so a TestFlight build can be traced to its code.
public enum BuildCommit {
    /// The first seven characters of a commit, or nil when the value isn't one: `local`, an
    /// unexpanded `$(DODDY_GIT_COMMIT)`, empty, or anything else that isn't 7 to 40 hex characters.
    public static func short(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              (7...40).contains(value.count),
              value.allSatisfy({ $0.isASCII && $0.isHexDigit && !$0.isUppercase })
        else { return nil }
        return String(value.prefix(7))
    }

    /// "0.1.0 (12, 8f3c2a1)" for a build that knows its commit; "0.1.0 (12)" as before for one that
    /// doesn't. A missing version or build number reads "?".
    public static func versionText(version: String?, build: String?, commit: String?) -> String {
        let version = version ?? "?"
        let build = build ?? "?"
        guard let short = short(commit) else { return "\(version) (\(build))" }
        return "\(version) (\(build), \(short))"
    }
}
