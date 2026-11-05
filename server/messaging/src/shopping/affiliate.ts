// Affiliate links (ADR-612, docs/implementation/SHOPPING.md "Affiliate links"). The owner said yes on
// 24 Oct 2026. Nothing here exists until the owner has a programme with a shop: the rules come from the
// AFFILIATE_LINKS setting, which is empty by default, so by default no result has a `buyUrl`. A rule says
// which shop's host gets a tracked link and how the shop's own page address is wrapped into it. The link
// is written only into the finished result, after the picks are made: it never reaches the model, the card
// writer or the ordering, so earning a commission can't change what Doddy recommends.
import { LIMITS } from "../errands/schema.js";

export interface AffiliateRule { host: string; template: string }

const HOST = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$/u;
export const MAX_AFFILIATE_RULES = 30;

/**
 * `{"mediaexpert.pl": "https://network.example/click?id=123&to={url}"}`: a shop's host, and an https
 * template with exactly one `{url}` where the shop's page address goes (percent-encoded). Throws a
 * message naming the problem (never the template) so a bad setting stops the server at start.
 */
export function parseAffiliateRules(json: string): AffiliateRule[] {
  if (!json.trim()) return [];
  let raw: unknown;
  try { raw = JSON.parse(json); } catch { throw new Error("AFFILIATE_LINKS must be a JSON object of shop host to https template"); }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("AFFILIATE_LINKS must be a JSON object of shop host to https template");
  const entries = Object.entries(raw as Record<string, unknown>);
  if (entries.length > MAX_AFFILIATE_RULES) throw new Error(`AFFILIATE_LINKS has more than ${MAX_AFFILIATE_RULES} shops`);
  return entries.map(([host, template]) => {
    if (!HOST.test(host)) throw new Error(`AFFILIATE_LINKS: "${host.slice(0, 60)}" is not a shop host like mediaexpert.pl`);
    if (typeof template !== "string" || template.length > 500 || template.split("{url}").length !== 2) {
      throw new Error(`AFFILIATE_LINKS: the template for ${host} needs exactly one {url} and at most 500 characters`);
    }
    let parsed: URL;
    try { parsed = new URL(template.replace("{url}", "x")); } catch { throw new Error(`AFFILIATE_LINKS: the template for ${host} is not an address`); }
    if (parsed.protocol !== "https:") throw new Error(`AFFILIATE_LINKS: the template for ${host} must be https`);
    return { host, template };
  });
}

export class AffiliateLinks {
  constructor(private readonly rules: readonly AffiliateRule[] = []) {}

  get size() { return this.rules.length; }

  /** The tracked link for a shop's page, or undefined when no rule covers its host. */
  link(pageUrl: string): string | undefined {
    let host: string;
    try { host = new URL(pageUrl).hostname.toLowerCase().replace(/^www\./u, ""); } catch { return undefined; }
    const rule = this.rules.find((r) => host === r.host || host.endsWith(`.${r.host}`));
    if (!rule) return undefined;
    const encoded = encodeURIComponent(pageUrl);
    const built = rule.template.replace("{url}", () => encoded);
    return /^https:\/\/\S+$/u.test(built) && built.length <= LIMITS.url ? built : undefined;
  }
}
