import { handleRegister } from '../src/register.js';
import { defaultDeps } from '../src/runtime.js';

export default { fetch: (/** @type {Request} */ request) => handleRegister(request, defaultDeps()) };
