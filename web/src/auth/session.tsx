import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { api, ApiError } from "../api/client.js";
import type { WebSessionView } from "../api/schemas.js";

/**
 * Whether this browser is signed in (ADR-585). The page learns it only by asking the server:
 * the session cookie is HttpOnly, so scripts can't read it, and nothing about it is stored here.
 */

export type SessionState =
  | { status: "checking" }
  | { status: "signedOut"; notice: "expired" | null }
  | { status: "signedIn"; session: WebSessionView }
  | { status: "unreachable"; error: ApiError };

interface SessionApi {
  state: SessionState;
  signIn(code: string): Promise<void>;
  signOut(): Promise<void>;
  /** A call answered `unauthenticated`: the session ended (signed out elsewhere, expired). */
  expired(): void;
  recheck(): void;
}

const Context = createContext<SessionApi | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<SessionState>({ status: "checking" });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    api
      .session(controller.signal)
      .then((session) => setState({ status: "signedIn", session }))
      .catch((error: unknown) => {
        if (controller.signal.aborted) return;
        if (error instanceof ApiError && error.code === "unauthenticated") setState({ status: "signedOut", notice: null });
        else setState({ status: "unreachable", error: error instanceof ApiError ? error : new ApiError("network", String(error), 0) });
      });
    return () => controller.abort();
  }, [attempt]);

  const signIn = useCallback(async (code: string) => {
    const session = await api.signIn(code);
    setState({ status: "signedIn", session });
  }, []);

  const signOut = useCallback(async () => {
    try {
      await api.signOut();
    } catch (error) {
      // Already signed out on the server: that's the outcome asked for.
      if (!(error instanceof ApiError && error.code === "unauthenticated")) throw error;
    }
    setState({ status: "signedOut", notice: null });
  }, []);

  const expired = useCallback(() => setState({ status: "signedOut", notice: "expired" }), []);
  const recheck = useCallback(() => {
    setState({ status: "checking" });
    setAttempt((n) => n + 1);
  }, []);

  const value = useMemo(() => ({ state, signIn, signOut, expired, recheck }), [state, signIn, signOut, expired, recheck]);
  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function useSession(): SessionApi {
  const value = useContext(Context);
  if (!value) throw new Error("useSession outside SessionProvider");
  return value;
}
