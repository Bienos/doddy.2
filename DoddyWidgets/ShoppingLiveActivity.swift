import ActivityKit
import AppIntents
import DoddyCore
import SwiftUI
import WidgetKit

/// Shopping mode on the Lock Screen and in the Dynamic Island (ADR-257). Each item is a button
/// that runs `ToggleListItemIntent` in the Doddy app (after the iPhone is unlocked): the app ticks
/// it through the store, reads it back and redraws this from the list as it now is. A stale or
/// tapped-twice item changes nothing (the intent checks the item still looks as shown).
struct ShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingActivityAttributes.self) { context in
            ShoppingLockScreen(listID: context.attributes.listID, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color("CardBackground"))
                .activitySystemActionForegroundColor(Color("Ink"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "cart").font(.title3).foregroundStyle(.white).padding(.leading, 6)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.listName).font(.headline).foregroundStyle(.white).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LeftCount(state: context.state).foregroundStyle(.white).padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(context.state.items.filter { !$0.isDone }.prefix(4)) { item in
                            ItemButton(listID: context.attributes.listID, item: item, onIsland: true)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "cart").foregroundStyle(.white).accessibilityLabel("Shopping mode")
            } compactTrailing: {
                LeftCount(state: context.state).foregroundStyle(.white)
            } minimal: {
                Text("\(context.state.openCount)").foregroundStyle(.white)
                    .accessibilityLabel("\(context.state.openCount) left")
            }
        }
    }
}

private struct LeftCount: View {
    let state: ShoppingModeState

    var body: some View {
        Group {
            if state.isFinished {
                Image(systemName: "checkmark").accessibilityLabel("All ticked")
            } else {
                Text("\(state.openCount) left").monospacedDigit()
            }
        }
        .font(.subheadline)
    }
}

private struct ShoppingLockScreen: View {
    let listID: UUID
    let state: ShoppingModeState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(state.listName, systemImage: "cart").font(.headline).lineLimit(1)
                Spacer()
                LeftCount(state: state).foregroundStyle(Color("SecondaryText"))
            }
            if state.isFinished {
                Text("All ticked. Shopping mode ends by itself.").font(.subheadline)
            } else if isStale {
                Text("Open Doddy to see the list as it is now.").font(.subheadline)
            } else {
                ForEach(state.items) { item in
                    ItemButton(listID: listID, item: item, onIsland: false)
                }
                if state.moreOpen > 0 {
                    Text("And \(state.moreOpen) more in Doddy").font(.caption).foregroundStyle(Color("SecondaryText"))
                }
            }
        }
        .foregroundStyle(Color("Ink"))
        .padding(14)
    }
}

private struct ItemButton: View {
    let listID: UUID
    let item: ShoppingModeState.Item
    let onIsland: Bool

    var body: some View {
        Button(intent: ToggleListItemIntent(listID: listID, itemID: item.id, shownDone: item.isDone)) {
            HStack(spacing: 8) {
                Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                Text(item.text).strikethrough(item.isDone).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(onIsland ? .subheadline : .body)
            .foregroundStyle(onIsland ? Color.white : (item.isDone ? Color("SecondaryText") : Color("Ink")))
            .frame(minHeight: onIsland ? 30 : 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.text)
        .accessibilityValue(item.isDone ? "Ticked" : "Not ticked")
    }
}
