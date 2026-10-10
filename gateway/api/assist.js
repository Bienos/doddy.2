import { handleAssist } from '../src/assist.js';
import { defaultDeps } from '../src/runtime.js';

export default { fetch: (/** @type {Request} */ request) => handleAssist(request, defaultDeps()) };
