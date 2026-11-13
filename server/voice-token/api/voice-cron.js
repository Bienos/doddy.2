// Vercel entry point for the daily retry of voice conversation deletions (GET /api/voice-cron, called by the
// cron in vercel.json with the project's CRON_SECRET; it does nothing without one).
import { handleConversationsCron } from "../src/cron.js";

export default {
  fetch(request) {
    return handleConversationsCron(request, process.env);
  },
};
