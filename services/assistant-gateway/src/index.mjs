import { createGateway } from "./server.mjs";

// Configuration comes only from the environment. Nothing secret is committed.
//   GATEWAY_TOKEN   required, 32+ chars; clients send it as "Authorization: Bearer <token>"
//   OPENAI_API_KEY  provider key, server-side only; without it /v1/assist answers providerUnavailable
//   OPENAI_MODEL    chat model id; defaults to a low-cost model (verify current pricing before relying on it)
//   PORT            default 8080

const port = Number(process.env.PORT ?? 8080);
const model = process.env.OPENAI_MODEL ?? "gpt-4o-mini";

const server = createGateway({
  token: process.env.GATEWAY_TOKEN ?? "",
  apiKey: process.env.OPENAI_API_KEY ?? "",
  model,
});

server.listen(port, () => {
  console.log(JSON.stringify({ event: "listening", port, model, keyConfigured: Boolean(process.env.OPENAI_API_KEY) }));
});
