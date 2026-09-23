import { LightningElement, api } from 'lwc';
import { STATE } from 'c/peUtils';

/**
 * Column 2. A dropdown, not a scrolling list.
 *
 * It used to be a listbox sharing the column with the object list below it
 * (38% / 62%, each with its own scroller) — on a wide-app org, or once
 * content grew past its share, the app list overflowed and painted over the
 * object list instead of scrolling. A dropdown has a fixed, small footprint
 * no matter how many apps exist, so the object list always gets the column's
 * full remaining height once an app is chosen, and there is nothing left to
 * overlap.
 *
 * Not paginated: even a large org has tens of apps, not thousands, and the
 * list is already in memory from resolveUser.
 *
 * "Why can't they see the app?" is asked as often as "what can they see?", so
 * hidden apps are behind a toggle rather than left out of the dropdown.
 */
export default class PeAppColumn extends LightningElement {
    @api selectedAppId;
    @api staleSince;

    _appList = { apps: [] };
    showHidden = false;

    @api
    get appList() { return this._appList; }
    set appList(value) {
        this._appList = value ?? { apps: [] };
    }

    @api state = STATE.EMPTY;
    @api error;

    get apps() { return this._appList.apps ?? []; }

    get visibleApps() {
        return this.showHidden ? this.apps : this.apps.filter((a) => a.visible);
    }

    get tally() {
        const total = this.apps.length;
        const visible = this.apps.filter((a) => a.visible).length;
        if (!total) {
            return '';
        }
        return `${visible} of ${total} visible to this user`;
    }

    get showDegradedNotice() {
        return this.state === STATE.LOADED && this._appList.setupRequired;
    }

    get emptyHeadline() {
        if (this.state === STATE.EMPTY) return 'Select a user to begin';
        return 'This user can see no apps';
    }

    get emptyDetail() {
        if (this.state === STATE.EMPTY) return 'Apps appear here once a user is selected.';
        return 'That is a valid outcome, not an error. Turn on "Show all apps" to see what is hidden and why.';
    }

    /**
     * One option per app. A dropdown option can't carry the badge and
     * secondary line a list row could, so a hidden app says so inline
     * instead of via a separate badge.
     */
    get dropdownItems() {
        return this.visibleApps.map((a) => ({
            id: a.developerName,
            label: a.visible ? a.label : `${a.label} — hidden`,
            isSelected: a.developerName === this.selectedAppId
        }));
    }

    handleToggle(event) {
        this.showHidden = event.target.checked;
    }

    handleSelect(event) {
        const appId = event.target.value;
        if (!appId) {
            return;
        }
        this.dispatchEvent(new CustomEvent('appselect', {
            detail: { appId }
        }));
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}
