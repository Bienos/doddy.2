// Vercel entry point for Apple sign-in exchange and DODDY session lifecycle.
import { handleVoiceAuthRequest } from "../src/voice-auth.js";

export default {
  fetch(request) {
    return handleVoiceAuthRequest(request, process.env);
  },
};
