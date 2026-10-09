// Request contract from docs/architecture/AI_RUNTIME.md (client request contract).
// Validation is strict on purpose: anything outside the contract is rejected, not coerced.

const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const TASK_TYPES = Object.freeze(["memory_answer", "general"]);

export const LIMITS = Object.freeze({
  promptScalars: 5000,
  turns: 6,
  turnScalars: 2000,
  memories: 20,
  memoryTextScalars: 5000,
  memorySourceScalars: 200,
  memoryIdScalars: 64,
  localeScalars: 16,
});

export class ContractError extends Error {
  constructor(field) {
    super(`invalid ${field}`);
    this.name = "ContractError";
    this.field = field;
  }
}

function scalarLength(s) {
  return [...s].length;
}

function text(value, field, max, { allowEmpty = false } = {}) {
  if (typeof value !== "string") throw new ContractError(field);
  if (!allowEmpty && value.trim().length === 0) throw new ContractError(field);
  if (scalarLength(value) > max) throw new ContractError(field);
  return value;
}

function parseTurn(turn, index) {
  const field = `turns[${index}]`;
  if (!turn || typeof turn !== "object") throw new ContractError(field);
  if (turn.role !== "user" && turn.role !== "assistant") throw new ContractError(`${field}.role`);
  return { role: turn.role, text: text(turn.text, `${field}.text`, LIMITS.turnScalars) };
}

function parseMemory(memory, index) {
  const field = `memories[${index}]`;
  if (!memory || typeof memory !== "object") throw new ContractError(field);
  return {
    id: text(memory.id, `${field}.id`, LIMITS.memoryIdScalars),
    currentText: text(memory.currentText, `${field}.currentText`, LIMITS.memoryTextScalars),
    source: text(memory.source, `${field}.source`, LIMITS.memorySourceScalars, { allowEmpty: true }),
  };
}

/** Validates a request body and returns a normalised copy. Throws ContractError on any violation. */
export function parseAssistRequest(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new ContractError("body");

  if (typeof body.sessionId !== "string" || !UUID_V4.test(body.sessionId)) throw new ContractError("sessionId");
  if (typeof body.requestId !== "string" || !UUID_V4.test(body.requestId)) throw new ContractError("requestId");
  if (!TASK_TYPES.includes(body.taskType)) throw new ContractError("taskType");

  const locale = text(body.locale, "locale", LIMITS.localeScalars);
  const prompt = text(body.prompt, "prompt", LIMITS.promptScalars);

  const turns = body.turns ?? [];
  if (!Array.isArray(turns) || turns.length > LIMITS.turns) throw new ContractError("turns");

  const memories = body.memories ?? [];
  if (!Array.isArray(memories) || memories.length > LIMITS.memories) throw new ContractError("memories");

  const seen = new Set();
  const parsedMemories = memories.map((m, i) => parseMemory(m, i));
  for (const m of parsedMemories) {
    if (seen.has(m.id)) throw new ContractError("memories.id");
    seen.add(m.id);
  }

  return {
    sessionId: body.sessionId,
    requestId: body.requestId,
    taskType: body.taskType,
    locale,
    prompt,
    turns: turns.map((t, i) => parseTurn(t, i)),
    memories: parsedMemories,
  };
}
