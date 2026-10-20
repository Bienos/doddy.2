#!/usr/bin/env python3
"""Doddy voice agent spec: check it, and render it for ElevenLabs or OpenAI Realtime.

The files in voice-agent/ are the source of truth (OpenAI Realtime shapes). ElevenLabs is the
engine today; this script turns the same spec into what each provider expects, and compares a
copy of the live ElevenLabs agent against the spec so drift made in the dashboard is caught.

  python3 -I scripts/voice_agent_spec.py check
  python3 -I scripts/voice_agent_spec.py openai              # session.update body (template unrendered)
  python3 -I scripts/voice_agent_spec.py elevenlabs          # one ElevenLabs tool_config per tool
  python3 -I scripts/voice_agent_spec.py compare EXPORT.json # EXPORT = {"prompt": str, "tools": [agents_list_tools items]}

Add `--agent phone` to any command for the phone agent (voice-agent/phone/, S2): its tools are
webhooks to the messaging server, written with a `base` env name, a `path_template` and `body`
parameters instead of a fixed https url.

`--agent task-call` checks the agent that places calls for the user (voice-agent/task-call/,
ADR-500): no function tools at all, only the end_call and voicemail_detection system tools, its first
message is the server-built variable, Polish, phone audio, no recording, and the expected values the
server embeds (server/messaging/src/taskCalls/agentSpec.ts, payload.ts) match this folder.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "voice-agent"
AGENTS = {"app": SPEC, "phone": SPEC / "phone", "task-call": SPEC / "task-call"}
PLACEHOLDER = re.compile(r"\{\{\s*([a-z_][a-z0-9_]*)\s*\}\}")
RUNS_ON = {"phone", "web"}
SPEAK_BEFORE = {"auto", "force"}
# ASK-01: a read takes the user's spoken yes or a tap; a change only a tap. ADR-564: a public
# lookup (the web, the weather, Wikipedia, news, places, sums, conversions) runs at once.
ASK = {"yes_or_tap", "tap", "runs_now"}
# Read nothing of the user's and change nothing (AskFirst.publicLookups in DoddyCore must match).
PUBLIC_LOOKUPS = {"calculate", "convert_units", "convert_currency", "web_search", "news_search", "find_places",
                  "geocode_place", "get_weather", "wikipedia_search", "wikipedia_summary"}
APP_INSTRUCTIONS = SPEC / "instructions.md"


def load(spec=SPEC):
    tools = json.loads((spec / "tools.json").read_text(encoding="utf-8"))
    session = json.loads((spec / "session.json").read_text(encoding="utf-8"))
    instructions = (spec / "instructions.md").read_text(encoding="utf-8")
    return tools, session, instructions


def check(tools, session, instructions):
    errors = []
    names = set()
    for i, tool in enumerate(tools.get("tools", [])):
        name = tool.get("name", f"#{i}")
        where = f"tool {name}"
        if tool.get("type") != "function":
            errors.append(f"{where}: type must be 'function'")
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", name):
            errors.append(f"{where}: name must be snake_case, at most 64 characters")
        if name in names:
            errors.append(f"{where}: duplicate name")
        names.add(name)
        if not tool.get("description", "").strip():
            errors.append(f"{where}: missing description")
        params = tool.get("parameters", {})
        props = params.get("properties", {})
        if params.get("type") != "object":
            errors.append(f"{where}: parameters.type must be 'object'")
        for req in params.get("required", []):
            if req not in props:
                errors.append(f"{where}: required '{req}' is not a property")
        for pname, prop in props.items():
            if prop.get("type") == "array":
                # Only lists of strings (list items, ADR-216); each element needs a description.
                items = prop.get("items", {})
                if items.get("type") != "string" or not items.get("description", "").strip():
                    errors.append(f"{where}.{pname}: an array must hold described strings")
            elif prop.get("type") not in {"string", "number", "integer", "boolean"}:
                errors.append(f"{where}.{pname}: unsupported type {prop.get('type')!r}")
            if not prop.get("description", "").strip():
                errors.append(f"{where}.{pname}: missing description")
        x = tool.get("x_doddy", {})
        if x.get("runs_on") not in RUNS_ON:
            errors.append(f"{where}: x_doddy.runs_on must be one of {sorted(RUNS_ON)}")
        if x.get("speak_before") not in SPEAK_BEFORE:
            errors.append(f"{where}: x_doddy.speak_before must be one of {sorted(SPEAK_BEFORE)}")
        if x.get("confirm_on_screen") and x.get("speak_before") != "force":
            errors.append(f"{where}: on-screen confirmation needs speak_before 'force' so the user is told to look")
        if not isinstance(x.get("timeout_secs"), int) or x["timeout_secs"] <= 0:
            errors.append(f"{where}: x_doddy.timeout_secs must be a positive integer")
        if x.get("runs_on") == "web":
            http = x.get("http") or {}
            if "base" in http:
                # Our own server: the origin comes from an env var at setup time.
                if not re.fullmatch(r"[A-Z][A-Z0-9_]*", str(http["base"])) or not str(http.get("path_template", "")).startswith("/"):
                    errors.append(f"{where}: x_doddy.http needs an ENV_NAME base and a path_template starting with '/'")
            elif not str(http.get("url", "")).startswith("https://"):
                errors.append(f"{where}: web tools need an https x_doddy.http.url (or a base + path_template)")
            path = http.get("path", [])
            query = http.get("query", [])
            body = http.get("body", [])
            for p in path:
                if "{" + p + "}" not in http.get("url", http.get("path_template", "")):
                    errors.append(f"{where}: path param '{p}' is not in the url")
            if sorted(path + query + body) != sorted(props):
                errors.append(f"{where}: http path+query+body must list exactly the tool's parameters")
            if body and http.get("method") != "POST":
                errors.append(f"{where}: body parameters need method POST")
            overlap = set(http.get("constants", {})) & set(props)
            if overlap:
                errors.append(f"{where}: constants shadow parameters {sorted(overlap)}")
        elif "http" in x:
            errors.append(f"{where}: phone tools must not have x_doddy.http")

    used = set(PLACEHOLDER.findall(instructions))
    declared = set(session.get("variables", {}))
    for name in sorted(used - declared):
        errors.append(f"instructions: {{{{{name}}}}} is not declared in session.json variables")
    # A variable the first message uses is used; some exist only for the server (never in the prompt).
    first = " ".join(session.get("first_message", {}).values())
    spoken = used | set(PLACEHOLDER.findall(first)) | set(session.get("elevenlabs", {}).get("not_in_prompt", []))
    for name in sorted(declared - spoken):
        errors.append(f"session.json: variable '{name}' is never used in instructions")
    # Builds that don't send a variable fall back to the agent's placeholder; without one the conversation can't start.
    placeholders = session.get("elevenlabs", {}).get("placeholders")
    if placeholders is not None:
        for name in sorted(declared - set(placeholders)):
            errors.append(f"session.json: variable '{name}' has no elevenlabs placeholder")
    # DODDY AI Constitution DOD-03 (ADR-191, ADR-194): asked whether it is human, Doddy says plainly it is an AI.
    if "ai, not a person" not in instructions.lower():
        errors.append("instructions: must tell Doddy to say plainly it is an AI, not a person (DOD-03)")
    if "vague answer" in instructions.lower():
        errors.append("instructions: must not ask for a vague answer about being human or an AI (DOD-03)")
    return errors


TASK_SYSTEM_TOOLS = {"end_call", "voicemail_detection"}
# Never on the task-call agent: they would let it act (transfer, press keys) or switch language.
TASK_FORBIDDEN = {"transfer_to_number", "transfer_to_agent", "play_keypad_touch_tone", "language_detection", "skip_turn"}
SERVER_TASK = ROOT / "server" / "messaging" / "src" / "taskCalls"


def check_task_call(tools, session, instructions, server=SERVER_TASK):
    """The task-call agent can only talk: no tools that act, fixed first message, and the server's
    embedded expectations (agentSpec.ts, payload.ts) must equal this folder."""
    errors = []
    if tools.get("tools"):
        errors.append("tools.json: the task-call agent must have no function tools (it may not act)")
    system = tools.get("system_tools", [])
    names = [t.get("name") for t in system]
    for n in names:
        if n in TASK_FORBIDDEN or n not in TASK_SYSTEM_TOOLS:
            errors.append(f"tools.json: system tool {n!r} is not allowed (only {sorted(TASK_SYSTEM_TOOLS)})")
    if sorted(names) != sorted(TASK_SYSTEM_TOOLS):
        errors.append(f"tools.json: system tools must be exactly {sorted(TASK_SYSTEM_TOOLS)}")
    for t in system:
        if t.get("name") == "voicemail_detection" and t.get("voicemail_message", None) != "":
            errors.append("tools.json: voicemail_detection must leave no message (voicemail_message \"\")")
    el = session.get("elevenlabs", {})
    if session.get("first_message") != {"pl": "{{doddy_opening_line}}"}:
        errors.append("session.json: first_message must be exactly {\"pl\": \"{{doddy_opening_line}}\"} (the server builds the AI disclosure)")
    if session.get("languages") != ["pl"]:
        errors.append("session.json: languages must be [\"pl\"]")
    if el.get("audio_format") != "ulaw_8000":
        errors.append("session.json: audio_format must be ulaw_8000 (register-call)")
    if el.get("privacy", {}).get("record_voice") is not False:
        errors.append("session.json: privacy.record_voice must be false")
    if el.get("overrides", {}).get("enable_conversation_initiation_client_data_from_webhook") is not False:
        errors.append("session.json: the initiation webhook must be off for this agent")
    if el.get("auth", {}).get("enable_auth") is not True:
        errors.append("session.json: auth.enable_auth must be true")
    if el.get("disable_first_message_interruptions") is not True:
        errors.append("session.json: disable_first_message_interruptions must be true (the disclosure is heard in full)")
    if not isinstance(el.get("max_duration_seconds"), int) or el["max_duration_seconds"] < 320:
        errors.append("session.json: max_duration_seconds must be at least 320 (our server decides when the call ends)")
    low = instructions.lower()
    for phrase in ("jestem asystentem ai", "{{doddy_callback_line}}", "never agree to anything", "at most one short clarifying question"):
        if phrase not in low:
            errors.append(f"instructions: must contain {phrase!r}")

    # The server's embedded copy of these expectations.
    spec_ts = (server / "agentSpec.ts").read_text(encoding="utf-8")
    want_hash = hashlib.sha256(instructions.strip().encode("utf-8")).hexdigest()
    m = re.search(r'promptSha256:\s*"([0-9a-f]{64})"', spec_ts)
    if not m or m.group(1) != want_hash:
        errors.append(f"agentSpec.ts: promptSha256 must be {want_hash} (sha256 of instructions.md, trimmed)")
    for key, value in (("firstMessage", "{{doddy_opening_line}}"), ("language", "pl"), ("audioFormat", "ulaw_8000")):
        if f'{key}: "{value}"' not in spec_ts:
            errors.append(f"agentSpec.ts: {key} must be {value!r}")
    tools_ts = re.search(r"systemTools:\s*\[([^\]]*)\]", spec_ts)
    if not tools_ts or sorted(re.findall(r'"([a-z_]+)"', tools_ts.group(1))) != sorted(TASK_SYSTEM_TOOLS):
        errors.append(f"agentSpec.ts: systemTools must be {sorted(TASK_SYSTEM_TOOLS)}")
    payload_ts = (server / "payload.ts").read_text(encoding="utf-8")
    names_ts = re.search(r"AGENT_VARIABLE_NAMES = \[([^\]]*)\]", payload_ts)
    server_vars = set(re.findall(r'"([a-z_]+)"', names_ts.group(1))) if names_ts else set()
    declared = set(session.get("variables", {})) - {"doddy_attempt"}
    if server_vars != declared:
        errors.append(f"payload.ts: AGENT_VARIABLE_NAMES {sorted(server_vars)} must equal session.json variables {sorted(declared)}")
    return errors


# Where the app answers tools that run on the phone: each such tool's name must appear there as a
# Swift string literal, or the app would answer it as unsupported while CI stayed green.
APP_SOURCES = [ROOT / "Packages" / "DoddyCore" / "Sources", ROOT / "DoddyApp"]


def check_app(tools, sources=APP_SOURCES):
    """Checks only the app agent needs: a live ElevenLabs tool id (or "not_synced") on every tool,
    so a tool missing from the live agent is visible, and an app handler for every phone tool."""
    errors = []
    swift = "".join(p.read_text(encoding="utf-8", errors="ignore") for d in sources for p in sorted(d.rglob("*.swift")))
    for tool in tools.get("tools", []):
        name = tool.get("name", "")
        x = tool.get("x_doddy", {})
        tool_id = x.get("elevenlabs_tool_id")
        if tool_id != "not_synced" and not re.fullmatch(r"tool_[a-z0-9]+", str(tool_id)):
            errors.append(f"tool {name}: x_doddy.elevenlabs_tool_id must be the live tool id, or 'not_synced' until it is synced")
        if x.get("runs_on") == "phone" and f'"{name}"' not in swift:
            errors.append(f"tool {name}: runs on the phone but no Swift source names it, so the app would answer it as unsupported")
        # ASK-01 (ADR-483): every tool asks first, except public lookups that run at once (ADR-564).
        # The app can only ask for a tool it runs itself, a change needs a tap on a card, and the
        # agent always says what it is about to do before an ask.
        runs_now = x.get("ask") == "runs_now"
        if x.get("runs_on") != "phone" and not runs_now:
            errors.append(f"tool {name}: ASK-01 needs every tool that asks to run on the phone, where the app asks first; only a runs_now lookup may run on the web")
        if x.get("ask") not in ASK:
            errors.append(f"tool {name}: x_doddy.ask must be one of {sorted(ASK)} (ASK-01)")
        if (x.get("ask") == "tap") != bool(x.get("confirm_on_screen")):
            errors.append(f"tool {name}: x_doddy.ask 'tap' and confirm_on_screen go together (ASK-01)")
        if runs_now and name not in PUBLIC_LOOKUPS:
            errors.append(f"tool {name}: only the public lookups {sorted(PUBLIC_LOOKUPS)} may run without asking (ADR-564)")
        if not runs_now and x.get("speak_before") != "force":
            errors.append(f"tool {name}: ASK-01 needs speak_before 'force', so Doddy says what it will do before the tool runs")
        if not runs_now and x.get("ask") and (not isinstance(x.get("timeout_secs"), int) or x["timeout_secs"] < 60):
            errors.append(f"tool {name}: an ask needs at least 60 s to be answered")
    if "ASK-01" not in APP_INSTRUCTIONS.read_text(encoding="utf-8"):
        errors.append("instructions: ASK-01 (always ask first) must be in voice-agent/instructions.md")
    return errors


def openai_session(tools, session, instructions):
    clean = [{k: v for k, v in t.items() if k != "x_doddy"} for t in tools["tools"]]
    body = json.loads(json.dumps(session["openai_realtime"]["session_update"]))
    body["instructions"] = instructions
    body["tools"] = clean
    return {"type": "session.update", "session": body}


def _el_param(prop, constant=None):
    out = {"type": prop["type"] if prop else type_of(constant), "description": prop.get("description", "") if prop else ""}
    if prop and "enum" in prop:
        out["enum"] = prop["enum"]
    if prop and prop.get("type") == "array":
        out["items"] = {"type": "string", "description": prop["items"]["description"]}
    if constant is not None:
        out["constant_value"] = constant
    return out


def type_of(value):
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    return "string"


def elevenlabs_tool(tool):
    x = tool["x_doddy"]
    props = tool["parameters"]["properties"]
    common = {
        "name": tool["name"],
        "description": tool["description"],
        "response_timeout_secs": x["timeout_secs"],
        "pre_tool_speech": x["speak_before"],
        "force_pre_tool_speech": x["speak_before"] == "force",
    }
    if x["runs_on"] == "phone":
        return {**common, "type": "client", "expects_response": True, "parameters": {
            "type": "object",
            "required": tool["parameters"].get("required", []),
            "properties": {k: _el_param(v) for k, v in props.items()},
        }}
    http = x["http"]
    if "base" in http:
        # Webhook to our own server: JSON body, headers that reference a workspace secret or a
        # secret dynamic variable (setup-phone-agent.mjs resolves the secret id and the origin).
        headers = {}
        for name, ref in http.get("headers", {}).items():
            headers[name] = {"secret_id": "<" + ref["secret"] + ">"} if "secret" in ref else {"variable_name": ref["variable"]}
        return {**common, "type": "webhook", "api_schema": {
            "url": "${" + http["base"] + "}" + http["path_template"],
            "method": http["method"],
            "request_headers": headers,
            "request_body_schema": {
                "type": "object",
                "properties": {k: _el_param(props[k]) for k in http.get("body", [])},
                "required": [k for k in tool["parameters"].get("required", []) if k in http.get("body", [])],
            },
        }}
    query = {k: _el_param(props[k]) for k in http.get("query", [])}
    query.update({k: _el_param(None, v) for k, v in http.get("constants", {}).items()})
    required = tool["parameters"].get("required", [])
    api = {
        "url": http["url"],
        "method": http["method"],
        "request_headers": http.get("headers", {}),
        "path_params_schema": {k: _el_param(props[k]) for k in http.get("path", [])},
        "response_filter": {"mode": "allow", "filters": http.get("response_fields", [])},
    }
    if query:
        api["query_params_schema"] = {"properties": query, "required": [k for k in http.get("query", []) if k in required]}
    out = {**common, "type": "webhook", "api_schema": api}
    if http.get("follow_redirects_domains"):
        out["follow_redirects"] = True
        out["follow_redirects_allowed_domains"] = http["follow_redirects_domains"]
    return out


def _live_params(cfg):
    """Flatten a live ElevenLabs tool into {name: (type, description, enum)} for comparison."""
    out = {}
    if cfg["type"] == "client":
        for k, v in cfg.get("parameters", {}).get("properties", {}).items():
            out[k] = (v.get("type"), v.get("description", ""), v.get("enum"))
    else:
        api = cfg.get("api_schema", {})
        sources = [api.get("path_params_schema", {}), api.get("query_params_schema", {}).get("properties", {}),
                   (api.get("request_body_schema") or {}).get("properties", {})]
        for source in sources:
            for k, v in source.items():
                if v.get("constant_value") in ("", None):
                    out[k] = (v.get("type"), v.get("description", ""), v.get("enum"))
    return out


def compare(tools, instructions, export, where="voice-agent/"):
    diffs = []
    if export.get("prompt") is not None and export["prompt"].strip() != instructions.strip():
        diffs.append(f"prompt: live agent prompt differs from {where}instructions.md")
    live = {t["tool_config"]["name"]: t for t in export.get("tools", [])}
    spec = {t["name"]: t for t in tools["tools"]}
    for name in sorted(set(spec) - set(live)):
        diffs.append(f"tool {name}: in spec, not on the live agent")
    for name in sorted(set(live) - set(spec)):
        diffs.append(f"tool {name}: on the live agent, not in spec")
    for name in sorted(set(spec) & set(live)):
        s, cfg = spec[name], live[name]["tool_config"]
        x = s["x_doddy"]
        want_type = "client" if x["runs_on"] == "phone" else "webhook"
        if cfg["type"] != want_type:
            diffs.append(f"tool {name}: live type {cfg['type']}, spec {want_type}")
        if cfg.get("description", "").strip() != s["description"].strip():
            diffs.append(f"tool {name}: description differs")
        if cfg.get("response_timeout_secs") != x["timeout_secs"]:
            diffs.append(f"tool {name}: timeout {cfg.get('response_timeout_secs')} live vs {x['timeout_secs']} spec")
        if cfg.get("pre_tool_speech") != x["speak_before"]:
            diffs.append(f"tool {name}: pre_tool_speech {cfg.get('pre_tool_speech')} live vs {x['speak_before']} spec")
        if live[name].get("id") and x.get("elevenlabs_tool_id") and live[name]["id"] != x["elevenlabs_tool_id"]:
            diffs.append(f"tool {name}: live id {live[name]['id']} vs spec {x['elevenlabs_tool_id']}")
        want = {k: (v["type"], v.get("description", ""), v.get("enum")) for k, v in s["parameters"]["properties"].items()}
        if _live_params(cfg) != want:
            diffs.append(f"tool {name}: parameters differ")
    return diffs


def main(argv):
    agent = "app"
    if "--agent" in argv:
        i = argv.index("--agent")
        agent = argv[i + 1] if i + 1 < len(argv) else ""
        argv = argv[:i] + argv[i + 2:]
    if agent not in AGENTS or len(argv) < 2 or argv[1] not in {"check", "openai", "elevenlabs", "compare"}:
        print(__doc__.strip())
        return 2
    spec = AGENTS[agent]
    where = spec.relative_to(ROOT).as_posix() + "/"
    tools, session, instructions = load(spec)
    errors = check(tools, session, instructions)
    if agent == "app":
        errors += check_app(tools)
    if agent == "task-call":
        errors += check_task_call(tools, session, instructions)
    if errors:
        print(f"FAIL voice agent spec ({where})")
        for e in errors:
            print(f"  - {e}")
        return 1
    cmd = argv[1]
    if cmd == "check" and agent == "task-call":
        print(f"PASS voice agent spec ({where}): no function tools; system tools {', '.join(t['name'] for t in tools['system_tools'])}; matches the server's agentSpec.ts")
    elif cmd == "check":
        phone = [t["name"] for t in tools["tools"] if t["x_doddy"]["runs_on"] == "phone"]
        web = [t["name"] for t in tools["tools"] if t["x_doddy"]["runs_on"] == "web"]
        groups = "; ".join(f"{label}: {', '.join(names)}" for label, names in (("phone", phone), ("web", web)) if names)
        print(f"PASS voice agent spec ({where}): {len(tools['tools'])} tools ({groups})")
    elif cmd == "openai":
        print(json.dumps(openai_session(tools, session, instructions), ensure_ascii=False, indent=2))
    elif cmd == "elevenlabs":
        print(json.dumps([elevenlabs_tool(t) for t in tools["tools"]], ensure_ascii=False, indent=2))
    else:
        if len(argv) < 3:
            print("compare needs an export file")
            return 2
        export = json.loads(Path(argv[2]).read_text(encoding="utf-8"))
        diffs = compare(tools, instructions, export, where)
        if diffs:
            print(f"DRIFT between live ElevenLabs agent and {where}")
            for d in diffs:
                print(f"  - {d}")
            return 1
        print(f"MATCH live ElevenLabs agent equals {where} spec")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
