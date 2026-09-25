/**
 * Top-level Lightning DTO for one License Inspector inventory row.
 * Field names intentionally match PEDto.LicenseRow so the existing LWC
 * contract does not change.
 */
public class PELicenseRow {
    @AuraEnabled public Id licenseId { get; set; }
    @AuraEnabled public String licenseType { get; set; }
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public String status { get; set; }
    @AuraEnabled public Integer total { get; set; }
    @AuraEnabled public Integer used { get; set; }
    @AuraEnabled public Integer free { get; set; }
    @AuraEnabled public Boolean isUnlimited { get; set; }
    @AuraEnabled public Datetime expirationDate { get; set; }
    @AuraEnabled public String frequency { get; set; }
}
