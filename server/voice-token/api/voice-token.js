// Vercel entry point (POST /api/voice-token). Set the Vercel project's Root Directory to
// server/voice-token and add the three environment variables from README.md.
import { handleTokenRequest } from "../src/handler.js";

export default {
  fetch(request) {
    return handleTokenRequest(request, process.env);
  },
};
