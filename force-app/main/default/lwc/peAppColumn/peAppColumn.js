import { LightningElement, api } from 'lwc';
import { STATE, sourceKindLabel } from 'c/peUtils';

/**
 * Column 2. Not paginated: even a large org has tens of apps, not thousands,
 * and the list is already in memory from resolveUser. A pager here would show
 * one page in every real org while making the show-hidden toggle awkward.
 *
 * "Why can't they see the app?" is asked as often as "what can they see?", so
 * hidden apps are behind a toggle rather than omitted.
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
        if (!total) return '';
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

    get listItems() {
        return this.visibleApps.map((a) => ({
            id: a.developerName,
            label: a.label,
            secondary: a.developerName,
            badge: a.visible ? null : 'Hidden',
            meta: this.metaFor(a),
            sources: a.sources?.length ? a.sources : null
        }));
    }

    metaFor(app) {
        const parts = [app.appType];
        if (app.visibilityEstimated) parts.push('visibility estimated');
        else if (!app.sources?.length && app.visible) parts.push('source unknown');
        return parts.filter(Boolean).join(' · ');
    }

    handleToggle(event) {
        this.showHidden = event.target.checked;
    }

    handleSelect(event) {
        this.dispatchEvent(new CustomEvent('appselect', {
            detail: { appId: event.detail.id }
        }));
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}