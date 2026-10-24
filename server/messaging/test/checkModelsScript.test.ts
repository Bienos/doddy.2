// The model check script (scripts/check-shopping-models.mjs): what its report says for a model that reports
// everything, one with no server tools and one with fields missing, and its rules about the key. The API is a
// fake `fetch`; nothing here reaches Anthropic. The samples are made up in the shape of the models listing, not
// copies of a real answer (nobody had a key when this was written).
import assert from "node:assert/strict";
import { describe, test } from "node:test";

interface RunnerChoice { webTools: { type: string; name: string }[]; serverFallback: boolean }
interface Io {
  env?: Record<string, string | undefined>;
  stdout?: (s: string) => void;
  stderr?: (s: string) => void;
  fetch?: (url: string, init: { headers: Record<string, string> }) => Promise<Response>;
  loadRunnerChoice?: (id: string) => Promise<RunnerChoice | undefined>;
}
interface ModelsScript {
  DEFAULT_MODELS: string[];
  formatModelReport(id: string, model: unknown, runner: RunnerChoice | undefined): string;
  run(argv: string[], io?: Io): Promise<number>;
  loadRunnerChoice(id: string): Promise<RunnerChoice | undefined>;
}
// The script is plain JavaScript next to src/, outside the TypeScript build. The tests run from dist/test, so the
// script is two levels up (the same way the fixtures are reached).
const script = (await import(new URL("../../scripts/check-shopping-models.mjs", import.meta.url).href)) as ModelsScript;

const BASIC: RunnerChoice = {
  webTools: [{ type: "web_search_20250305", name: "web_search" }, { type: "web_fetch_20250910", name: "web_fetch" }],
  serverFallback: false,
};
const DYNAMIC: RunnerChoice = {
  webTools: [{ type: "web_search_20260209", name: "web_search" }, { type: "web_fetch_20260209", name: "web_fetch" }],
  serverFallback: true,
};

const EVERYTHING = {
  id: "claude-haiku-5-5",
  display_name: "Sample",
  max_input_tokens: 1_000_000,
  max_tokens: 64_000,
  capabilities: {
    effort: { supported: true, low: { supported: true }, medium: { supported: true }, high: { supported: true }, max: { supported: false } },
    structured_outputs: { supported: true },
    thinking: { supported: true, types: { adaptive: { supported: true }, enabled: { supported: false } } },
    server_tools: { web_search: { supported: true }, web_fetch: { supported: true }, code_execution: { supported: true } },
    code_execution: { supported: true },
  },
};

describe("the report for a model that reports everything", () => {
  const report = script.formatModelReport("claude-haiku-5-5", EVERYTHING, BASIC);

  test("every field is printed as the listing says it", () => {
    assert.match(report, /^Model: claude-haiku-5-5$/m);
    assert.match(report, /max_input_tokens: 1,000,000/);
    assert.match(report, /max_tokens: 64,000/);
    assert.match(report, /effort levels: low, medium, high \(not available: max\)/);
    assert.match(report, /structured outputs: yes/);
    assert.match(report, /thinking types: adaptive \(not available: enabled\)/);
    assert.match(report, /server tool web_search: yes/);
    assert.match(report, /server tool code_execution: yes/);
    assert.match(report, /code_execution \(programmatic tool calling\): yes/);
    assert.doesNotMatch(report, /not reported/);
  });

  test("dynamic filtering is likely usable, and the runner's basic tools are named as what it uses now", () => {
    assert.match(report, /\(web_search_20260209 \/ web_fetch_20260209\): LIKELY USABLE/);
    assert.match(report, /currently uses: web_search_20250305 \+ web_fetch_20250910 \(the basic tools\)/);
    assert.match(report, /the runner does not send the fallbacks parameter/);
    assert.match(report, /allows more than the runner uses/);
    assert.match(report, /This script changes nothing/);
    assert.match(report, /no call with these tools was made/, "the report doesn't claim a test it did not do");
  });

  test("when the runner already uses the _20260209 tools the report says it is consistent", () => {
    const r = script.formatModelReport("claude-sonnet-5-5", { ...EVERYTHING, id: "claude-sonnet-5-5" }, DYNAMIC);
    assert.match(r, /currently uses: web_search_20260209 \+ web_fetch_20260209 \(the dynamic-filtering tools\)/);
    assert.match(r, /the runner sends the fallbacks parameter/);
    assert.match(r, /Consistent: the runner's choice matches/);
  });
});

describe("a model with no server_tools", () => {
  const { server_tools: _gone, ...capabilities } = EVERYTHING.capabilities;
  const model = { ...EVERYTHING, capabilities };

  test("the three server tool lines say not reported, and the verdict is that nothing can be told", () => {
    const r = script.formatModelReport("claude-haiku-5-5", model, BASIC);
    assert.match(r, /server tool web_search: not reported/);
    assert.match(r, /server tool web_fetch: not reported/);
    assert.match(r, /server tool code_execution: not reported/);
    assert.match(r, /code_execution \(programmatic tool calling\): yes/, "the top-level field is still read");
    assert.match(r, /: CANNOT TELL \(the listing does not report web search and server-side code execution\)/);
    assert.match(r, /Consistent: the basic tools don't depend on code execution/);
  });

  test("sent the _20260209 tools anyway, the report says the listing does not confirm them", () => {
    const r = script.formatModelReport("claude-haiku-5-5", model, DYNAMIC);
    assert.match(r, /CANNOT TELL/);
    assert.match(r, /does not confirm them/);
  });

  test("a listing that says no is a no, and a runner that sends the _20260209 tools anyway is called a mismatch", () => {
    const no = { ...EVERYTHING, capabilities: { ...EVERYTHING.capabilities, server_tools: { web_search: { supported: true }, code_execution: { supported: false } } } };
    const r = script.formatModelReport("claude-haiku-5-5", no, DYNAMIC);
    assert.match(r, /LIKELY NOT USABLE \(the listing says server-side code execution is not supported\)/);
    assert.match(r, /Mismatch: the runner sends the _20260209 tools/);
    assert.match(script.formatModelReport("claude-haiku-5-5", no, BASIC), /Consistent: the basic tools/);
  });
});

describe("a response with fields missing", () => {
  test("nothing is guessed: every field is not reported, and a runner that could not be read is said so", () => {
    const r = script.formatModelReport("claude-x-1", { id: "claude-x-1-20260101" }, undefined);
    for (const field of ["max_input_tokens", "max_tokens", "effort levels", "structured outputs", "thinking types",
      "server tool web_search", "server tool web_fetch", "server tool code_execution", "code_execution (programmatic tool calling)"]) {
      assert.match(r, new RegExp(`${field.replace(/[()]/g, "\\$&")}: not reported`), field);
    }
    assert.match(r, /\(the API calls it claude-x-1-20260101\)/);
    assert.match(r, /CANNOT TELL/);
    assert.match(r, /currently uses: could not read \(run `npm run build`/);
  });

  test("odd shapes don't throw and don't turn into answers", () => {
    for (const odd of [null, "text", 42, [], {}, { capabilities: "none" }, { capabilities: { effort: true, thinking: { supported: "yes" } }, max_tokens: "lots" }]) {
      const r = script.formatModelReport("claude-x-1", odd, undefined);
      assert.match(r, /max_tokens: not reported/);
      assert.match(r, /thinking types: not reported/);
      assert.match(r, /CANNOT TELL/);
    }
  });

  test("a group that is supported but names nothing says the names are not reported", () => {
    const r = script.formatModelReport("claude-x-1", { capabilities: { effort: { supported: true }, thinking: { supported: false } } }, undefined);
    assert.match(r, /effort levels: supported \(which ones: not reported\)/);
    assert.match(r, /thinking types: not supported/);
  });
});

describe("running it", () => {
  const KEY = "sk-ant-test-SECRET-0123456789";
  const capture = () => {
    const io = { out: "", err: "" };
    return { io, sinks: { stdout: (s: string) => { io.out += s; }, stderr: (s: string) => { io.err += s; } } };
  };
  const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

  test("without ANTHROPIC_API_KEY it exits 2 with a clear message and sends nothing", async () => {
    const { io, sinks } = capture();
    let calls = 0;
    const code = await script.run([], { ...sinks, env: {}, fetch: async () => { calls++; return json(200, {}); } });
    assert.equal(code, 2);
    assert.equal(calls, 0);
    assert.match(io.err, /ANTHROPIC_API_KEY is not set/);
    assert.equal(io.out, "");
    assert.equal((await script.run([], { ...sinks, env: { ANTHROPIC_API_KEY: "   " }, fetch: async () => json(200, {}) })), 2, "a blank key is no key");
  });

  test("a key given as an argument is refused and never printed", async () => {
    const { io, sinks } = capture();
    let calls = 0;
    const fetch = async () => { calls++; return json(200, {}); };
    for (const argv of [[KEY], ["--api-key", KEY], [`--api-key=${KEY}`]]) {
      assert.equal(await script.run(argv, { ...sinks, env: { ANTHROPIC_API_KEY: KEY }, fetch }), 2);
    }
    assert.equal(calls, 0);
    assert.doesNotMatch(io.out + io.err, /SECRET|sk-ant/);
  });

  test("each default model is asked for with the key and the API version, and the reports are printed", async () => {
    const { io, sinks } = capture();
    const asked: { url: string; headers: Record<string, string> }[] = [];
    const code = await script.run([], {
      ...sinks, env: { ANTHROPIC_API_KEY: KEY }, loadRunnerChoice: async () => BASIC,
      fetch: async (url, init) => { asked.push({ url, headers: init.headers }); return json(200, { ...EVERYTHING, id: url.split("/").pop() }); },
    });
    assert.equal(code, 0);
    assert.deepEqual(asked.map((a) => a.url), script.DEFAULT_MODELS.map((m) => `https://api.anthropic.com/v1/models/${m}`));
    assert.deepEqual(script.DEFAULT_MODELS, ["claude-haiku-5-5", "claude-sonnet-5-5"]);
    for (const a of asked) assert.deepEqual(a.headers, { "x-api-key": KEY, "anthropic-version": "2023-06-01" });
    assert.match(io.out, /^Model: claude-haiku-5-5$/m);
    assert.match(io.out, /^Model: claude-sonnet-5-5$/m);
    assert.doesNotMatch(io.out + io.err, /SECRET|sk-ant/, "the key is never printed");
  });

  test("model ids on the command line replace the defaults", async () => {
    const { sinks } = capture();
    const asked: string[] = [];
    const code = await script.run(["claude-haiku-5-5", "claude-haiku-5-5", "claude-opus-5-5"], {
      ...sinks, env: { ANTHROPIC_API_KEY: KEY }, loadRunnerChoice: async () => undefined,
      fetch: async (url) => { asked.push(url.split("/").pop()!); return json(200, EVERYTHING); },
    });
    assert.equal(code, 0);
    assert.deepEqual(asked, ["claude-haiku-5-5", "claude-opus-5-5"]);
  });

  test("an HTTP error prints the status and the error type only, goes on to the next model, and exits 1", async () => {
    const { io, sinks } = capture();
    let n = 0;
    const code = await script.run([], {
      ...sinks, env: { ANTHROPIC_API_KEY: KEY }, loadRunnerChoice: async () => undefined,
      fetch: async () => (++n === 1
        ? json(401, { type: "error", error: { type: "authentication_error", message: `invalid x-api-key ${KEY}` } })
        : json(200, EVERYTHING)),
    });
    assert.equal(code, 1);
    assert.match(io.err, /^claude-haiku-5-5: HTTP 401 authentication_error$/m);
    assert.match(io.out, /^Model: claude-sonnet-5-5$/m, "the second model was still checked");
    assert.doesNotMatch(io.out + io.err, /SECRET|sk-ant|invalid x-api-key/, "nothing from the error body but its type");
  });

  test("a network failure, a body that is not JSON and an error without a type each end as exit 1 with a plain line", async () => {
    for (const [fetch, expected] of [
      [async () => { throw new TypeError("fetch failed"); }, /could not be reached/],
      [async () => new Response("<html>", { status: 200 }), /not with JSON/],
      [async () => new Response("oops", { status: 503 }), /HTTP 503 unknown error type/],
    ] as const) {
      const { io, sinks } = capture();
      assert.equal(await script.run(["claude-haiku-5-5"], { ...sinks, env: { ANTHROPIC_API_KEY: KEY }, fetch, loadRunnerChoice: async () => undefined }), 1);
      assert.match(io.err, expected);
    }
  });

  test("the runner's own choice is read from the built code", async () => {
    const haiku = await script.loadRunnerChoice("claude-haiku-5-5");
    assert.ok(haiku, "dist/src/shopping/runner.js is there (the tests run after the build)");
    assert.deepEqual(haiku.webTools.map((t) => t.name), ["web_search", "web_fetch"]);
  });
});
