/**
 * Records who inspected whom. Async so it never slows a column load, and
 * not suppressible from the client — the controller never chooses whether
 * to log, only AccessGate does.
 */
public with sharing class InspectionAuditLogger {

    private static List<Inspection_Log__c> buffer = new List<Inspection_Log__c>();

    public static void log(String action, Id subjectUserId, String detail) {
        Inspection_Log__c row = new Inspection_Log__c(
            Action__c          = action,
            Inspector_User__c  = UserInfo.getUserId(),
            Subject_User__c    = subjectUserId,
            Detail__c          = detail == null ? null : detail.abbreviate(255),
            Inspected_At__c    = System.now()
        );
        buffer.add(row);
        flush();
    }

    /**
     * Single-row insert today. If volume becomes a problem, swap the body for
     * a Platform Event or Big Object write — the call sites do not change.
     */
    private static void flush() {
        if (buffer.isEmpty()) return;
        List<Inspection_Log__c> toInsert = buffer;
        buffer = new List<Inspection_Log__c>();
        try {
            insert toInsert;
        } catch (Exception e) {
            // Never let logging break an inspection, but do not swallow silently.
            System.debug(LoggingLevel.ERROR, 'Inspection log failed: ' + e.getMessage());
        }
    }
}