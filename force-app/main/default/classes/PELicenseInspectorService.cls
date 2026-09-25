/**
 * Reads license inventory for the License Inspector tab: User Licenses,
 * Permission Set Licenses, Package Licenses, and Usage-Based Entitlements —
 * each with total/used/free (or allowed/consumed) counts, plus the users
 * currently consuming a given seat-based license.
 *
 * Four categories, not two, because "license" means different things in
 * Salesforce and an inventory that only covers half of them isn't honest
 * about what it's missing:
 *   - UserLicense: the base org access every user has one of.
 *   - PermissionSetLicense: add-on features granted independent of profile
 *     (what older Salesforce docs called a "feature license" — the name
 *     was retired, the object wasn't).
 *   - PackageLicense: seats for an installed managed package (an AppExchange
 *     app), tracked completely separately from both of the above.
 *   - TenantUsageEntitlement: an org-wide consumption allowance (API calls,
 *     storage, etc.) rather than a per-user seat — there is no "assigned
 *     users" for these, which getLicenseUsers below refuses rather than
 *     silently returning nothing.
 *
 * Gated the same way as the rest of the product — PEAccessGate at the
 * controller boundary, never here. This class assumes the caller already
 * authorised the request.
 */
public with sharing class PELicenseInspectorService {

    private static final String TYPE_USER_LICENSE     = 'UserLicense';
    private static final String TYPE_PSL               = 'PermissionSetLicense';
    private static final String TYPE_PACKAGE_LICENSE   = 'PackageLicense';
    private static final String TYPE_USAGE_ENTITLEMENT = 'UsageEntitlement';

    /**
     * Lists every user license, permission set license, package license and
     * usage-based entitlement in the org, sorted by name within each
     * category in the order above.
     *
     * @return License rows ready for the License Inspector table.
     */
    @SuppressWarnings('PMD.EmptyCatchBlock,PMD.AvoidNonRestrictiveQueries')
    public static List<PELicenseRow> getLicenses() {
        List<PELicenseRow> rows = new List<PELicenseRow>();

        for (UserLicense ul : [
            SELECT Id, Name, Status, TotalLicenses, UsedLicenses
            FROM UserLicense
            WITH USER_MODE
            ORDER BY Name
        ]) {
            rows.add(toRow(ul.Id, TYPE_USER_LICENSE, ul.Name, ul.Status,
                            ul.TotalLicenses, ul.UsedLicenses, null, null));
        }

        for (PermissionSetLicense psl : [
            SELECT Id, MasterLabel, Status, TotalLicenses, UsedLicenses, ExpirationDate
            FROM PermissionSetLicense
            WITH USER_MODE
            ORDER BY MasterLabel
        ]) {
            rows.add(toRow(psl.Id, TYPE_PSL, psl.MasterLabel, psl.Status,
                            psl.TotalLicenses, psl.UsedLicenses, psl.ExpirationDate, null));
        }

        // Package Licenses and Usage-Based Entitlements are less universal
        // than the two above — some orgs' access to WITH USER_MODE on these
        // specific objects can differ, and a query failure here should cost
        // this one category, not the other three. UserLicense and
        // PermissionSetLicense are not wrapped: those are core to every org
        // and a failure there is a real problem worth surfacing, not hiding.
        try {
            // NamespacePrefix, not a friendly display name — PackageLicense
            // has no label field. It is still the real, stable identifier
            // for the package, so it is shown as-is rather than guessed at.
            for (PackageLicense pl : [
                SELECT Id, NamespacePrefix, Status, AllowedLicenses, UsedLicenses, ExpirationDate
                FROM PackageLicense
                WITH USER_MODE
                ORDER BY NamespacePrefix
            ]) {
                rows.add(toRow(pl.Id, TYPE_PACKAGE_LICENSE, pl.NamespacePrefix, pl.Status,
                                pl.AllowedLicenses, pl.UsedLicenses, pl.ExpirationDate, null));
            }
        } catch (Exception e) {
            // Package licenses simply do not appear in the table for this
            // org/user rather than breaking the other three categories.
        }

        try {
            // Amounts here are Decimal (API calls, storage, etc. can be
            // large or fractional) and rounded to the nearest whole number
            // for display, consistent with the seat-count styling the rest
            // of the table uses.
            for (TenantUsageEntitlement tue : [
                SELECT Id, MasterLabel, CurrentAmountAllowed, AmountUsed, EndDate, Frequency
                FROM TenantUsageEntitlement
                WITH USER_MODE
            ]) {
                rows.add(toRow(tue.Id, TYPE_USAGE_ENTITLEMENT, tue.MasterLabel, null,
                                roundToInt(tue.CurrentAmountAllowed), roundToInt(tue.AmountUsed),
                                tue.EndDate, tue.Frequency));
            }
        } catch (Exception e) {
            // Usage-based entitlements simply do not appear in the table for
            // this org/user rather than breaking the other three categories.
        }

        return rows;
    }

    /**
     * Lists the users currently assigned a given seat-based license, for the
     * "view users" drill-down on the License Inspector table.
     *
     * Usage-based entitlements have no per-user assignment — they are an
     * org-wide allowance, not a seat — so this refuses rather than silently
     * returning an empty (and misleading) list for that category.
     *
     * @param licenseId Id of the license row selected in the table.
     * @param licenseType Discriminator returned alongside licenseId by getLicenses.
     * @return Users holding that license, in name order, capped for readability.
     */
    @SuppressWarnings('PMD.CyclomaticComplexity')
    public static List<PELicenseUserRow> getLicenseUsers(Id licenseId, String licenseType) {
        if (licenseId == null) {
            throw PermissionExplorerException.build(
                PermissionExplorerException.NOT_FOUND, 'That license no longer exists.', false
            );
        }

        List<PELicenseUserRow> rows = new List<PELicenseUserRow>();

        if (licenseType == TYPE_PSL) {
            // Permission set licenses are assigned directly via a junction
            // object, independent of profile.
            for (PermissionSetLicenseAssign a : [
                SELECT AssigneeId, Assignee.Name, Assignee.Username,
                       Assignee.Profile.Name, Assignee.IsActive
                FROM PermissionSetLicenseAssign
                WHERE PermissionSetLicenseId = :licenseId
                WITH USER_MODE
                ORDER BY Assignee.Name
                LIMIT :PEConstants.MAX_SEARCH_RESULTS
            ]) {
                rows.add(toUserRow(a.AssigneeId, a.Assignee?.Name, a.Assignee?.Username,
                                    a.Assignee?.Profile?.Name, a.Assignee?.IsActive));
            }
        } else if (licenseType == TYPE_PACKAGE_LICENSE) {
            // Package licenses are assigned via their own junction object,
            // independent of both profile and permission set licenses.
            try {
                for (UserPackageLicense upl : [
                    SELECT UserId, User.Name, User.Username, User.Profile.Name, User.IsActive
                    FROM UserPackageLicense
                    WHERE PackageLicenseId = :licenseId
                    WITH USER_MODE
                    ORDER BY User.Name
                    LIMIT :PEConstants.MAX_SEARCH_RESULTS
                ]) {
                    rows.add(toUserRow(upl.UserId, upl.User?.Name, upl.User?.Username,
                                        upl.User?.Profile?.Name, upl.User?.IsActive));
                }
            } catch (Exception e) {
                throw PermissionExplorerException.build(
                    PermissionExplorerException.UNKNOWN,
                    'The assigned-user list for package licenses could not be read in this org.',
                    false
                );
            }
        } else if (licenseType == TYPE_USAGE_ENTITLEMENT) {
            throw PermissionExplorerException.build(
                PermissionExplorerException.NOT_FOUND,
                'This is an org-wide usage allowance, not a per-user seat — there is no list of assigned users to show.',
                false
            );
        } else {
            // A user consumes a UserLicense through their profile — the User
            // object carries no UserLicenseId of its own.
            for (User u : [
                SELECT Id, Name, Username, Profile.Name, IsActive
                FROM User
                WHERE Profile.UserLicenseId = :licenseId
                WITH USER_MODE
                ORDER BY Name
                LIMIT :PEConstants.MAX_SEARCH_RESULTS
            ]) {
                rows.add(toUserRow(u.Id, u.Name, u.Username, u.Profile?.Name, u.IsActive));
            }
        }

        return rows;
    }

    private static Integer roundToInt(Decimal value) {
        return value == null ? null : Integer.valueOf(Math.round(value));
    }

    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static PELicenseRow toRow(
        Id licenseId, String licenseType, String name, String status,
        Integer total, Integer used, Datetime expirationDate, String frequency
    ) {
        PELicenseRow r = new PELicenseRow();
        r.licenseId      = licenseId;
        r.licenseType     = licenseType;
        r.name            = name;
        r.status          = status;
        r.used            = used == null ? 0 : used;
        // A handful of licenses report a total of 0 or a negative sentinel to
        // mean "not capacity-limited" — surfacing that as Unlimited is
        // correct; surfacing it as "0 free" would be alarming and wrong.
        r.isUnlimited     = (total == null || total <= 0);
        r.total           = r.isUnlimited ? null : total;
        r.free            = r.isUnlimited ? null : Math.max(0, total - r.used);
        r.expirationDate  = expirationDate;
        r.frequency       = frequency;
        return r;
    }

    @SuppressWarnings('PMD.ExcessiveParameterList')
    private static PELicenseUserRow toUserRow(
        Id userId, String name, String username, String profileName, Boolean isActive
    ) {
        PELicenseUserRow r = new PELicenseUserRow();
        r.userId      = userId;
        r.name        = name;
        r.username    = username;
        r.profileName = profileName;
        r.isActive    = isActive != false;
        return r;
    }
}
