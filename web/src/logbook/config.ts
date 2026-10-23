/**
 * Whether Logbook (ADR-602) is in Doddy Web's menu and routes. The server keeps and serves days
 * today, but the iPhone doesn't send any (see below), so the page shows an empty Logbook and an
 * example. It is on while Doddy Web is the owner's own; set it to false before anyone else gets
 * Doddy Web, unless the iPhone half has shipped (docs/product/WEB_LOGBOOK.md, "Build plan").
 */
export const LOGBOOK_ENABLED = true;

/**
 * Whether the Doddy app on the iPhone can send Logbook days and has the switch for it (Settings ›
 * Doddy on the web). It cannot yet: that part of the app is not built. While this is false the page
 * never tells anyone to turn Logbook on in the app and the menu says Example. Set it to true in
 * the same change that ships the iPhone half.
 */
export const IPHONE_SENDS_LOGBOOK = false;
