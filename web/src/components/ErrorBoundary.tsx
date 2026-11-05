import { Component, type ErrorInfo, type ReactNode } from "react";
import { MESSAGES } from "../i18n/messages.js";
import { storedLanguage } from "../i18n/i18n.js";

/**
 * Last line of defence: a rendering bug shows a calm page with Reload instead of a blank screen.
 * Nothing about the error (it may hold personal data) is sent anywhere.
 */
export class ErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  override state = { failed: false };

  static getDerivedStateFromError(): { failed: boolean } {
    return { failed: true };
  }

  override componentDidCatch(_error: Error, _info: ErrorInfo): void {
    // Kept in this browser only.
  }

  override render() {
    if (!this.state.failed) return this.props.children;
    const m = MESSAGES[storedLanguage()];
    return (
      <main className="crash" id="main">
        <h1>{m["crash.title"]}</h1>
        <p>{m["crash.body"]}</p>
        <button type="button" className="button" onClick={() => window.location.reload()}>
          {m["crash.reload"]}
        </button>
      </main>
    );
  }
}
