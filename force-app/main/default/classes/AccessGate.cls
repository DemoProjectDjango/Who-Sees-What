/**
 * Authorisation gate. Enforced in Apex before any service returns data —
 * never only in the UI.
 *
 * The whole product reads other users' permission metadata, which is exactly
 * the pattern an AppExchange security reviewer scrutinises. The defensible
 * position is: gated by an explicit custom permission, and every inspection
 * logged. Both live here.
 */
public with sharing class AccessGate {

    /** Throws unless the running user holds the packaged custom permission. */
    public static void assertAuthorised() {
        if (!isAuthorised()) {
            throw PermissionExplorerException.build(
                PermissionExplorerException.NOT_AUTHORISED,
                'You need the Permission Explorer permission set to use this tool. ' +
                'Ask an administrator to assign it.',
                false
            );
        }
    }

    /**
     * Deliberately uncached. An authorisation decision held in a mutable
     * static outlives the context it was made in - System.runAs changes the
     * user but not the static - and checkPermission is cheap enough that the
     * guarantee is worth more than the microseconds.
     */
    public static Boolean isAuthorised() {
        return FeatureManagement.checkPermission(PEConstants.CUSTOM_PERMISSION);
    }

    /**
     * Gate plus audit in one call. Every entry point uses this, so an
     * inspection cannot happen without a log row.
     */
    public static void assertAuthorisedAndLog(String action, Id subjectUserId, String detail) {
        assertAuthorised();
        InspectionAuditLogger.log(action, subjectUserId, detail);
    }

    /** Target-user guard. Inactive users are out of scope; frozen users are not. */
    public static User assertInspectable(Id userId) {
        List<User> rows = [
            SELECT Id, Name, Username, Email, IsActive, UserType, ProfileId,
                   Profile.Name, UserRole.Name, Profile.UserLicense.Name, LastLoginDate
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw PermissionExplorerException.build(
                PermissionExplorerException.NOT_FOUND,
                'That user no longer exists.', false
            );
        }
        if (!rows[0].IsActive) {
            throw PermissionExplorerException.build(
                PermissionExplorerException.INACTIVE_USER,
                'This user is inactive and cannot be inspected. Search for an active user.',
                false
            );
        }
        return rows[0];
    }
}