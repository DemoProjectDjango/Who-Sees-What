/**
 * Top-level Lightning DTO for one assigned user in License Inspector.
 * Field names intentionally match PEDto.LicenseUserRow so the existing LWC
 * contract does not change.
 */
public class PELicenseUserRow {
    @AuraEnabled public Id userId { get; set; }
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public String username { get; set; }
    @AuraEnabled public String profileName { get; set; }
    @AuraEnabled public Boolean isActive { get; set; }
}
