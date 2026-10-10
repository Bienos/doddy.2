// Local-time scheduling without a date library: Intl gives the zone's offset at any instant.
export function isValidTimeZone(tz) {
    try {
        new Intl.DateTimeFormat("en-US", { timeZone: tz });
        return true;
    }
    catch {
        return false;
    }
}
function parts(at, tz) {
    const f = new Intl.DateTimeFormat("en-US", {
        timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
    });
    const p = Object.fromEntries(f.formatToParts(at).map((x) => [x.type, x.value]));
    return { y: +p.year, m: +p.month, d: +p.day, h: +p.hour, mi: +p.minute, s: +p.second };
}
/** The local calendar date (YYYY-MM-DD) in `tz` at instant `at`. */
export function localDate(at, tz) {
    const p = parts(at, tz);
    return `${p.y}-${String(p.m).padStart(2, "0")}-${String(p.d).padStart(2, "0")}`;
}
function offsetMs(at, tz) {
    const p = parts(at, tz);
    return Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s) - Math.floor(at.getTime() / 1000) * 1000;
}
/** The instant when the wall clock in `tz` shows y-m-d hh:mm (a skipped DST time moves forward). */
export function zonedToUtc(y, m, d, hh, mm, tz) {
    const guess = Date.UTC(y, m - 1, d, hh, mm);
    let t = guess - offsetMs(new Date(guess), tz);
    t = guess - offsetMs(new Date(t), tz);
    return new Date(t);
}
/** Next instant strictly after `now` when it is `hhmm` ("08:00") in `tz`. */
export function nextRunAt(now, hhmm, tz) {
    const [hh, mm] = hhmm.split(":").map(Number);
    const today = parts(now, tz);
    for (let add = 0; add < 3; add++) {
        const day = new Date(Date.UTC(today.y, today.m - 1, today.d + add));
        const at = zonedToUtc(day.getUTCFullYear(), day.getUTCMonth() + 1, day.getUTCDate(), hh, mm, tz);
        if (at > now)
            return at;
    }
    throw new Error("unreachable");
}
//# sourceMappingURL=schedule.js.map