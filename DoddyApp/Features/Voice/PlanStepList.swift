import DoddyCore
import SwiftUI

/// The steps of a plan card, each with its tick box and Change button (ADR-204, ADR-205). Shared
/// by the voice screen and the practice card (ADR-206) so both look and behave the same.
struct PlanStepList: View {
    let steps: [PlanStep]
    let blocked: [Int: PlanBlock]
    let ticked: Set<Int>
    /// Accessibility identifiers: "<prefix>.step<n>" and "<prefix>.change<n>".
    let idPrefix: String
    /// Gmail and Todoist steps: the preview Doddy's server prepared (ADR-209), shown instead of
    /// the step's name only.
    var cloud: [Int: VoiceSessionController.PlanCloudApproval] = [:]
    let onToggle: (Int) -> Void
    let onChange: (PlanStep) -> Void

    var body: some View {
        ForEach(steps) { step in
            let request = step.activity(calendar: .current)
            let block = blocked[step.number]
            let isTicked = ticked.contains(step.number)
            Button {
                onToggle(step.number)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: block != nil ? "minus.circle" : isTicked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(block != nil ? Theme.secondaryText : Theme.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        if let prepared = cloud[step.number] {
                            if prepared.mode == .mock {
                                Label("Demo — nothing real will be created", systemImage: "theatermasks")
                                    .font(.footnote)
                            }
                            Text("\(prepared.preview.title) · \(request?.app.title ?? "")")
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                            ForEach(Array(prepared.preview.lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        } else {
                            Text("\(request?.title ?? step.toolName) · \(request?.app.title ?? "")")
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                            if let detail = request?.detail {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        if let block {
                            Text(block.screenText)
                                .font(.footnote)
                                .foregroundStyle(Theme.error)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(block != nil)
            .accessibilityValue(block?.screenText ?? (isTicked ? "Ticked" : "Not ticked"))
            .accessibilityIdentifier("\(idPrefix).step\(step.number)")
            if block == nil, step.canChange {
                Button("Change") {
                    onChange(step)
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityLabel("Change step \(step.number)")
                .accessibilityIdentifier("\(idPrefix).change\(step.number)")
            }
        }
    }
}
