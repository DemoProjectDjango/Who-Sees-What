/**
 * Column 2's data source.
 *
 * Per-permission-set app visibility lives only in Profile / PermissionSet
 * metadata, which is not queryable from Apex and would require a callout to
 * read. Callout-dependent features are deliberately out of scope for this
 * package, so this column resolves from AppMenuItem and discloses that it is
 * an estimate.
 *
 * Resolution mode: APP_MENU_ITEM (the only mode).
 */
public with sharing class PEAppVisibilityService {

    /**
     * Resolves the app list shown in the permission inspection workflow, using
     * the only Apex-queryable source and preserving the estimated-visibility notice.
     *
     * @param userId User selected for app visibility inspection.
     * @param r Effective permission-set resolution for the inspected user.
     * @return App list rows and setup messaging for the admin-facing app column.
     */
    public static PEDto.AppList getVisibleApps(Id userId, PEPermissionResolver.Resolved r) {
        return fromAppMenuItem(r);
    }

    /**
     * AppMenuItem is filtered by the *running* user's access, not the target
     * user's — safe for org structure, unsafe as the source of truth for the
     * target user's visibility. Every row is therefore marked estimated, and
     * the column shows a persistent notice.
     *
     * @param r Effective permission-set resolution retained for parity with permission-based service calls.
     * @return App list built from AppMenuItem with product warnings that visibility is estimated.
     */
    private static PEDto.AppList fromAppMenuItem(PEPermissionResolver.Resolved r) {
        PEDto.AppList out = new PEDto.AppList();
        out.resolutionMode = 'APP_MENU_ITEM';
        out.setupRequired = true;
        out.setupMessage =
            'App visibility is estimated from the org-level app menu. ' +
            'Per-permission-set app assignments are not analysed.';

        // Materialised into a List deliberately, NOT iterated as an inline SOQL
        // for-loop. The loop form opens a query cursor and pages via queryMore(),
        // which several app/tab setup objects reject outright — TabDefinition in
        // PEMetadataCatalog failed exactly that way in a subscriber org. AppMenuItem
        // returns a few dozen rows at most, so fetching in one batch costs nothing
        // and removes the paging question entirely.
        List<AppMenuItem> items = [
            SELECT Name, Label, Type, IsAccessible, IsVisible
            FROM AppMenuItem
            WHERE Type IN ('TabSet', 'ConnectedApplication')
            WITH USER_MODE
            ORDER BY SortOrder
            LIMIT 2000
        ];

        for (AppMenuItem item : items) {
            PEDto.AppRow row = new PEDto.AppRow();
            row.developerName = item.Name;
            row.label = item.Label;
            row.appType = item.Type == 'ConnectedApplication' ? 'Connected' : 'Lightning';
            // Null-safe: IsAccessible and IsVisible are Boolean fields and a null
            // on either would throw on unboxing during the && evaluation.
            row.visible = item.IsAccessible == true && item.IsVisible == true;
            row.visibilityEstimated = true;
            out.apps.add(row);
        }
        return out;
    }
}