import DoddyCore
import SwiftUI

/// Sign in with a code sent by email (decision 2026-11-08-required-account): no password, ever. Two
/// steps, both kept in `DoddyAccountModel` (tested in DoddyCore): the address, then the code from the
/// email. A new address makes a new account; a known one signs in. Shown inside the welcome's sign-in
/// sheet, in place of the buttons.
struct EmailCodeForm: View {
    let account: DoddyAccountModel
    /// Back to the Apple, Google and email buttons.
    let back: () -> Void

    @State private var email = ""
    @State private var code = ""
    @FocusState private var focused: Field?

    private enum Field { case email, code }

    var body: some View {
        VStack(spacing: 10) {
            switch account.emailStep {
            case .enterEmail: addressStep
            case .enterCode(let sentTo): codeStep(sentTo: sentTo)
            }
        }
        .disabled(account.isWorking)
        .onAppear { focused = account.emailStep == .enterEmail ? .email : .code }
        .onChange(of: account.emailStep) { _, step in
            code = ""
            focused = step == .enterEmail ? .email : .code
        }
    }

    private var addressStep: some View {
        Group {
            TextField("Your email address", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($focused, equals: .email)
                .onSubmit(send)
                .modifier(FieldLook())
                .accessibilityIdentifier("welcome.email.address")
            Button(action: send) {
                Text("Send me a code")
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Theme.canvas)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .disabled(EmailAddress.normalized(email) == nil)
            .accessibilityIdentifier("welcome.email.send")
            Button("Back", action: back)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome.email.back")
        }
    }

    private func codeStep(sentTo: String) -> some View {
        Group {
            // Supabase took the request; whether the email arrived only the inbox knows.
            Text(verbatim: String(format: NSLocalizedString("A code is on its way to %@. It works once, and only for a short time.", comment: "the email address"), sentTo))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Code from the email", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focused, equals: .code)
                .modifier(FieldLook())
                .accessibilityIdentifier("welcome.email.code")
            Button(action: verify) {
                Text("Sign in")
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Theme.canvas)
                    .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .disabled(EmailCode.normalized(code) == nil)
            .accessibilityIdentifier("welcome.email.signIn")
            Button("Use another email") { account.changeEmail() }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome.email.change")
        }
    }

    private func send() {
        guard EmailAddress.normalized(email) != nil else { return }
        Task { await account.sendEmailCode(email) }
    }

    private func verify() {
        guard EmailCode.normalized(code) != nil else { return }
        Task { await account.verifyEmailCode(code) }
    }
}

/// The text fields' look: the same height and shape as the sheet's buttons.
private struct FieldLook: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(Theme.canvas))
            .overlay(Capsule().stroke(Theme.ink.opacity(0.16), lineWidth: 1))
    }
}
