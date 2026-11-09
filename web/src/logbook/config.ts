/**
 * Whether Logbook (ADR-602) is in Doddy Web's menu and routes. The server keeps and serves days,
 * and the iPhone sends them (see below).
 */
export const LOGBOOK_ENABLED = true;

/**
 * Whether the Doddy app on the iPhone can send Logbook days and has the switch for it (Settings ›
 * Doddy on the web). It can since the iPhone half shipped (DoddyCore `Logbook/`, on by default:
 * decision 2026-11-09-usage-counts-on-by-default), so the page tells people where the switch is and
 * the menu drops its Example marker.
 */
export const IPHONE_SENDS_LOGBOOK = true;
