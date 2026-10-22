import DoddyCore
import SwiftUI

/// Settings → Doddy on the web (ADR-579). The iPhone vouches for a browser: it shows a one-time code
/// and the web address to type it at, and lists the browsers signed in to this account, each with
/// Sign out. The rules are `WebSignInModel` in DoddyCore, tested on Linux; this file only draws them.
struct WebSignInScreen: View {
    @State private var model = WebSignInModel(
        makeClient: { await WebLinkClientFactory.ready() },
        renewClient: { await WebLinkClientFactory.renewed() })

    var body: some View {
        WebSignInView(model: model)
    }
}

struct WebSignInView: View {
    let model: WebSignInModel

    var body: some View {
        List {
            Section {
                codeContent
            } header: {
                Text("Sign in on a computer")
            } footer: {
                Text("Open Doddy's web address in a browser and type the code there. It works once, for five minutes. Doddy will never ask you to read it out or send it to anyone.")
            }

            Section {
                browsersContent
                if let problem = model.signOutProblem {
                    WebProblemText(problem: problem)
                        .accessibilityIdentifier("web.signOutProblem")
                }
            } header: {
                Text("Signed-in browsers")
            } footer: {
                Text("A browser stays signed in for 30 days, or until it goes unused for 14. It sees the files Doddy made, your online accounts and Doddy's receipts, never your saved notes.")
            }
        }
        .navigationTitle("Doddy on the web")
        .task { await model.refreshBrowsers() }
        .refreshable { await model.refreshBrowsers() }
    }

    @ViewBuilder private var codeContent: some View {
        switch model.code {
        case .none:
            Button("Get a sign-in code") {
                Task { await model.getCode() }
            }
            .accessibilityIdentifier("web.getCode")
        case .asking:
            HStack(spacing: 12) {
                ProgressView()
                Text("Getting a code…")
            }
        case .shown(let code):
            WebCodeCard(code: code, onExpired: { model.expireCode(now: Date()) })
            Button("Get a new code") {
                Task { await model.getCode() }
            }
        case .failed(let problem):
            WebProblemText(problem: problem)
            Button("Try again") {
                Task { await model.getCode() }
            }
        }
    }

    @ViewBuilder private var browsersContent: some View {
        switch model.browsers {
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading…")
            }
        case .failed(let problem):
            WebProblemText(problem: problem)
            Button("Try again") {
                Task { await model.refreshBrowsers() }
            }
        case .loaded(let sessions) where sessions.isEmpty:
            Text("No browser is signed in.")
                .foregroundStyle(Theme.secondaryText)
        case .loaded(let sessions):
            ForEach(sessions) { session in
                WebBrowserRow(
                    session: session,
                    busy: model.signingOut.contains(session.id),
                    signOut: { Task { await model.signOut(session.id) } })
            }
        }
    }
}

/// The code, big and spelled out to VoiceOver, the address to type it at, and the time left.
private struct WebCodeCard: View {
    let code: WebLinkCode
    let onExpired: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = code.secondsLeft(at: context.date)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: code.code)
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .textSelection(.enabled)
                    .speechSpellsOutCharacters()
                    .accessibilityIdentifier("web.code")
                Text("Type it at")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Text(verbatim: code.displayAddress)
                    .font(.headline)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("web.address")
                HStack(spacing: 4) {
                    Text("Works for")
                    Text(verbatim: String(format: "%ld:%02ld", left / 60, left % 60))
                        .monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityElement(children: .combine)
            }
            .padding(.vertical, 4)
            .onChange(of: left == 0) { _, expired in
                if expired { onExpired() }
            }
        }
    }
}

private struct WebBrowserRow: View {
    let session: WebBrowserSession
    let busy: Bool
    let signOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            (browserName + Text(verbatim: " · ") + systemName)
                .font(.body.weight(.semibold))
            HStack(spacing: 4) {
                Text("Last used")
                Text(session.lastSeenAt, format: .dateTime.day().month().hour().minute())
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityElement(children: .combine)
            Button(role: .destructive, action: signOut) {
                if busy {
                    ProgressView()
                } else {
                    Text("Sign out")
                }
            }
            .disabled(busy)
            .accessibilityIdentifier("web.signOut")
        }
        .padding(.vertical, 2)
    }

    private var browserName: Text {
        switch session.browser {
        case .chrome: Text(verbatim: "Chrome")
        case .edge: Text(verbatim: "Edge")
        case .firefox: Text(verbatim: "Firefox")
        case .safari: Text(verbatim: "Safari")
        case .opera: Text(verbatim: "Opera")
        case .other: Text("A browser")
        }
    }

    private var systemName: Text {
        switch session.system {
        case .macos: Text(verbatim: "macOS")
        case .windows: Text(verbatim: "Windows")
        case .ios: Text(verbatim: "iPhone")
        case .ipados: Text(verbatim: "iPad")
        case .android: Text(verbatim: "Android")
        case .linux: Text(verbatim: "Linux")
        case .chromeos: Text(verbatim: "ChromeOS")
        case .other: Text("another system")
        }
    }
}

/// What went wrong, in the person's language. Nothing here claims an action happened.
private struct WebProblemText: View {
    let problem: WebSignInModel.Problem

    var body: some View {
        Group {
            switch problem {
            case .notConfigured:
                Text("Doddy on the web needs Doddy's server, which isn't set up in this build.")
            case .signedOut:
                Text("Doddy's server didn't accept this iPhone. Try again in a moment.")
            case .tooMany:
                Text("Too many codes this hour. Try again later.")
            case .offline:
                Text("Doddy's server couldn't be reached. Check your connection and try again.")
            case .unreadable:
                Text("Doddy's server sent something the app couldn't read, so nothing is shown.")
            case .server:
                Text("Something went wrong on Doddy's server. Nothing was changed.")
            }
        }
        .foregroundStyle(Theme.error)
    }
}
