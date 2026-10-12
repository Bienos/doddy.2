# DODDY Brain 04: Capability and tool registry

## Today: five partial registries
| Registry | Knows | Used for |
|---|---|---|
| `voice-agent/tools.json` (`x_doddy`) | 59 names, schemas, `runs_on`, `confirm_on_screen`, `speak_before`, `timeout_secs` | ElevenLabs/OpenAI config (`scripts/voice_agent_spec.py`) |
| `VoiceToolName` + `VoiceToolRequest.parse` | phone tools, typed validation | voice dispatch |
| `VoiceConnection.serving` | which user switch a tool needs | gating |
| `CloudToolName` (`all`, `writes`) + backend `CLOUD_TOOLS` | online-account tools, read/write, grants, retries | server is authoritative |
| `PlanTool.allowed` | 7 tools a plan may contain | plans |
| `CapabilityCatalog` | 15 product capabilities, `notImplemented / limited / needsSetup / available` | UI claims only |

## Built: `ToolCatalog` (ADR-445)
`DoddyCore/Brain/ToolCatalog.swift` holds effect and approval per tool; `ToolCatalogTests` run every cross-check listed below,
plus the server's `risk` in `backend/src/tools/catalog.ts`. Risk tiers are not stored: lookup ≈ L0/L1, localChange and handoff ≈ L2,
accountWrite ≈ L3. `CapabilityResolver` (availability) is still a proposal.

## Proposal (Phase 3)
A Swift `ToolCatalog` of `ToolDescriptor` values, **derived from the constants above, not a second list**:
`name, runsOn, effect (lookup | localChange | accountWrite | handoff | session), approval (none | card | serverApproval),
connection: VoiceConnection?, planEligible, riskTier (L0–L4, docs/trust/04)`.

- **Cross-check test (the main value):** every `tools.json` name has a descriptor and the reverse. `confirm_on_screen ⇔ approval != none`.
  `accountWrite ⇒ serverApproval`. Plan steps are changes that finish inside Doddy (as built: `add_to_list` has no single card;
  in a plan the plan card approves it). A drift between spec and app then fails CI before it reaches the live agent.
- **`CapabilityResolver.availability(tool, environment)`** → `available | needsSetup(reason) | limited(reason) | disabled(reason) | unsupported | unverified`.
  It is built from `CapabilityCatalog`, the connection switches, `ConnectionPause`, iOS permission and `AlarmScheduler.support()`.
  The existing `CapabilityStatus` cases are reused, plus `disabled` (a switch is off) and `unsupported` (`.unsupported(name:)`).
  "Unverified" maps to `limited`, whose note says why.
- Phrases ("I need permission first", "That connection isn't configured") come from the existing `VoiceToolReply.notConnected`,
  `ConnectionPause.reply` and `PlanBlock.reply`. No new copy.
- TypeScript keeps `CLOUD_TOOLS` as the server authority. The Swift side only mirrors names and read/write, as `CloudToolName` does today.

Not proposed: a shared code-generated registry across Swift and TS, or runtime-loaded tool lists. Both add build steps for little gain at 59 tools.
