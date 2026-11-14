import type { SocialProvider } from "../api/schemas.js";

/**
 * Apple or Google in a small window, so the page the person came from stays where it is.
 *
 * The server's sign-in is unchanged: the window goes `/v1/web/oauth/start` → Supabase → Apple or
 * Google → `/v1/web/oauth/callback`, which sets the session cookie. A cookie is shared by every
 * window of this browser, so the page that opened the window learns it is signed in by asking the
 * server (`api.session`), never from anything the window tells it. The window's own messages
 * (BroadcastChannel, same origin only) only make that check happen sooner.
 *
 * It is not used on a phone or a narrow screen, where a window is a tab and leaving the page is
 * worse than the redirect, and a blocked window falls back to the plain redirect.
 */

/** The window's name, so the page it lands on can tell it is the sign-in window. */
export const POPUP_NAME = "doddy-signin";
/** How often the opening page asks the server whether the window finished. */
export const POLL_MS = 1500;
/** How long the opening page waits before it says nothing happened. */
export const WAIT_LIMIT_MS = 5 * 60 * 1000;

export type PopupMessage = { type: "signedIn" } | { type: "result"; result: string; provider: SocialProvider | null };

/** A window only where it stays a window: a mouse and room for it. */
export function popupWanted(): boolean {
  try {
    if (typeof window.matchMedia === "function" && window.matchMedia("(pointer: coarse)").matches) return false;
    return window.innerWidth >= 700;
  } catch {
    return false;
  }
}

/** The window, or null when the browser blocked it (the caller then goes to the address itself). */
export function openSignInPopup(url: string): Window | null {
  const width = 480;
  const height = 720;
  const left = Math.max(0, Math.round(window.screenX + (window.outerWidth - width) / 2));
  const top = Math.max(0, Math.round(window.screenY + (window.outerHeight - height) / 2));
  try {
    // No `noopener`: the page keeps the handle to close the window once it is signed in. Only
    // Doddy's server, Supabase, Apple and Google are ever loaded in it.
    const popup = window.open(url, POPUP_NAME, `popup=yes,width=${width},height=${height},left=${left},top=${top}`);
    if (!popup || popup.closed) return null;
    popup.focus();
    return popup;
  } catch {
    return null;
  }
}

/** True in the window this page opened (its name survives the trip unless a provider cut the link). */
export function insideSignInPopup(): boolean {
  try {
    return window.name === POPUP_NAME;
  } catch {
    return false;
  }
}

export function openChannel(): BroadcastChannel | null {
  try {
    return typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel(POPUP_NAME);
  } catch {
    return null;
  }
}

/** Tells the opening page, which then asks the server; failing to tell it is harmless (it keeps polling). */
export function tellOpener(message: PopupMessage): void {
  const channel = openChannel();
  if (!channel) return;
  try {
    channel.postMessage(message);
  } finally {
    channel.close();
  }
}

/** Closes this window if the browser lets a script do it (it does for a window a script opened). */
export function closeSelf(): void {
  try {
    window.close();
  } catch {
    // The page says it can be closed.
  }
}
