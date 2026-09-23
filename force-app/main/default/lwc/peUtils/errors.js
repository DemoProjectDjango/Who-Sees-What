/**
 * The controller serialises a structured ErrorInfo into the exception message,
 * so the client branches on cause instead of matching strings.
 */
export function parseError(error) {
    const fallback = {
        cause: 'UNKNOWN',
        message: 'Something went wrong loading this panel.',
        retryable: true
    };
    const raw = error?.body?.message ?? error?.message;
    if (!raw) {
        return fallback;
    }
    try {
        const parsed = JSON.parse(raw);
        if (parsed && parsed.cause) {
            return parsed;
        }
    } catch {
        // Not our structured payload — surface the real text, not a generic one.
    }
    return { ...fallback, message: raw };
}

/** Copy written for the person reading it, not for the log. */
export function errorHeadline(cause) {
    switch (cause) {
        case 'NOT_AUTHORISED': return 'You do not have access to this tool';
        case 'INACTIVE_USER':  return 'This user is inactive';
        case 'NOT_FOUND':      return 'Not found';
        case 'LIMIT_EXCEEDED': return 'Too much to analyse at once';
        case 'CALLOUT_FAILED': return 'Could not reach Salesforce metadata';
        case 'SETUP_REQUIRED': return 'Setup needed';
        default:               return 'Something went wrong';
    }
}