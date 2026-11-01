// A throwaway Redis for tests that need the store's Lua scripts to really run. It listens only on a
// Unix socket in a temp folder, keeps nothing on disk, and is used only when `redis-server` is
// installed; those tests are skipped otherwise. `fetch` answers like the Upstash REST endpoint.
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { createConnection } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const redisAvailable = spawnSync("redis-server", ["--version"]).status === 0;

export async function startLocalRedis() {
  const dir = mkdtempSync(join(tmpdir(), "voice-token-redis-"));
  const path = join(dir, "redis.sock");
  const child = spawn("redis-server", ["--port", "0", "--unixsocket", path, "--save", "", "--appendonly", "no"],
    { stdio: "ignore" });
  let socket;
  for (let attempt = 0; !socket; attempt += 1) {
    socket = await new Promise((resolve) => {
      const candidate = createConnection({ path }, () => resolve(candidate));
      candidate.once("error", () => resolve(undefined));
    });
    if (!socket && attempt > 100) throw new Error("local redis-server did not start");
    if (!socket) await new Promise((resolve) => setTimeout(resolve, 20));
  }

  const waiting = [];
  let buffer = Buffer.alloc(0);
  socket.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    for (let parsed = parse(buffer, 0); parsed; parsed = parse(buffer, 0)) {
      buffer = buffer.subarray(parsed[1]);
      waiting.shift()(parsed[0]);
    }
  });

  function command(...args) {
    const parts = args.map((arg) => Buffer.from(String(arg)));
    socket.write(`*${parts.length}\r\n`);
    for (const part of parts) socket.write(Buffer.concat([Buffer.from(`$${part.length}\r\n`), part, Buffer.from("\r\n")]));
    return new Promise((resolve) => waiting.push(resolve));
  }

  async function fetch(url, init) {
    if (!String(url).endsWith("/multi-exec")) return new Response("not found", { status: 404 });
    const results = [];
    for (const args of JSON.parse(init.body)) {
      const reply = await command(...args);
      results.push(reply instanceof Error ? { error: reply.message } : { result: reply });
    }
    return Response.json(results);
  }

  function stop() {
    socket.destroy();
    child.kill();
    rmSync(dir, { recursive: true, force: true });
  }

  return { command, fetch, stop };
}

/** One RESP reply from `buffer` at `offset`: [value, next offset], or null while incomplete. */
function parse(buffer, offset) {
  const end = buffer.indexOf("\r\n", offset);
  if (end === -1) return null;
  const type = String.fromCharCode(buffer[offset]);
  const line = buffer.toString("utf8", offset + 1, end);
  const next = end + 2;
  if (type === "+") return [line, next];
  if (type === "-") return [new Error(line), next];
  if (type === ":") return [Number(line), next];
  if (type === "$") {
    const length = Number(line);
    if (length === -1) return [null, next];
    if (buffer.length < next + length + 2) return null;
    return [buffer.toString("utf8", next, next + length), next + length + 2];
  }
  if (type === "*") {
    const count = Number(line);
    if (count === -1) return [null, next];
    const items = [];
    let position = next;
    for (let index = 0; index < count; index += 1) {
      const item = parse(buffer, position);
      if (!item) return null;
      items.push(item[0]);
      position = item[1];
    }
    return [items, position];
  }
  throw new Error(`unexpected reply type ${type}`);
}
