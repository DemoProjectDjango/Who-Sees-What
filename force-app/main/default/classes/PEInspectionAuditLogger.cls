/**
 * Records who inspected whom. Async so it never slows a column load, and
 * not suppressible from the client — the controller never chooses whether
 * to log, only PEAccessGate does.
 */
public with sharing class PEInspectionAuditLogger {

    private static List<PE_Inspection_Log__c> buffer = new List<PE_Inspection_Log__c>();

    public static void log(String action, Id subjectUserId, String detail) {
        PE_Inspection_Log__c row = new PE_Inspection_Log__c(
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
        List<PE_Inspection_Log__c> toInsert = buffer;
        buffer = new List<PE_Inspection_Log__c>();
        try {
            insert toInsert;
        } catch (Exception e) {
            // Never let logging break an inspection, but do not swallow silently.
            System.debug(LoggingLevel.ERROR, 'Inspection log failed: ' + e.getMessage());
        }
    }
}