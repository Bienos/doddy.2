import DoddyCore
import SwiftUI

/// Settings → Doddy on the web (ADR-600). The iPhone vouches for a browser: it shows a one-time code
/// and the web address to type it at, and lists the browsers signed in to this account, each with
/// Sign out. Below that, what the person chooses to keep on Doddy's server (`WebMemorySection`, ADR-603). The rules are `WebSignInModel` in DoddyCore, tested on Linux; this file only draws them.
struct WebSignInScreen: View {
    @State private var model = WebSignInModel(
        makeClient: { await WebLinkClientFactory.ready() },
        renewClient: { await WebLinkClientFactory.renewed() },
        // ADR-818: Apple and Google open in the system sign-in sheet, as Connected Apps do.
        authenticator: SystemWebAuthenticator(),
        // ADR-819: this iPhone's own device ID, so the server knows which iPhone uses which account.
        deviceID: { DeviceSession.deviceID() })

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

            // ADR-819: this iPhone using an account made on the web (or another iPhone's).
            WebDeviceAccountSection(model: model)

            // ADR-818: Apple and Google as a second way in on the web. Hidden when the server offers neither.
            WebSignInMethodsSection(model: model)

            Section {
                browsersContent
                if let problem = model.signOutProblem {
                    WebProblemText(problem: problem)
                        .accessibilityIdentifier("web.signOutProblem")
                }
            } header: {
                Text("Signed-in browsers")
            } footer: {
                Text("A browser stays signed in for 30 days, or until it goes unused for 14. It sees the files Doddy made, your online accounts and Doddy's receipts. It sees your notes and conversations only if you keep them on Doddy's server, below.")
            }

            // ADR-603: notes and conversations kept on Doddy's server, off unless turned on here.
            WebMemorySection()

            // ADR-602: Logbook's counts, on unless turned off here (decision 2026-11-09-usage-counts-on-by-default).
            LogbookSection()
        }
        .navigationTitle("Doddy on the web")
        .task {
            await model.refreshDeviceAccount()
            await model.refreshBrowsers()
            await model.refreshMethods()
        }
        .refreshable {
            await model.refreshDeviceAccount()
            await model.refreshBrowsers()
            await model.refreshMethods()
        }
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

/// ADR-819: which account this iPhone uses. "Sign in with Google" switches this iPhone to the account
/// of that Google sign-in (made on the web, or another iPhone's); "Use this iPhone's own account" goes
/// back. Nothing moves between accounts. Hidden when the server offers neither Google nor Apple.
private struct WebDeviceAccountSection: View {
    let model: WebSignInModel

    var body: some View {
        if !model.joinProviders.isEmpty || model.deviceAccount.map({ if case .joined = $0 { true } else { false } }) == true {
            Section {
                if case .joined(let account) = model.deviceAccount {
                    VStack(alignment: .leading, spacing: 6) {
                        switch account.provider {
                        case .google: Text("This iPhone uses your Doddy account from Google.")
                        case .apple: Text("This iPhone uses your Doddy account from Apple.")
                        }
                        HStack(spacing: 4) {
                            Text("Since")
                            Text(account.since, format: .dateTime.day().month().year())
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityElement(children: .combine)
                    }
                    Button {
                        Task { await model.leaveJoinedAccount() }
                    } label: {
                        if model.leaving { ProgressView() } else { Text("Use this iPhone's own account") }
                    }
                    .disabled(model.leaving)
                    .accessibilityIdentifier("web.leaveAccount")
                } else {
                    ForEach(model.joinProviders, id: \.self) { provider in
                        Button {
                            Task { await model.joinAccount(with: provider) }
                        } label: {
                            if model.joining == provider {
                                HStack(spacing: 12) {
                                    ProgressView()
                                    Text("Opening the sign-in…")
                                }
                            } else {
                                switch provider {
                                case .google: Text("Sign in with Google")
                                case .apple: Text("Sign in with Apple")
                                }
                            }
                        }
                        .disabled(model.joining != nil)
                        .accessibilityIdentifier("web.join.\(provider.rawValue)")
                    }
                }
                if let outcome = model.joinOutcome {
                    WebJoinOutcomeText(outcome: outcome)
                        .accessibilityIdentifier("web.joinOutcome")
                }
            } header: {
                Text("Your account from the web")
            } footer: {
                Text("Made a Doddy account on the web with Google or Apple? Sign in with it here and this iPhone uses that account. What this iPhone's own account keeps on Doddy's server stays there; you can switch back. Notes on this iPhone stay on this iPhone.")
            }
        }
    }
}

private struct WebJoinOutcomeText: View {
    let outcome: WebSignInModel.JoinOutcome

    var body: some View {
        switch outcome {
        case .joined:
            Text("Done. This iPhone now uses that account.")
                .foregroundStyle(Theme.secondaryText)
        case .joinedRenewPending:
            Text("Done on Doddy's server. This iPhone switches the next time it connects.")
                .foregroundStyle(Theme.secondaryText)
        case .own:
            Text("That is already this iPhone's own account. Nothing changed.")
                .foregroundStyle(Theme.secondaryText)
        case .notLinked:
            Text("That account has no Doddy account yet. Make one on Doddy's web page first, or use Link below to add it to this iPhone's account.")
                .foregroundStyle(Theme.error)
        case .canceled:
            Text("Sign-in was cancelled. Nothing changed.")
                .foregroundStyle(Theme.secondaryText)
        case .busy:
            Text("Too many tries. Wait a few minutes, then try again.")
                .foregroundStyle(Theme.error)
        case .failed:
            Text("That sign-in didn't finish. Nothing changed. Try again.")
                .foregroundStyle(Theme.error)
        case .problem(let problem):
            WebProblemText(problem: problem)
        case .left:
            Text("This iPhone uses its own account again.")
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

/// Apple and Google linked to this account (ADR-818). Linking opens the system sign-in sheet; what
/// the section then shows is the server's answer and its list, read again, never a hoped-for state.
private struct WebSignInMethodsSection: View {
    let model: WebSignInModel

    var body: some View {
        switch model.methods {
        case .unavailable:
            EmptyView()
        case .loading:
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…")
                }
            } header: {
                Text("Sign in with Google or Apple")
            }
        case .failed(let problem):
            Section {
                WebProblemText(problem: problem)
                Button("Try again") {
                    Task { await model.refreshMethods() }
                }
            } header: {
                Text("Sign in with Google or Apple")
            }
        case .loaded(let offered, let linked):
            Section {
                ForEach(linked) { signIn in
                    WebLinkedRow(signIn: signIn, busy: model.unlinking.contains(signIn.id)) {
                        Task { await model.unlink(signIn.id) }
                    }
                }
                ForEach(offered.filter { provider in !linked.contains { $0.provider == provider } }, id: \.self) { provider in
                    Button {
                        Task { await model.link(provider) }
                    } label: {
                        if model.linking == provider {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Opening the sign-in…")
                            }
                        } else {
                            switch provider {
                            case .google: Text("Link Google")
                            case .apple: Text("Link Apple")
                            }
                        }
                    }
                    .disabled(model.linking != nil)
                    .accessibilityIdentifier("web.link.\(provider.rawValue)")
                }
                if let outcome = model.linkOutcome {
                    WebLinkOutcomeText(outcome: outcome)
                        .accessibilityIdentifier("web.linkOutcome")
                }
                if let problem = model.linkProblem {
                    WebProblemText(problem: problem)
                }
            } header: {
                Text("Sign in with Google or Apple")
            } footer: {
                Text("Link Google or Apple once, then choose it on Doddy's web sign-in page instead of typing a code. It opens this same account; nothing is copied or merged. The code keeps working.")
            }
        }
    }
}

private struct WebLinkedRow: View {
    let signIn: WebLinkedSignIn
    let busy: Bool
    let unlink: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                switch signIn.provider {
                case .google: Text(verbatim: "Google")
                case .apple: Text(verbatim: "Apple")
                }
            }
            .font(.body.weight(.semibold))
            HStack(spacing: 4) {
                Text("Linked")
                Text(signIn.linkedAt, format: .dateTime.day().month().year())
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityElement(children: .combine)
            Button(role: .destructive, action: unlink) {
                if busy {
                    ProgressView()
                } else {
                    Text("Unlink")
                }
            }
            .disabled(busy)
            .accessibilityIdentifier("web.unlink")
        }
        .padding(.vertical, 2)
    }
}

/// What the server said about the link. Only `linked` and `already` say it is linked.
private struct WebLinkOutcomeText: View {
    let outcome: WebLinkOutcome

    var body: some View {
        switch outcome {
        case .linked:
            Text("Linked. Next time, choose it on Doddy's web sign-in page.")
                .foregroundStyle(Theme.secondaryText)
        case .already:
            Text("It was already linked to this account.")
                .foregroundStyle(Theme.secondaryText)
        case .taken:
            Text("That account is already linked to another Doddy account (perhaps one made on the web), so it wasn't linked here. Nothing was merged.")
                .foregroundStyle(Theme.error)
        case .canceled:
            Text("Linking was cancelled. Nothing changed.")
                .foregroundStyle(Theme.secondaryText)
        case .busy:
            Text("Too many tries. Wait a few minutes, then try again.")
                .foregroundStyle(Theme.error)
        case .failed, .notLinked:
            Text("Linking didn't finish. Nothing changed. Try again.")
                .foregroundStyle(Theme.error)
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
