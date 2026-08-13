/**
 * @description Controller to check for the existence of a Salesforce Site by name.
 */
public with sharing class SiteNameCheckController {

    /**
     * @description Checks if a Salesforce Site exists by name or URL path prefix.
     * @param siteName The Salesforce Site name or URL path prefix to check.
     * @return True if a Site with the given name or prefix exists, false otherwise.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean doesSiteExist(String siteName) {
        if (String.isBlank(siteName)) {
            return false;
        }

        // Object-level read access (kept for clarity; USER_MODE also enforces it)
        if (!Schema.sObjectType.Site.isAccessible()) {
            return false;
        }

        String s = siteName.trim();
        String prefix = s.toLowerCase();

        try {
            // Enforce CRUD/FLS in user context to satisfy PMD ApexCRUDViolation
            List<Site> sites = Database.query(
                'SELECT Id ' +
                'FROM Site ' +
                'WHERE UrlPathPrefix = :prefix ' +
                '   OR Name = :s ' +
                '   OR MasterLabel = :s ' +
                'LIMIT 1',
                AccessLevel.USER_MODE
            );
            return !sites.isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Inner class that encapsulates Site status information including existence, active status, and validation details.
     */
    public class SiteStatus {
        @AuraEnabled public Boolean exists;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isReady;     // exists && isActive
        @AuraEnabled public String reason;

        @AuraEnabled public String matchedName;
        @AuraEnabled public String matchedPrefix;
        @AuraEnabled public String matchedStatus;
    }

    /**
     * @description Checks if a Site exists and is Active (best-effort with permissions).
     * Not cacheable so "Re-check" reflects changes immediately.
     * @param siteName The Salesforce Site name to check.
     * @return SiteStatus object containing existence, active status, and reason.
     */
    @AuraEnabled
    public static SiteStatus getSiteStatus(String siteName) {
        SiteStatus res = initializeSiteStatus();

        if (String.isBlank(siteName)) {
            res.reason = 'Site name is blank.';
            return res;
        }

        if (!Schema.sObjectType.Site.isAccessible()) {
            res.reason = 'Current user cannot access Setup > Sites. Ask an admin to create/activate the site.';
            return res;
        }

        String validationError = validateFieldPermissions();
        if (validationError != null) {
            res.reason = validationError;
            return res;
        }

        return querySiteStatus(siteName, res);
    }

    /**
     * @description Initializes a new SiteStatus object with default values.
     * @return A new SiteStatus instance with false values.
     */
    private static SiteStatus initializeSiteStatus() {
        SiteStatus res = new SiteStatus();
        res.exists = false;
        res.isActive = false;
        res.isReady = false;
        return res;
    }

    /**
     * @description Validates required field permissions for Site object.
     * @return Error message if permissions are missing, null otherwise.
     */
    private static String validateFieldPermissions() {
        Boolean canReadName = Site.Name.getDescribe().isAccessible();
        Boolean canReadPrefix = Site.UrlPathPrefix.getDescribe().isAccessible();

        if (!canReadName || !canReadPrefix) {
            return 'Current user cannot read Site fields required to validate the site.';
        }
        return null;
    }

    /**
     * @description Queries and processes Site records to determine status.
     * @param siteName The site name to query.
     * @param res The SiteStatus object to populate.
     * @return The populated SiteStatus object.
     */
    private static SiteStatus querySiteStatus(String siteName, SiteStatus res) {
        String s = siteName.trim();
        String prefix = s.toLowerCase();
        Boolean canReadStatus = Site.Status.getDescribe().isAccessible();

        try {
            List<Site> sites = querySites(prefix, s, canReadStatus);

            if (sites.isEmpty()) {
                res.reason = 'No Salesforce Site found with name/path prefix "' + s + '".';
                return res;
            }

            res.exists = true;
            Site chosen = findPreferredSite(sites, canReadStatus);
            populateSiteStatusResult(res, chosen, canReadStatus);

            return res;

        } catch (Exception e) {
            res.reason = 'Unable to query Site: ' + e.getMessage();
            return res;
        }
    }

    /**
     * @description Queries Site records with optional Status field based on permissions.
     * @param prefix The URL path prefix to search.
     * @param s The site name to search.
     * @param canReadStatus Whether Status field is readable.
     * @return List of Site records.
     */
    private static List<Site> querySites(String prefix, String s, Boolean canReadStatus) {
        // Note: USER_MODE enforces CRUD/FLS. If Status isn't readable, don't select it.
        if (canReadStatus) {
            return (List<Site>) Database.query(
                'SELECT Id, Name, UrlPathPrefix, Status, MasterLabel ' +
                'FROM Site ' +
                'WHERE UrlPathPrefix = :prefix ' +
                '   OR Name = :s ' +
                '   OR MasterLabel = :s ' +
                'LIMIT 10',
                AccessLevel.USER_MODE
            );
        }

        return (List<Site>) Database.query(
            'SELECT Id, Name, UrlPathPrefix, MasterLabel ' +
            'FROM Site ' +
            'WHERE UrlPathPrefix = :prefix ' +
            '   OR Name = :s ' +
            '   OR MasterLabel = :s ' +
            'LIMIT 10',
            AccessLevel.USER_MODE
        );
    }



    /**
     * @description Finds the preferred Site record, prioritizing Active sites.
     * @param sites The list of Site records to search.
     * @param canReadStatus Whether Status field is readable.
     * @return The preferred Site record (Active if available, otherwise first).
     */
    private static Site findPreferredSite(List<Site> sites, Boolean canReadStatus) {
        Site chosen = sites[0];
        if (canReadStatus) {
            for (Site st : sites) {
                String stStatus = (String)st.get('Status');
                if (stStatus != null && stStatus.equalsIgnoreCase('Active')) {
                    chosen = st;
                    break;
                }
            }
        }
        return chosen;
    }

    /**
     * @description Populates the SiteStatus result with matched Site information.
     * @param res The SiteStatus object to populate.
     * @param chosen The Site record to extract information from.
     * @param canReadStatus Whether Status field is readable.
     */
    private static void populateSiteStatusResult(SiteStatus res, Site chosen, Boolean canReadStatus) {
        res.matchedName = chosen.Name;
        res.matchedPrefix = chosen.UrlPathPrefix;

        if (!canReadStatus) {
            res.reason = 'Site exists but status cannot be verified due to permissions.';
            return;
        }

        res.matchedStatus = (String)chosen.get('Status');
        res.isActive = (res.matchedStatus != null && res.matchedStatus.equalsIgnoreCase('Active'));
        res.isReady = res.exists && res.isActive;

        if (!res.isActive) {
            res.reason = 'Site exists but is not Active.';
        }
    }
}