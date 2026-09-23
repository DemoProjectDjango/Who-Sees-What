/**
 * Decides when the absence of field-level security is structural rather than a
 * permission gap. Misreporting these as "no access" is the fastest way to lose
 * an admin's trust in the whole tool, so this is flagged with a reason, never
 * silently rendered as a gap.
 *
 * Pure logic, no queries — cheap to test, and easy to get subtly wrong.
 */
public with sharing class PEFlsClassifier {

    /** Classification returned to the field grid when missing FLS is a structural Salesforce rule. */
    public class Verdict {
        public Boolean notApplicable = false;
        public String reason;
    }

    /**
     * Classifies a field describe so admins do not confuse non-controllable fields
     * with permission gaps in the inspection results.
     *
     * @param d Field describe result for the object detail row being rendered.
     * @return Verdict explaining whether FLS is not applicable and why.
     */
    public static Verdict classify(Schema.DescribeFieldResult d) {
        Verdict v = new Verdict();
        String reason = fieldTypeReason(d);
        if (reason == null) {
            reason = relationshipReason(d);
        }
        if (reason != null) {
            return flag(v, reason);
        }
        return v;
    }

    private static String fieldTypeReason(Schema.DescribeFieldResult d) {
        if (d.isCalculated()) {
            return 'Formula field — read-only by nature.';
        }
        if (d.isAutoNumber()) {
            return 'Auto-number — read-only by nature.';
        }
        if (d.getType() == Schema.DisplayType.ID) {
            return 'Record Id — FLS does not apply.';
        }
        if (d.isNameField()) {
            return 'Name field — always readable.';
        }
        // Audit fields first: CreatedById and OwnerId are non-nillable
        // references, so a master-detail heuristic based on nillability alone
        // mislabels them.
        if (isSystemAudit(d.getName())) {
            return 'System audit field — not FLS-controllable.';
        }
        return null;
    }

    private static String relationshipReason(Schema.DescribeFieldResult d) {
        // getRelationshipOrder() is 0 or 1 for master-detail, null otherwise.
        if (d.getRelationshipOrder() != null) {
            return 'Master-detail relationship — FLS not applicable.';
        }
        if (!d.isNillable() && d.isCreateable() && !d.isDefaultedOnCreate()) {
            return 'Required field — FLS not applicable.';
        }
        if (!d.isPermissionable()) {
            return 'Not FLS-controllable.';
        }
        return null;
    }

    private static Boolean isSystemAudit(String name) {
        return new Set<String>{
            'CreatedById', 'CreatedDate', 'LastModifiedById', 'LastModifiedDate',
            'SystemModstamp', 'IsDeleted', 'LastActivityDate', 'LastViewedDate',
            'LastReferencedDate'
        }.contains(name);
    }

    private static Verdict flag(Verdict v, String reason) {
        v.notApplicable = true;
        v.reason = reason;
        return v;
    }
}
