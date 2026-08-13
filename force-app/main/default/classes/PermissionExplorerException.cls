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

    public static PermissionExplorerException build(String causeCode, String msg, Boolean retryable) {
        PermissionExplorerException e = new PermissionExplorerException(msg);
        e.causeCode = causeCode;
        e.retryable = retryable;
        return e;
    }

    public PEDto.ErrorInfo toInfo() {
        return new PEDto.ErrorInfo(this.causeCode, this.getMessage(), this.retryable);
    }
}