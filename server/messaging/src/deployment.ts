// Is this server deployed, as opposed to a local run or a test? A deployed server must have MEMORY_ENCRYPTION_KEY:
// without it queued texts would be stored readable and phone numbers and client addresses hashed without a key, so
// loadConfig refuses to start one (config.ts). Local runs and tests keep working without a key.
//
// Deployed means any one of:
//   - NODE_ENV=production (render.yaml sets it for both messaging services);
//   - RENDER is set (Render sets RENDER=true on every service, also one made by hand in the dashboard);
//   - PUBLIC_BASE_URL is an address other people's servers can reach (Twilio and ElevenLabs post to it): any host but
//     localhost, a loopback or unspecified address, or a name reserved for tests (.localhost, .test, .example, .invalid).
// An empty value counts as unset, as everywhere in loadConfig.

type Env = Record<string, string | undefined>;

const RESERVED_SUFFIXES = [".localhost", ".test", ".example", ".invalid"];

/** True for a host no one else can reach: localhost, a loopback or unspecified address, a reserved test name. */
export function isLocalHost(hostname: string): boolean {
  const h = hostname.toLowerCase().replace(/^\[|\]$/g, "").replace(/\.$/, "");
  if (h === "localhost" || h === "::1" || h === "::" || h === "0.0.0.0" || /^127(\.\d{1,3}){3}$/.test(h)) return true;
  return RESERVED_SUFFIXES.some((s) => h.endsWith(s) || h === s.slice(1));
}

/** Which rule marks this environment as deployed, or undefined for a local run or a test. */
export function deployedBecause(env: Env): "NODE_ENV" | "RENDER" | "PUBLIC_BASE_URL" | undefined {
  if (env.NODE_ENV === "production") return "NODE_ENV";
  if (env.RENDER) return "RENDER";
  if (env.PUBLIC_BASE_URL) {
    let host: string | undefined;
    try {
      host = new URL(env.PUBLIC_BASE_URL).hostname;
    } catch {
      host = undefined; // not an address at all (loadConfig refuses it anyway)
    }
    if (host && !isLocalHost(host)) return "PUBLIC_BASE_URL";
  }
  return undefined;
}

/** Read at the time of the call (default: this process's environment), so a test can switch it. */
export const isDeployed = (env: Env = process.env): boolean => deployedBecause(env) !== undefined;
