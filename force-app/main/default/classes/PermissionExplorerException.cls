/**
 * Typed exception so the UI can distinguish causes rather than parse strings.
 * The `cause` values map 1:1 to the error states in the design doc.
 */
public with sharing class PermissionExplorerException extends Exception {

    public static final String NOT_AUTHORISED = 'NOT_AUTHORISED';
    public static final String INACTIVE_USER  = 'INACTIVE_USER';
    public static final String NOT_FOUND      = 'NOT_FOUND';
    public static final String LIMIT_EXCEEDED = 'LIMIT_EXCEEDED';
    public static final String CALLOUT_FAILED = 'CALLOUT_FAILED';
    public static final String SETUP_REQUIRED = 'SETUP_REQUIRED';
    public static final String UNKNOWN        = 'UNKNOWN';

    public String causeCode = UNKNOWN;
    public Boolean retryable = false;

    /**
     * Builds a typed product exception that the controller can serialize for LWC error handling.
     *
     * @param causeCode Stable Permission Explorer error code.
     * @param msg Admin-facing error message.
     * @param retryable True when the failed inspection action can reasonably be retried.
     * @return Exception carrying the structured cause and retry state.
     */
    // retryable is part of the typed-exception contract every caller builds;
    // an enum/wrapper would change those call sites and the serialised payload.
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters')
    public static PermissionExplorerException build(String causeCode, String msg, Boolean retryable) {
        PermissionExplorerException e = new PermissionExplorerException(msg);
        e.causeCode = causeCode;
        e.retryable = retryable;
        return e;
    }

    /**
     * Converts the exception into the DTO shape expected by the client error boundary.
     *
     * @return Structured error payload for Permission Explorer UI handling.
     */
    public PEDto.ErrorInfo toInfo() {
        return new PEDto.ErrorInfo(this.causeCode, this.getMessage(), this.retryable);
    }
}
