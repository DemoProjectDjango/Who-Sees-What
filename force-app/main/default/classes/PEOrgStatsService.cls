/**
 * Org-wide counts for the KPI bar atop Permission Explorer: active users,
 * permission sets, permission set groups, profiles, reachable apps, and
 * objects with at least one grant somewhere in the org.
 *
 * Each count runs in its own try/catch. These are six unrelated queries
 * against objects of varying obscurity — AppDefinition and an aggregate over
 * ObjectPermissions are not as universally well-trodden as the others — and
 * one of them being unavailable in a given org is not a reason to blank the
 * other five. (This is the same lesson License Inspector's launch taught the
 * hard way: an uncaught failure in one card took the whole panel down with
 * it, silently, for every card, not just the one actually at fault.)
 */
public with sharing class PEOrgStatsService {

    public static PEDto.OrgStats getStats() {
        PEDto.OrgStats s = new PEDto.OrgStats();

        try {
            s.activeUsers = [SELECT COUNT() FROM User WHERE IsActive = true WITH USER_MODE];
        } catch (Exception e) { /* card hidden, not the whole bar */ }

        try {
            // IsOwnedByProfile excludes the hidden permission set every
            // profile carries internally — those are not something an admin
            // manages or would recognise as "a permission set".
            s.permissionSets = [
                SELECT COUNT() FROM PermissionSet WHERE IsOwnedByProfile = false WITH USER_MODE
            ];
        } catch (Exception e) { /* card hidden, not the whole bar */ }

        try {
            s.permissionSetGroups = [SELECT COUNT() FROM PermissionSetGroup WITH USER_MODE];
        } catch (Exception e) { /* card hidden, not the whole bar */ }

        try {
            s.profiles = [SELECT COUNT() FROM Profile WITH USER_MODE];
        } catch (Exception e) { /* card hidden, not the whole bar */ }

        try {
            s.reachableApps = [
                SELECT COUNT() FROM AppDefinition WHERE UiType = 'Lightning' WITH USER_MODE
            ];
        } catch (Exception e) { /* card hidden, not the whole bar */ }

        try {
            AggregateResult[] ar = [
                SELECT COUNT_DISTINCT(SobjectType) cnt
                FROM ObjectPermissions
                WHERE PermissionsRead = true
                WITH USER_MODE
            ];
            s.objectsWithAccess = ar.isEmpty() ? null : (Integer) ar[0].get('cnt');
        } catch (Exception e) { /* card hidden, not the whole bar */ }

        return s;
    }
}
