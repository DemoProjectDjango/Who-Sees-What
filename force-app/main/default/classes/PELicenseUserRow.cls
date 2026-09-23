/**
 * Top-level Lightning DTO for one assigned user in License Inspector.
 * Field names intentionally match PEDto.LicenseUserRow so the existing LWC
 * contract does not change.
 */
public class PELicenseUserRow {
    /** The assigned user's Salesforce Id. */
    @AuraEnabled public Id userId { get; set; }
    /** Display name of the assigned user. */
    @AuraEnabled public String name { get; set; }
    /** Username of the assigned user. */
    @AuraEnabled public String username { get; set; }
    /** Profile name of the assigned user. */
    @AuraEnabled public String profileName { get; set; }
    /** Whether the assigned user is active. */
    // Serialised LWC contract: the Boolean auto-property's setter trips this
    // rule, but the field name and shape are fixed by the wire response.
    @SuppressWarnings('PMD.AvoidBooleanMethodParameters')
    @AuraEnabled public Boolean isActive { get; set; }
}
