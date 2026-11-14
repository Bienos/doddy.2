// A throwaway local redis-server for the tests of the Redis scripts, served over Upstash's /multi-exec shape.
// Shared by the test files; not a test itself (the test runner only takes *.test.js).
import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { connect, createServer } from "node:net";
import { createVoiceAuthStore } from "../src/voice-auth.js";

// The scripts themselves, run on a real Redis when one is installed (CI may not have it).
export const hasRedis = spawnSync("redis-server", ["--version"]).status === 0;

/** Upstash's /multi-exec, served by a local redis-server over its own protocol. */
async function localRedisFetch(port) {
  const socket = connect(port, "127.0.0.1");
  await new Promise((resolve, reject) => { socket.once("connect", resolve); socket.once("error", reject); });
  let buffer = Buffer.alloc(0);
  let waiting = null;
  socket.on("data", (chunk) => { buffer = Buffer.concat([buffer, chunk]); waiting?.(); });
  const parse = (at) => {
    const end = buffer.indexOf("\r\n", at);
    if (end < 0) return null;
    const type = String.fromCharCode(buffer[at]);
    const line = buffer.toString("utf8", at + 1, end);
    if (type === "+" ) return { value: line, next: end + 2 };
    if (type === "-") return { value: new Error(line), next: end + 2 };
    if (type === ":") return { value: Number(line), next: end + 2 };
    if (type === "$") {
      const length = Number(line);
      if (length < 0) return { value: null, next: end + 2 };
      if (buffer.length < end + 2 + length + 2) return null;
      return { value: buffer.toString("utf8", end + 2, end + 2 + length), next: end + 2 + length + 2 };
    }
    if (type === "*") {
      const items = [];
      let next = end + 2;
      for (let i = 0; i < Number(line); i += 1) {
        const item = parse(next);
        if (!item) return null;
        items.push(item.value);
        next = item.next;
      }
      return { value: items, next };
    }
    throw new Error(`unexpected reply ${type}`);
  };
  const sendNow = async (command) => {
    socket.write(`*${command.length}\r\n${command.map((part) => `$${Buffer.byteLength(part)}\r\n${part}\r\n`).join("")}`);
    for (;;) {
      const reply = parse(0);
      if (reply) { buffer = buffer.subarray(reply.next); return reply.value; }
      await new Promise((resolve) => { waiting = resolve; });
    }
  };
  // One command at a time on the one connection, so two requests running at once can't read each other's replies.
  let queue = Promise.resolve();
  const send = (command) => {
    const turn = queue.then(() => sendNow(command));
    queue = turn.catch(() => {});
    return turn;
  };
  const fetch = async (_url, init) => {
    const results = [];
    for (const command of JSON.parse(init.body)) {
      const value = await send(command);
      results.push(value instanceof Error ? { error: value.message } : { result: value });
    }
    return Response.json(results);
  };
  return { fetch, send, close: () => socket.destroy() };
}

/** A free port from the operating system (a random guess can collide with something already listening). */
function freePort() {
  return new Promise((resolve, reject) => {
    const probe = createServer();
    probe.once("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });
}

/**
 * Starts a throwaway local redis-server and waits for it to answer: up to 3 tries, each on its own free port,
 * each given 5 seconds, and a server that has already exited ends its try at once. A slow or busy runner then
 * no longer fails the test with "local redis-server started".
 */
export async function startLocalRedis() {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const port = await freePort();
    const server = spawn("redis-server", ["--port", String(port), "--save", "", "--appendonly", "no"], { stdio: "ignore" });
    let client;
    for (let i = 0; i < 100 && !client && server.exitCode === null; i += 1) {
      try { client = await localRedisFetch(port); } catch { await new Promise((resolve) => setTimeout(resolve, 50)); }
    }
    if (client) return { server, client };
    server.kill();
  }
  return { server: null, client: null };
}

/** A throwaway local redis-server and a store on it; `command` runs one raw Redis command. */
export async function withLocalRedis(body) {
  const { server, client } = await startLocalRedis();
  try {
    assert.ok(client, "local redis-server started");
    const store = createVoiceAuthStore({ url: "https://redis.example.test", token: "t", fetch: client.fetch });
    await body({ store, command: (...parts) => client.send(parts.map(String)) });
  } finally {
    client?.close();
    server?.kill();
  }
}
