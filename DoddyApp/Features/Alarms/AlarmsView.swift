import DoddyCore
import SwiftUI

/// Settings › Alarms (ADR-255): the alarms Doddy set that are still on, each with Turn off.
struct AlarmsView: View {
    @State private var alarms: [DoddyAlarm] = []
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                if AlarmScheduler.support() == .needsNewerIOS {
                    Text("Alarms need iOS 26 or later. On this iPhone Doddy can set timers and reminders instead.")
                        .foregroundStyle(Theme.secondaryText)
                } else if alarms.isEmpty {
                    Text("No alarms from Doddy. Ask Doddy, for example “Wake me at seven”.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(alarms) { alarm in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alarm.summary).font(.headline)
                                if let label = alarm.label {
                                    Text(label).foregroundStyle(Theme.secondaryText)
                                }
                            }
                            Spacer()
                            Button("Turn off") { turnOff(alarm) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if let problem {
                    Text(problem).foregroundStyle(Theme.accentText)
                }
            } footer: {
                Text("Doddy's alarms ring even in Silent mode or a Focus. Only alarms set by Doddy are shown here; the Clock app's alarms aren't.")
            }
        }
        .navigationTitle("Alarms")
        .onAppear { alarms = AlarmScheduler.current() }
    }

    private func turnOff(_ alarm: DoddyAlarm) {
        if AlarmScheduler.cancel(alarm.id) {
            problem = nil
        } else {
            problem = NSLocalizedString("That alarm couldn't be turned off. Try again.", comment: "")
        }
        alarms = AlarmScheduler.current()
    }
}
