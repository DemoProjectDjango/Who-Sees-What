/**
 * Top-level Lightning DTO for one assigned user in License Inspector.
 * Field names intentionally match PEDto.LicenseUserRow so the existing LWC
 * contract does not change.
 */
public class PELicenseUserRow {
    /** Identifier of the assigned user. */
    @AuraEnabled public Id userId { get; set; }

    /** Display name of the assigned user. */
    @AuraEnabled public String name { get; set; }

    /** Login username of the assigned user. */
    @AuraEnabled public String username { get; set; }

    /** Profile name of the assigned user, when available. */
    @AuraEnabled public String profileName { get; set; }

    /** Whether the assigned user is active. */
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters')
    @AuraEnabled public Boolean isActive { get; set; }
}
