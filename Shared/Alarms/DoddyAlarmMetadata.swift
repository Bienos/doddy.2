#if canImport(AlarmKit)
import AlarmKit

/// What Doddy's alarms carry for their system screens (ADR-260, ADR-267): nothing personal. It is
/// shared by the app, which sets the alarms, and the widget extension, which draws the snooze
/// countdown. AlarmKit is allowed only here, in `DoddyApp/Features/Alarms` and in the widget's
/// `AlarmLiveActivity.swift` (scripts/check_forbidden_capabilities.sh).
@available(iOS 26.0, *)
struct DoddyAlarmMetadata: AlarmMetadata {}
#endif
