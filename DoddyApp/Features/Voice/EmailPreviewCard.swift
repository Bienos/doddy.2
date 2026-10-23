import DoddyCore
import SwiftUI

/// The email card (owner, 22 Oct 2026, ADR-597): To, Subject and the text as an email reads,
/// from the server's preview for exactly these arguments. Every value is the server's own line;
/// only the labels are the app's. Notes (a send can't be taken back) stay under it.
struct EmailPreviewCard: View {
    let email: EmailPreviewLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row { Text("To") } value: {
                Text(email.to).font(.body.weight(.semibold))
            }
            Divider()
            row { Text("Subject") } value: {
                Text(email.subject).font(.body.weight(.semibold))
            }
            Divider()
            Text(email.body)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .textSelection(.enabled)
        }
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
        ForEach(Array(email.notes.enumerated()), id: \.offset) { _, note in
            Text(note)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func row<Name: View, Value: View>(@ViewBuilder _ label: () -> Name, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            label()
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 56, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
