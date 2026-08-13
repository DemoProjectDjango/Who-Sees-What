import { LightningElement } from 'lwc';
import resolveUser from '@salesforce/apex/PermissionExplorerController.resolveUser';
import getAppObjects from '@salesforce/apex/PermissionExplorerController.getAppObjects';
import refreshCache from '@salesforce/apex/PermissionExplorerController.refreshCache';
import getObjectDetail from '@salesforce/apex/PermissionExplorerController.getObjectDetail';
import getLoginHistory from '@salesforce/apex/PermissionExplorerController.getLoginHistory';
import getAssignedPermissionSets from '@salesforce/apex/PermissionExplorerController.getAssignedPermissionSets';
import getAssignedPermissionSetGroups from '@salesforce/apex/PermissionExplorerController.getAssignedPermissionSetGroups';
import {
    STATE, parseError, readState, writeState, shareableLink
} from 'c/peUtils';

/** Which modal is open, if any. A single value cannot represent "both". */
const MODAL = {
    NONE: null,
    APP: 'app',
    LOGIN: 'login',
    PERMSETS: 'permsets',
    GROUPS: 'groups'
};

const LOGIN_HISTORY_ROWS = 50;

/**
 * Setup deep links. Plain anchors rather than NavigationMixin, because "open in
 * a new tab" should also mean middle-click and cmd-click — an admin comparing
 * five permission sets opens five tabs, and a programmatic navigate gives them
 * one.
 */
const permSetSetupUrl = (id) => `/lightning/setup/PermSets/page?address=%2F${id}`;
const permSetGroupSetupUrl = (id) => `/lightning/setup/PermSetGroups/page?address=%2F${id}`;

/**
 * Owns every piece of state and pushes it down as props; children are
 * presentational and emit events upward.
 *
 * That single decision is what makes URL state and the modal's prev/next
 * arrows trivial rather than a synchronisation problem — the arrows just
 * increment an index in this component's object list and the modal re-renders
 * from new props.
 */
export default class PermissionExplorer extends LightningElement {

    /* ------------------------------- state ------------------------------- */

    selectedUserId;
    selectedAppId;

    userSummary;
    appList = { apps: [] };
    objectRows = [];

    appState = STATE.EMPTY;
    appError;
    railState = STATE.EMPTY;
    railError;

    activeModal = MODAL.NONE;
    resolvedAt;

    /* Header drill-downs. Fetched on first open, then held for this user. */
    loginHistory = {};
    loginState = STATE.EMPTY;
    loginError;

    permSetList = { directSets: [] };
    permSetState = STATE.EMPTY;
    permSetError;

    groupList = [];
    groupState = STATE.EMPTY;
    groupError;

    _triggerElement;

    /* ------------------------------ lifecycle ------------------------------ */

    connectedCallback() {
        this.restoreFromUrl();
    }

    /** A link pasted into a support ticket should land on the exact panel. */
    async restoreFromUrl() {
        const state = readState();
        if (!state.userId) return;

        await this.loadUser(state.userId);
        if (state.appId && this.appList.apps.some((a) => a.developerName === state.appId)) {
            await this.loadAppObjects(state.appId);
            this.activeModal = MODAL.APP;
        }
    }

    /* ------------------------------- derived ------------------------------- */

    get isAppModal()     { return this.activeModal === MODAL.APP && !!this.userSummary; }
    get isLoginModal()   { return this.activeModal === MODAL.LOGIN && !!this.userSummary; }
    get isPermSetModal() { return this.activeModal === MODAL.PERMSETS && !!this.userSummary; }
    get isGroupModal()   { return this.activeModal === MODAL.GROUPS && !!this.userSummary; }

    get selectedAppLabel() {
        const app = this.appList.apps.find((a) => a.developerName === this.selectedAppId);
        return app?.label ?? this.selectedAppId;
    }

    get crumbs() {
        const out = [];
        if (this.userSummary) {
            out.push({ key: 'u', label: this.userSummary.name, separator: false });
        }
        if (this.selectedAppId) {
            const app = this.appList.apps.find((a) => a.developerName === this.selectedAppId);
            out.push({ key: 'a', label: app?.label ?? this.selectedAppId, separator: true });
        }
        return out;
    }

    /* --------------------- drill-down row shaping --------------------- */

    /**
     * Sorted here rather than in Apex: `List.sort()` on a wrapper needs
     * Comparable, and a locale-aware compare belongs on the client anyway.
     */
    get permSetItems() {
        const rows = [...(this.permSetList?.directSets ?? [])];
        rows.sort((a, b) => (a.label ?? '').localeCompare(b.label ?? ''));

        return rows.map((r, i) => {
            const linkable = r.isReadable !== false && !!r.permSetId;
            return {
                key: r.permSetId ?? `ps-${i}`,
                label: r.label ?? 'Unnamed permission set',
                sublabel: r.apiName ?? null,
                url: linkable ? permSetSetupUrl(r.permSetId) : null,
                linkable,
                badge: this.permSetBadge(r.setType),
                badgeClass: 'badge',
                note: linkable
                    ? null
                    : 'This permission set belongs to a managed package and its definition is not readable, so it cannot be opened in Setup. Its permissions still apply.'
            };
        });
    }

    /** Only the unusual types are worth a badge; "Regular" is the default. */
    permSetBadge(setType) {
        if (!setType || setType === 'Regular') return null;
        return setType;
    }

    get permSetFootnote() {
        const via = this.permSetList?.viaGroupCount ?? 0;
        const unreadable = this.permSetList?.unreadableCount ?? 0;
        const parts = [];

        if (via) {
            parts.push(
                `${via} further permission set${via === 1 ? '' : 's'} appl${via === 1 ? 'ies' : 'y'} ` +
                'through assigned permission set groups and are not listed here.'
            );
        }
        if (unreadable) {
            parts.push(
                `${unreadable} of these could not be read, so ${unreadable === 1 ? 'its label is' : 'their labels are'} unavailable.`
            );
        }
        return parts.length ? parts.join(' ') : null;
    }

    get groupItems() {
        const rows = [...(this.groupList ?? [])];
        rows.sort((a, b) =>
            (a.masterLabel ?? a.developerName ?? '').localeCompare(
                b.masterLabel ?? b.developerName ?? ''
            )
        );

        return rows.map((r, i) => ({
            key: r.groupId ?? `psg-${i}`,
            label: r.masterLabel ?? r.developerName ?? 'Unnamed group',
            sublabel: r.developerName ?? null,
            url: r.groupId ? permSetGroupSetupUrl(r.groupId) : null,
            linkable: !!r.groupId,
            badge: r.isOutdated ? r.status ?? 'Not updated' : null,
            badgeClass: r.isOutdated ? 'badge badge_caution' : 'badge',
            note: r.isOutdated
                ? 'This group is still recalculating, so its effective permissions are not yet settled.'
                : null
        }));
    }

    get groupFootnote() {
        const outdated = (this.groupList ?? []).filter((g) => g.isOutdated).length;
        if (!outdated) return null;
        return `${outdated} group${outdated === 1 ? ' is' : 's are'} still recalculating. ` +
            'Treat any permission traced to them as provisional.';
    }

    /* ------------------------------- loading ------------------------------- */

    async loadUser(userId, forceRefresh = false) {
        this.selectedUserId = userId;
        this.selectedAppId = undefined;
        this.objectRows = [];
        this.appState = STATE.LOADING;
        this.appError = undefined;
        this.resetDrillDowns();

        try {
            const ctx = await resolveUser({ userId, forceRefresh });
            this.userSummary = ctx.summary;
            this.appList = ctx.apps ?? { apps: [] };
            this.resolvedAt = ctx.summary?.resolvedAt;
            this.appState = this.appList.apps.length ? STATE.LOADED : STATE.LOADED_EMPTY;
        } catch (e) {
            this.appError = parseError(e);
            this.appState = STATE.ERROR;
            this.userSummary = undefined;
        }
        this.syncUrl();
    }

    /** A new user invalidates all three panels; stale rows under a new name is
        the worst possible outcome for an audit tool. */
    resetDrillDowns() {
        this.activeModal = MODAL.NONE;
        this.loginHistory = {};
        this.loginState = STATE.EMPTY;
        this.loginError = undefined;
        this.permSetList = { directSets: [] };
        this.permSetState = STATE.EMPTY;
        this.permSetError = undefined;
        this.groupList = [];
        this.groupState = STATE.EMPTY;
        this.groupError = undefined;
    }

    /**
     * Fired on app click, before the modal finishes its open transition — the
     * animation buys 200–300 ms of free loading time, which is frequently the
     * entire request.
     */
    async loadAppObjects(appId) {
        this.selectedAppId = appId;
        this.railState = STATE.LOADING;
        this.railError = undefined;
        this.objectRows = [];

        try {
            const rows = await getAppObjects({
                userId: this.selectedUserId,
                appDeveloperName: appId
            });
            this.objectRows = rows ?? [];
            this.railState = this.objectRows.length ? STATE.LOADED : STATE.LOADED_EMPTY;
        } catch (e) {
            this.railError = parseError(e);
            this.railState = STATE.ERROR;
        }
        this.syncUrl();
    }

    /* --------------------------- drill-down loading --------------------------- */

    /**
     * Login history is a query against an object the running user may not be
     * permitted to read, so it is never fetched on user selection — only when
     * someone actually asks for it.
     */
    async loadLoginHistory() {
        this.loginState = STATE.LOADING;
        this.loginError = undefined;

        try {
            const res = await getLoginHistory({
                userId: this.selectedUserId,
                maxRows: LOGIN_HISTORY_ROWS
            });
            this.loginHistory = res ?? {};
            // An unavailable panel is LOADED, not EMPTY: the component renders
            // its own explanation and must not fall through to "no sign-ins".
            this.loginState = (res?.notAvailableReason || res?.events?.length)
                ? STATE.LOADED
                : STATE.LOADED_EMPTY;
        } catch (e) {
            this.loginError = parseError(e);
            this.loginState = STATE.ERROR;
        }
    }

    async loadPermSets() {
        this.permSetState = STATE.LOADING;
        this.permSetError = undefined;

        try {
            const res = await getAssignedPermissionSets({ userId: this.selectedUserId });
            this.permSetList = res ?? { directSets: [] };
            this.permSetState = this.permSetList.directSets?.length
                ? STATE.LOADED
                : STATE.LOADED_EMPTY;
        } catch (e) {
            this.permSetError = parseError(e);
            this.permSetState = STATE.ERROR;
        }
    }

    async loadGroups() {
        this.groupState = STATE.LOADING;
        this.groupError = undefined;

        try {
            const res = await getAssignedPermissionSetGroups({ userId: this.selectedUserId });
            this.groupList = res ?? [];
            this.groupState = this.groupList.length ? STATE.LOADED : STATE.LOADED_EMPTY;
        } catch (e) {
            this.groupError = parseError(e);
            this.groupState = STATE.ERROR;
        }
    }

    /* ------------------------------- handlers ------------------------------- */

    handleUserSelect(event) {
        this.loadUser(event.detail.userId);
    }

    handleAppSelect(event) {
        this._triggerElement = event.target;
        this.activeModal = MODAL.APP;         // open first, fetch under the animation
        this.loadAppObjects(event.detail.appId);
    }

    handleAppRetry() {
        if (this.selectedUserId) this.loadUser(this.selectedUserId, true);
    }

    /* Open, then fetch only if this panel has never been loaded for this user.
       Reopening a panel should cost nothing. */

    handleOpenLoginHistory(event) {
        this._triggerElement = event.target;
        this.activeModal = MODAL.LOGIN;
        if (this.loginState === STATE.EMPTY) this.loadLoginHistory();
    }

    handleOpenPermSets(event) {
        this._triggerElement = event.target;
        this.activeModal = MODAL.PERMSETS;
        if (this.permSetState === STATE.EMPTY) this.loadPermSets();
    }

    handleOpenGroups(event) {
        this._triggerElement = event.target;
        this.activeModal = MODAL.GROUPS;
        if (this.groupState === STATE.EMPTY) this.loadGroups();
    }

    handleLoginRetry()   { this.loadLoginHistory(); }
    handlePermSetRetry() { this.loadPermSets(); }
    handleGroupRetry()   { this.loadGroups(); }

    /**
     * Fetch a row's detail on first expand only.
     *
     * With fifty objects in an app, prefetching the whole list would mean fifty
     * round trips for data the admin may never look at. The cache lives here
     * rather than in the table so an expanded row costs nothing to reopen.
     */
    async handleLoadDetail(event) {
        const apiName = event.detail.apiName;
        const table = this.template.querySelector('c-pe-object-table');
        if (!table) return;

        table.setDetail(apiName, undefined, STATE.LOADING, undefined);
        try {
            const detail = await getObjectDetail({
                userId: this.selectedUserId,
                objectApiName: apiName
            });
            table.setDetail(apiName, detail, STATE.LOADED, undefined);
        } catch (e) {
            table.setDetail(apiName, undefined, STATE.ERROR, parseError(e));
        }
    }

    handleRailRetry() {
        if (this.selectedAppId) this.loadAppObjects(this.selectedAppId);
    }

    /** Focus returns to the control that opened the modal, not the page top. */
    handleModalClose() {
        this.activeModal = MODAL.NONE;
        this.syncUrl();
        this._triggerElement?.focus?.();
    }

    async handleRefresh() {
        await refreshCache();
        if (this.selectedUserId) {
            await this.loadUser(this.selectedUserId, true);
        }
    }

    handleCopyLink() {
        const link = shareableLink({
            userId: this.selectedUserId,
            appId: this.selectedAppId,
            objectId: null,
            tab: null
        });
        navigator.clipboard?.writeText(link);
    }

    syncUrl() {
        writeState({
            userId: this.selectedUserId,
            appId: this.selectedAppId,
            objectId: null,
            tab: null
        });
    }
}
