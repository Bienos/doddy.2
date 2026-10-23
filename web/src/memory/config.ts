/**
 * Whether the Memory and Ask Doddy pages (ADR-603) are in Doddy Web's menu and routes. The server
 * keeps and serves what the iPhone sends, but the iPhone can't send yet (below), so the pages open on
 * "nothing is kept". Set it to false before anyone but the owner gets Doddy Web, unless the iPhone
 * half has shipped.
 */
export const MEMORY_ENABLED = true;

/**
 * Whether the Doddy app on the iPhone can send notes and conversations to Doddy's server and has
 * the switches for it (Settings › Doddy on the web). It cannot yet: that part of the app is not
 * built. While this is false the pages never tell anyone to turn it on in the app, and the menu
 * says Soon. Set it to true in the same change that ships the iPhone half.
 */
export const IPHONE_SYNCS_MEMORY = false;
