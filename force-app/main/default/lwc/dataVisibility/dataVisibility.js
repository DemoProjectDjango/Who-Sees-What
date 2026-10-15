import { LightningElement } from 'lwc';
import resolveUser from '@salesforce/apex/PermissionExplorerController.resolveUser';
import getAppObjects from '@salesforce/apex/PermissionExplorerController.getAppObjects';
import getRecordReach from '@salesforce/apex/PermissionExplorerController.getRecordReach';
import WHO_SEES_WHAT_LOGO from '@salesforce/resourceUrl/whoSeesWhatLogo';
import { STATE, parseError } from 'c/peUtils';

/**
 * Data Visibility: how many records of an object a user can actually reach.
 *
 * Permission Explorer answers whether a user may open an object. This answers
 * how much of it they can see - a different mechanism (record sharing rather
 * than object permissions) reached by an identical path.
 *
 * The shell, the stage accordion and the stylesheet are Permission Explorer's,
 * deliberately. Two tools that ask the same three questions should not look
 * like two different products, and the first build of this tab proved how
 * quickly a bespoke layout drifts away from the one beside it.
 */
export default class DataVisibility extends LightningElement {
    projectLogo = WHO_SEES_WHAT_LOGO;

    selectedUserId;
    selectedUserName;

    appList = { apps: [] };
    appState = STATE.EMPTY;
    appError;
    selectedAppId;
    selectedAppLabel;

    objectRows = [];
    railState = STATE.EMPTY;
    railError;
    selectedObjectApiName;
    selectedObjectLabel;

    reach;
    reachLoading = false;
    recounting = false;
    reachError;

    /* Accordion state. Private fields with getters so a stage can be forced
       shut by progress without the template reaching into internals. */
    _whoOpen = true;
    _appOpen = false;
    _objectsOpen = false;

    /* ------------------------------ stage: who ------------------------------ */

    async handleUserSelect(event) {
        const userId = event.detail?.userId ?? event.detail;
        if (!userId || userId === this.selectedUserId) return;

        this.selectedUserId = userId;
        /* peUserColumn emits { userId } and nothing else, so the name has to
           come from resolveUser below. Reading it off the event left the Who
           row reading "No user selected" next to a green tick. */
        this.selectedUserName = undefined;

        /* Everything downstream described the previous user. A stale record
           count beside a new name is worse than no count at all. */
        this.resetFromApp();

        this._whoOpen = false;
        this._appOpen = true;

        await this.loadApps();
    }

    async loadApps() {
        this.appState = STATE.LOADING;
        this.appError = undefined;
        try {
            const ctx = await resolveUser({
                userId: this.selectedUserId,
                forceRefresh: false
            });
            this.appList = ctx?.apps ?? { apps: [] };
            /* UserContext carries `summary`, not `user`. */
            this.selectedUserName = ctx?.summary?.name;
            this.appState = this.appList.apps.length
                ? STATE.LOADED
                : STATE.LOADED_EMPTY;
        } catch (e) {
            this.appError = parseError(e)?.message;
            this.appState = STATE.ERROR;
        }
    }

    handleAppRetry() {
        this.loadApps();
    }

    /* ----------------------------- stage: where ----------------------------- */

    async handleAppSelect(event) {
        const appId = event.detail?.appId ?? event.detail;
        if (!appId || appId === this.selectedAppId) return;

        this.selectedAppId = appId;
        this.selectedAppLabel =
            this.appList.apps.find((a) => a.developerName === appId)?.label ?? appId;

        this.resetFromObject();

        this._appOpen = false;
        this._objectsOpen = true;

        await this.loadObjects();
    }

    async loadObjects() {
        this.railState = STATE.LOADING;
        this.railError = undefined;
        try {
            const rows = await getAppObjects({
                userId: this.selectedUserId,
                appDeveloperName: this.selectedAppId
            });
            this.objectRows = rows ?? [];
            this.railState = this.objectRows.length
                ? STATE.LOADED
                : STATE.LOADED_EMPTY;
        } catch (e) {
            this.railError = parseError(e)?.message;
            this.railState = STATE.ERROR;
        }
    }

    handleRailRetry() {
        this.loadObjects();
    }

    /* ----------------------------- stage: what ----------------------------- */

    async handleObjectSelect(event) {
        const apiName = event.detail?.apiName ?? event.detail;
        if (!apiName) return;

        this.selectedObjectApiName = apiName;
        this.selectedObjectLabel =
            this.objectRows.find((r) => r.apiName === apiName)?.label ?? apiName;

        await this.loadReach();
    }

    async loadReach(quiet) {
        /* Recount keeps the current panel on screen. Setting reachLoading would
           swap the whole workspace for a "Counting records" line and rebuild it
           a second later, which is a lot of movement to show the same object
           again. The left rail is never touched either way - it holds the
           selection, and the selection has not changed. */
        this.reachLoading = quiet ? false : true;
        this.recounting = quiet === true;
        this.reachError = undefined;
        try {
            this.reach = await getRecordReach({
                userId: this.selectedUserId,
                objectApiName: this.selectedObjectApiName
            });
        } catch (e) {
            this.reach = undefined;
            this.reachError = parseError(e)?.message;
        } finally {
            this.reachLoading = false;
            this.recounting = false;
        }
    }

    handleRefresh() {
        if (this.selectedObjectApiName) {
            this.loadReach(true);
        }
    }

    /* ------------------------------ accordion ------------------------------ */

    handleStageToggle(event) {
        const stage = event.currentTarget.dataset.stage;
        if (stage === 'who') {
            this._whoOpen = !this._whoOpen;
        } else if (stage === 'app') {
            if (this.appStageDisabled) return;
            this._appOpen = !this._appOpen;
        } else if (stage === 'objects') {
            if (this.objectStageDisabled) return;
            this._objectsOpen = !this._objectsOpen;
        }
    }

    handleStageKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleStageToggle(event);
        }
    }

    /* A stage you have not reached cannot be opened - there is nothing in it to
       show, and an empty panel reads as a failure rather than an order. */
    get appStageDisabled() {
        return !this.selectedUserId;
    }
    get objectStageDisabled() {
        return !this.selectedAppId;
    }

    get whoOpen() {
        return this._whoOpen;
    }
    get appOpen() {
        return this._appOpen && !this.appStageDisabled;
    }
    get objectsOpen() {
        return this._objectsOpen && !this.objectStageDisabled;
    }

    get whoOpenStr() {
        return String(this.whoOpen);
    }
    get appOpenStr() {
        return String(this.appOpen);
    }
    get objectsOpenStr() {
        return String(this.objectsOpen);
    }

    get isWhoDone() {
        return !!this.selectedUserId;
    }
    get isAppDone() {
        return !!this.selectedAppId;
    }
    get isObjectDone() {
        return !!this.selectedObjectApiName;
    }

    /* -------------------------- class composition -------------------------- */

    sectionClass(name, open, done, disabled) {
        return [
            'nav_section',
            `nav_section_${name}`,
            open ? 'nav_section_open' : 'nav_section_shut',
            done ? 'nav_section_done' : '',
            disabled ? 'nav_section_waiting' : ''
        ]
            .filter(Boolean)
            .join(' ');
    }

    get whoSectionClass() {
        return this.sectionClass('who', this.whoOpen, this.isWhoDone, false);
    }
    get whereSectionClass() {
        return this.sectionClass(
            'where',
            this.appOpen,
            this.isAppDone,
            this.appStageDisabled
        );
    }
    get objectSectionClass() {
        return this.sectionClass(
            'objects',
            this.objectsOpen,
            this.isObjectDone,
            this.objectStageDisabled
        );
    }

    badgeClass(done, open, disabled) {
        if (done) return 'nav_step nav_step_done';
        if (open) return 'nav_step nav_step_active';
        return disabled ? 'nav_step nav_step_disabled' : 'nav_step';
    }

    get whoBadgeClass() {
        return this.badgeClass(this.isWhoDone, this.whoOpen, false);
    }
    get appBadgeClass() {
        return this.badgeClass(this.isAppDone, this.appOpen, this.appStageDisabled);
    }
    get objectBadgeClass() {
        return this.badgeClass(
            this.isObjectDone,
            this.objectsOpen,
            this.objectStageDisabled
        );
    }

    get whoHeadClass() {
        return 'nav_section_head clickable_head';
    }
    get whereHeadClass() {
        return `nav_section_head ${
            this.appStageDisabled ? 'head_disabled' : 'clickable_head'
        }`;
    }
    get objectHeadClass() {
        return `nav_section_head ${
            this.objectStageDisabled ? 'head_disabled' : 'clickable_head'
        }`;
    }

    chevron(open) {
        return open ? 'stage_chevron stage_chevron_open' : 'stage_chevron';
    }
    get whoChevronClass() {
        return this.chevron(this.whoOpen);
    }
    get appChevronClass() {
        return this.chevron(this.appOpen);
    }
    get objectChevronClass() {
        return this.chevron(this.objectsOpen);
    }

    get whoToggleTitle() {
        return this.whoOpen ? 'Click to collapse Who' : 'Click to expand Who';
    }
    get appToggleTitle() {
        if (this.appStageDisabled) return 'Select a user first';
        return this.appOpen ? 'Click to collapse Where' : 'Click to expand Where';
    }
    get objectToggleTitle() {
        if (this.objectStageDisabled) return 'Select an app first';
        return this.objectsOpen
            ? 'Click to collapse Object'
            : 'Click to expand Object';
    }

    /* A collapsed row has to carry its selection, or compressing the accordion
       loses the context the breadcrumb is also showing. */
    get whoSummary() {
        return this.selectedUserName ?? 'No user selected';
    }
    get appSummary() {
        if (!this.selectedUserId) return 'Select a user first';
        return this.selectedAppLabel ?? 'No app selected';
    }
    get objectSummary() {
        if (!this.selectedAppId) return 'Select an app first';
        if (this.selectedObjectLabel) return this.selectedObjectLabel;
        const n = this.objectRows.length;
        return n ? `${n} objects` : 'No object selected';
    }

    /* ------------------------------ workspace ------------------------------ */

    get crumbs() {
        const out = [];
        if (this.selectedUserName) {
            out.push({ key: 'u', label: this.selectedUserName, separator: false });
        }
        if (this.selectedAppLabel) {
            out.push({ key: 'a', label: this.selectedAppLabel, separator: true });
        }
        if (this.selectedObjectLabel) {
            out.push({ key: 'o', label: this.selectedObjectLabel, separator: true });
        }
        return out;
    }

    get placeholderHeading() {
        if (!this.selectedUserId) return 'Start with Who';
        if (!this.selectedAppId) return 'Now choose Where';
        return 'Choose an Object or Tab';
    }

    get placeholderText() {
        if (!this.selectedUserId) {
            return 'Choose a user from WHO on the left to begin.';
        }
        if (!this.selectedAppId) {
            return 'Choose an app from WHERE on the left to see what it reaches.';
        }
        return 'Choose an object to see how many of its records this user can reach, and why.';
    }

    progressClass(done, current) {
        if (done) return 'progress_step progress_done';
        if (current) return 'progress_step progress_current';
        return 'progress_step';
    }

    get whoProgressClass() {
        return this.progressClass(!!this.selectedUserId, !this.selectedUserId);
    }
    get appProgressClass() {
        return this.progressClass(
            !!this.selectedAppId,
            !!this.selectedUserId && !this.selectedAppId
        );
    }
    get objectProgressClass() {
        return this.progressClass(
            !!this.selectedObjectApiName,
            !!this.selectedAppId && !this.selectedObjectApiName
        );
    }

    get cannotRefresh() {
        return !this.selectedObjectApiName || this.reachLoading || this.recounting;
    }

    get recountLabel() {
        return this.recounting ? 'Recounting' : 'Recount';
    }

    /* ------------------------------- resets ------------------------------- */

    resetFromApp() {
        this.appList = { apps: [] };
        this.appState = STATE.EMPTY;
        this.selectedAppId = undefined;
        this.selectedAppLabel = undefined;
        this.resetFromObject();
    }

    resetFromObject() {
        this.objectRows = [];
        this.railState = STATE.EMPTY;
        this.selectedObjectApiName = undefined;
        this.selectedObjectLabel = undefined;
        this.reach = undefined;
        this.reachError = undefined;
    }
}
