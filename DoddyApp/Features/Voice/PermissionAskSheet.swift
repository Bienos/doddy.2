import DoddyCore
import SwiftUI

/// "Let Doddy use Calendar?" (ADR-562). Slides up over the conversation when Doddy needs an Apple
/// app that is off, so the user can allow it right there instead of finding Settings. It shows why
/// now (what Doddy was asked to do) and what leaves the phone. Allow turns the connection on, and
/// iOS shows its own prompt the first time; Not now (or a swipe down) answers the agent and isn't
/// asked again in this conversation. When iOS has refused, only iPhone Settings can change it, so
/// the sheet offers that instead of a button that can't work.
struct PermissionAskSheet: View {
    let request: VoiceSessionController.PermissionRequest
    let onAllow: () -> Void
    let onDecline: () -> Void

    var body: some View {
        let info = ConnectionInfo.of(request.connection)
        let title = request.connection.title
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: info.symbol)
                        .font(.title2)
                        .foregroundStyle(Theme.ink)
                        .frame(width: 52, height: 52)
                        .background(Theme.quietSurface, in: Circle())
                        .accessibilityHidden(true)
                    Group {
                        switch request.kind {
                        case .turnOn: Text("Let Doddy use \(title)?")
                        case .openSettings: Text("\(title) is off for Doddy in iPhone Settings")
                        }
                    }
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                }

                if let card = request.askCard {
                    asked {
                        Text(card.title)
                        ForEach(card.lines, id: \.self) { line in
                            Text(line).foregroundStyle(Theme.secondaryText)
                        }
                    }
                } else if let reason = request.reason {
                    asked { Text(reason) }
                }

                switch request.kind {
                case .turnOn:
                    Text(info.leavesPhone)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Text("iPhone may ask you once too. You can turn it off any time in Settings, Connections.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if request.askCard != nil {
                        Text("Allow also says yes to this one look-up.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Button(action: onAllow) {
                        Label("Allow \(title)", systemImage: "checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("permission.allow")
                case .openSettings:
                    Text("iPhone has \(title) turned off for Doddy. Only you can turn it back on, in iPhone Settings.")
                        .foregroundStyle(Theme.secondaryText)
                    Button("Open iPhone Settings", action: onAllow)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("permission.openSettings")
                }
                Button("Not now", action: onDecline)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("permission.notNow")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
    }

    /// What Doddy was asked to do, so the user sees why it asks now.
    private func asked<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Doddy was asked to")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.secondaryText)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
