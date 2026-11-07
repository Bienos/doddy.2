import DoddyCore
import SwiftUI

/// A small phone icon on Home while Doddy has a call going for the person (owner, 2026-11-05: calls
/// should be invisible, one small mark on Home, then only the recap afterwards). It shows nothing
/// otherwise. It is a mark, not a screen: no transcript, name or number appears on Home, so nothing
/// private is readable over a shoulder. A tap opens "Calls for you", where the live call, Przejmij
/// and Zakończ still are.
///
/// It reads the calls kept on this iPhone (`callCaseRepository`), the same ones the list shows, and
/// looks again every few seconds while Home is on screen. A call the server still holds but this
/// iPhone has not heard about yet shows when the list next syncs (Settings › Phone calls).
///
/// NOT COMPILED here (no Xcode in the session that wrote it).
struct ActiveCallBadge: View {
    @Environment(\.appEnvironment) private var environment
    @State private var active = false
    @State private var showCalls = false

    var body: some View {
        Group {
            if active {
                Button { showCalls = true } label: {
                    Image(systemName: "phone.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Theme.quietSurface, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
                .accessibilityLabel("Doddy is making a call for you")
                .accessibilityIdentifier("home.activeCall")
            }
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .sheet(isPresented: $showCalls) {
            NavigationStack {
                CallCasesView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showCalls = false }
                        }
                    }
            }
        }
    }

    /// A read that fails leaves the icon as it was: a failed read is never shown as "no call".
    private func refresh() async {
        guard let cases = try? await environment.callCaseRepository.list() else { return }
        active = cases.contains { Self.isInProgress($0) }
    }

    /// Approved and not finished: the same "active" the calls list syncs (`CallCasesModel`).
    static func isInProgress(_ record: StoredCallCase) -> Bool { record.state == "active" }
}
