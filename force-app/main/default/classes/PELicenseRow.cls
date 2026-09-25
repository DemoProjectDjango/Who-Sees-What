/**
 * Top-level Lightning DTO for one License Inspector inventory row.
 * Field names intentionally match PEDto.LicenseRow so the existing LWC
 * contract does not change.
 */
public class PELicenseRow {
    /** Identifier of the license record. */
    @AuraEnabled public Id licenseId { get; set; }

    /** License category discriminator used by inspector workflows. */
    @AuraEnabled public String licenseType { get; set; }

    /** Display name for the license. */
    @AuraEnabled public String name { get; set; }

    /** Current license status, when available. */
    @AuraEnabled public String status { get; set; }

    /** Allocated capacity, or the allowed amount for a usage entitlement. */
    @AuraEnabled public Integer total { get; set; }

    /** Consumed capacity, or current usage for an entitlement. */
    @AuraEnabled public Integer used { get; set; }

    /** Remaining capacity, or null when the license is unlimited. */
    @AuraEnabled public Integer free { get; set; }

    /** Whether the license has no finite capacity limit. */
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters')
    @AuraEnabled public Boolean isUnlimited { get; set; }

    /** Expiration timestamp, when available. */
    @AuraEnabled public Datetime expirationDate { get; set; }

    /** Reporting frequency for a usage entitlement. */
    @AuraEnabled public String frequency { get; set; }
}
