/**
 * Top-level Lightning DTO for one License Inspector inventory row.
 * Field names intentionally match PEDto.LicenseRow so the existing LWC
 * contract does not change.
 */
public class PELicenseRow {
    /** The license Id in Salesforce. */
    @AuraEnabled public Id licenseId { get; set; }
    /** The category of license, such as user, permission set, package, or usage-based. */
    @AuraEnabled public String licenseType { get; set; }
    /** Display name of the license. */
    @AuraEnabled public String name { get; set; }
    /** Health/status label rendered in the inventory row. */
    @AuraEnabled public String status { get; set; }
    /** Total seat count for the license. */
    @AuraEnabled public Integer total { get; set; }
    /** Seats currently in use for the license. */
    @AuraEnabled public Integer used { get; set; }
    /** Seats still available for the license. */
    @AuraEnabled public Integer free { get; set; }
    /** Whether the license has no seat limit. */
    // Serialised LWC contract: the Boolean auto-property's setter trips this
    // rule, but the field name and shape are fixed by the wire response.
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters')
    @AuraEnabled public Boolean isUnlimited { get; set; }
    /** License expiration date, when one applies. */
    @AuraEnabled public Datetime expirationDate { get; set; }
    /** Billing or reporting frequency label for the license. */
    @AuraEnabled public String frequency { get; set; }
}
