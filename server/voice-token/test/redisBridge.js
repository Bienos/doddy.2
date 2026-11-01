// A real Redis for the store's Lua scripts, reached the way Upstash's REST API is: the store's
// `fetch` gets the /multi-exec body, and the commands run on a local redis-server. Tests that use
// it are SKIPPED (not passed) where there is no `redis-server` on the PATH and no TEST_REDIS_URL.
import { spawn, spawnSync } from "node:child_process";
import net from "node:net";

class RedisError extends Error {}

function encode(args) {
  const parts = [`*${args.length}\r\n`];
  for (const arg of args) {
    const text = String(arg);
    parts.push(`$${Buffer.byteLength(text, "utf8")}\r\n${text}\r\n`);
  }
  return parts.join("");
}

/** One RESP reply from `buf` at `at`: [value, next] or null while it is incomplete. */
function parse(buf, at = 0) {
  const end = buf.indexOf("\r\n", at);
  if (end < 0) return null;
  const type = String.fromCharCode(buf[at]);
  const line = buf.toString("utf8", at + 1, end);
  const next = end + 2;
  if (type === "+") return [line, next];
  if (type === "-") return [new RedisError(line), next];
  if (type === ":") return [Number(line), next];
  if (type === "$") {
    const length = Number(line);
    if (length < 0) return [null, next];
    if (buf.length < next + length + 2) return null;
    return [buf.toString("utf8", next, next + length), next + length + 2];
  }
  if (type === "*") {
    const count = Number(line);
    if (count < 0) return [null, next];
    const items = [];
    let cursor = next;
    for (let i = 0; i < count; i += 1) {
      const item = parse(buf, cursor);
      if (!item) return null;
      items.push(item[0]);
      cursor = item[1];
    }
    return [items, cursor];
  }
  throw new Error(`unexpected RESP type ${type}`);
}

function connect(port) {
  return new Promise((resolve, reject) => {
    const socket = net.connect({ host: "127.0.0.1", port });
    socket.once("connect", () => resolve(socket));
    socket.once("error", reject);
  });
}

class RedisClient {
  constructor(socket) {
    this.socket = socket;
    this.buffer = Buffer.alloc(0);
    this.waiting = [];
    socket.on("data", (data) => {
      this.buffer = Buffer.concat([this.buffer, data]);
      while (this.waiting.length > 0) {
        const reply = parse(this.buffer);
        if (!reply) return;
        this.buffer = this.buffer.subarray(reply[1]);
        this.waiting.shift()(reply[0]);
      }
    });
  }

  command(args) {
    return new Promise((resolve) => {
      this.waiting.push(resolve);
      this.socket.write(encode(args));
    });
  }
}

/** A local Redis, or null when there is none to use. */
export async function startRedis() {
  let port;
  let child = null;
  if (process.env.TEST_REDIS_URL) {
    port = Number(new URL(process.env.TEST_REDIS_URL).port || 6379);
  } else {
    const found = spawnSync("redis-server", ["--version"], { stdio: "ignore" });
    if (found.error || found.status !== 0) return null;
    port = await new Promise((resolve) => {
      const probe = net.createServer().listen(0, "127.0.0.1", () => {
        const { port: free } = probe.address();
        probe.close(() => resolve(free));
      });
    });
    child = spawn("redis-server", ["--port", String(port), "--bind", "127.0.0.1", "--save", "", "--appendonly", "no"], { stdio: "ignore" });
  }
  let socket;
  for (let i = 0; i < 100 && !socket; i += 1) {
    socket = await connect(port).catch(() => new Promise((resolve) => setTimeout(() => resolve(undefined), 50)));
  }
  if (!socket) {
    child?.kill();
    return null;
  }
  const client = new RedisClient(socket);
  return {
    command: (args) => client.command(args),
    /** What the store's `fetch` is given: Upstash's /multi-exec, answered by this Redis. */
    fetch: async (_url, init) => {
      const results = [];
      for (const command of JSON.parse(init.body)) {
        const reply = await client.command(command);
        results.push(reply instanceof RedisError ? { error: reply.message } : { result: reply });
      }
      return Response.json(results);
    },
    async stop() {
      socket.destroy();
      child?.kill();
    },
  };
}
