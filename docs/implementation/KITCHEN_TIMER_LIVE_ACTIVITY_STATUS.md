# Kitchen timer Live Activity

## State map

| State | Source of truth | iPhone UI | Dynamic Island / Lock Screen |
|---|---|---|---|
| Proposed | Existing voice tool call | Existing Start/Cancel proposal card | Nothing yet |
| Starting | Existing `TimerStartAction` schedules through `UNUserNotificationCenter` | Existing confirmation flow | Nothing until iOS reads the request back |
| Running | Confirmed pending notification identifier and `firesAt` metadata | Existing timer receipt | Countdown from the real end date; generic timer label only |
| Cancel requested | Existing Live Activity Cancel intent removes that exact local request | Activity remains until removal is verified | If removal cannot be confirmed, countdown remains and says cancellation could not be confirmed |
| Finished | End date passed, delivered notification, or ActivityKit stale date | In-app “Time’s up” alert when Doddy is open | “Time’s up” state with dismiss action; stale state is not presented as running |
| Alert permission unavailable | iOS notification authorization status | Timer can still be scheduled after Timers is explicitly enabled; voice copy says iOS may not alert | Countdown may appear only if Live Activities are enabled |
| Live Activities unavailable | `ActivityAuthorizationInfo` | Timer and notification behavior remain independent | No island or Lock Screen countdown is claimed |

## Existing components extended

- `DeviceConnections` remains the only notification API boundary. Timer requests use a generic alert body and store only the timer identifier, end date, start date, and duration in request metadata.
- `TimerStartAction` remains the trusted writer and still confirms a timer only by reading its identifier back from iOS. Duplicate timers remain intentional.
- `DoddyToolAttributes`, `ToolActivityIntents`, `ToolLiveActivity`, `IslandScene`, and `DoddyToolLiveActivity` extend the existing shared tool Live Activity rather than introducing a second rendering path.
- `KitchenTimerActivities` manages each timer by its existing notification identifier, restores pending countdowns, and only ends an activity after cancellation is read back.
- Foreground completion uses an accessible in-app alert. When Doddy is foregrounded, its notification delegate requests sound only for a timer; iOS presents the native notification normally when Doddy is not in front.

No timer label, note text, transcript, or conversation text is put in Live Activity attributes, notification content, or notification metadata. Notification authorization does not prove delivery; iOS settings and Focus can change presentation.

## Validation status

Linux core CI can check the shared timer action and voice reply logic, but cannot compile ActivityKit/WidgetKit targets or prove island behavior. A Mac owner should run the iPhone Xcode build and simulator checks from `docs/platforms/iphone.md`, including multiple timers, cancel success/failure, app foreground completion, notification denial, and Dynamic Island/Lock Screen layouts. Device delivery, sound, Focus, and Silent behavior remain unverified until checked on iPhone.
