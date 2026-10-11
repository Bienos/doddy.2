/** One JSON line per event. Callers pass ids and counts only, never message text or phone numbers. */
export const log = (msg: string, extra: object = {}) =>
  console.log(JSON.stringify({ time: new Date().toISOString(), msg, ...extra }));
