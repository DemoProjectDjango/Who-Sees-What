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
public with sharing class AppVisibilityService {

    public static PEDto.AppList getVisibleApps(Id userId, PEPermissionResolver.Resolved r) {
        return fromAppMenuItem(r);
    }

    /**
     * AppMenuItem is filtered by the *running* user's access, not the target
     * user's — safe for org structure, unsafe as the source of truth for the
     * target user's visibility. Every row is therefore marked estimated, and
     * the column shows a persistent notice.
     */
    private static PEDto.AppList fromAppMenuItem(PEPermissionResolver.Resolved r) {
        PEDto.AppList out = new PEDto.AppList();
        out.resolutionMode = 'APP_MENU_ITEM';
        out.setupRequired = true;
        out.setupMessage =
            'App visibility is estimated from the org-level app menu. ' +
            'Per-permission-set app assignments are not analysed.';

        for (AppMenuItem item : [
            SELECT Name, Label, Type, IsAccessible, IsVisible
            FROM AppMenuItem
            WHERE Type IN ('TabSet', 'ConnectedApplication')
            ORDER BY SortOrder
        ]) {
            PEDto.AppRow row = new PEDto.AppRow();
            row.developerName = item.Name;
            row.label = item.Label;
            row.appType = item.Type == 'ConnectedApplication' ? 'Connected' : 'Lightning';
            row.visible = item.IsAccessible && item.IsVisible;
            row.visibilityEstimated = true;
            out.apps.add(row);
        }
        return out;
    }
}