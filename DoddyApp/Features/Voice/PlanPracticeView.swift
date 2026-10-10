import DoddyCore
import SwiftUI

/// Settings → Connections → Try a plan card (ADR-206). The same card as in a conversation, with
/// sample steps (`PlanPractice`), so it can be checked without talking to Doddy. Tick, untick and
/// Change work as in a real plan; the button only shows what would happen. Nothing is added,
/// saved or started, and nothing is written to "What Doddy did".
struct PlanPracticeView: View {
    @State private var steps = PlanPractice.steps()
    @State private var ticked: Set<Int> = Set(PlanPractice.steps().map(\.number))
    @State private var editing: PlanStep?
    /// Set after the button is tapped: one line per step.
    @State private var results: [Int: String]?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(PlanPractice.banner, systemImage: "graduationcap")
                    .font(.subheadline)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("practice.banner")

                Text("You asked: \u{201C}I'm at Mom's for lunch on Saturday. Remind me to bring the spare key, remember where it is, and start a pasta timer.\u{201D}")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)

                if let results {
                    resultCard(results)
                } else {
                    card
                }
            }
            .padding(24)
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Try a plan card")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { step in
            PlanStepEditor(step: step) { changed in
                guard let index = steps.firstIndex(where: { $0.number == changed.number }) else { return }
                steps[index] = changed
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Here's what I'd do")
                .font(.headline)
            PlanStepList(
                steps: steps, blocked: [:], ticked: ticked, idPrefix: "practice",
                onToggle: { number in
                    if ticked.contains(number) { ticked.remove(number) } else { ticked.insert(number) }
                },
                onChange: { editing = $0 })
            Text("Untick anything you don't want, or tap Change to fix a step. In a conversation, the rest run in this order.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button {
                results = Dictionary(uniqueKeysWithValues: steps.map {
                    ($0.number, PlanPractice.result(for: $0, ticked: ticked.contains($0.number)))
                })
            } label: {
                HStack { Text(PlanProposal.confirmTitle(steps.filter { ticked.contains($0.number) })); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(ticked.isEmpty)
            .accessibilityIdentifier("practice.confirm")
        }
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func resultCard(_ results: [Int: String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What would happen")
                .font(.headline)
            ForEach(steps) { step in
                Text("\(step.number). \(results[step.number] ?? "")")
                    .font(.subheadline)
            }
            Button("Try again") {
                steps = PlanPractice.steps()
                ticked = Set(steps.map(\.number))
                self.results = nil
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("practice.again")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("practice.results")
    }
}
