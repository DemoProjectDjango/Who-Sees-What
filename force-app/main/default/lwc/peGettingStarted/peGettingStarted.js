import { LightningElement } from 'lwc';
import { openInNewTab } from 'c/peUtils';

/**
 * Shown in place of the app column until a user is selected.
 *
 * Mostly static content by design — the limitations here are the product's
 * honest core, not fine print, so they get the empty state rather than a
 * link somewhere else. The two Setup steps are the exception: they're real
 * actions the admin has to go take, so they get real deep links — as buttons,
 * not anchors, so Lightning's own navigation shell has nothing to intercept
 * (see peUtils/accessLabels.js).
 */
export default class PeGettingStarted extends LightningElement {
    permSetsSetupUrl = '/lightning/setup/PermSets/home';
    profilesSetupUrl = '/lightning/setup/EnhancedProfiles/home';

    handleOpenPermSetsSetup() {
        openInNewTab(this.permSetsSetupUrl);
    }

    handleOpenProfilesSetup() {
        openInNewTab(this.profilesSetupUrl);
    }
}