import { useCallback, useEffect, useRef, useState } from "react";
import { useSession } from "../auth/session.js";
import { ApiError } from "./client.js";

/**
 * Loads one thing from the server for a page, with honest states: loading, the data, or an error
 * with a retry. An `unauthenticated` answer signs the page out instead of showing an error.
 * `refreshEveryMs` re-asks while it returns a number, for lists whose items the server is still
 * working on (never a simulated progress: each refresh is a real answer from the server).
 */

export type Resource<T> =
  | { status: "loading"; data: undefined; error: undefined }
  | { status: "ready"; data: T; error: undefined }
  | { status: "error"; data: T | undefined; error: ApiError };

export function useResource<T>(load: (signal: AbortSignal) => Promise<T>, options: { refreshEveryMs?: (data: T) => number | null } = {}) {
  const { expired } = useSession();
  const [resource, setResource] = useState<Resource<T>>({ status: "loading", data: undefined, error: undefined });
  const [tick, setTick] = useState(0);
  const loadRef = useRef(load);
  loadRef.current = load;
  const refreshRef = useRef(options.refreshEveryMs);
  refreshRef.current = options.refreshEveryMs;

  useEffect(() => {
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    loadRef
      .current(controller.signal)
      .then((data) => {
        if (controller.signal.aborted) return;
        setResource({ status: "ready", data, error: undefined });
        const every = refreshRef.current?.(data) ?? null;
        if (every !== null) timer = setTimeout(() => setTick((n) => n + 1), every);
      })
      .catch((error: unknown) => {
        if (controller.signal.aborted) return;
        if (error instanceof ApiError && error.code === "unauthenticated") {
          expired();
          return;
        }
        const apiError = error instanceof ApiError ? error : new ApiError("unreadable", String(error), 0);
        setResource((previous) => ({ status: "error", data: previous.data, error: apiError }));
      });
    return () => {
      controller.abort();
      if (timer) clearTimeout(timer);
    };
  }, [tick, expired]);

  const reload = useCallback(() => setTick((n) => n + 1), []);
  return { resource, reload };
}
