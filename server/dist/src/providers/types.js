export class ProviderError extends Error {
    code;
    status;
    constructor(code, status) {
        super(`provider error ${code}${status ? ` (HTTP ${status})` : ""}`);
        this.code = code;
        this.status = status;
    }
}
//# sourceMappingURL=types.js.map