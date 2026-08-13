import { LightningElement, api, wire } from 'lwc';
import searchUsers from '@salesforce/apex/PermissionExplorerController.searchUsers';
import getFilterOptions from '@salesforce/apex/PermissionExplorerController.getFilterOptions';
import {
    STATE, SORT, PAGE_SIZE, parseError,
    CursorStack, filterSignature, relativeTime
} from 'c/peUtils';

/**
 * Column 1. Presentational plus its own pagination bookkeeping — the parent
 * owns which user is selected, this component owns how the list is walked.
 *
 * Active users only. The Apex side enforces it; this component does not offer
 * an Active/Inactive filter at all, because a filter the server ignores is a
 * lie and a filter the server enforces does not need a control.
 */
export default class PeUserColumn extends LightningElement {
    @api selectedUserId;

    state = STATE.EMPTY;
    error;
    rows = [];
    hasMore = false;
    capReached = false;
    filtersOpen = false;

    profileOptions = [];
    roleOptions = [];

    cursors = new CursorStack();
    filters = { term: '', profileId: null, roleId: null, userType: null, sortField: SORT.RECENT };

    connectedCallback() {
        this.load();
    }

    @wire(getFilterOptions)
    wiredOptions({ data }) {
        if (data) {
            this.profileOptions = data.profiles ?? [];
            this.roleOptions = data.roles ?? [];
        }
    }

    /* ------------------------------ derived ------------------------------ */

    get isLoading()  { return this.state === STATE.LOADING; }
    get shownCount() { return this.rows.length; }
    get pageNumber() { return this.cursors.pageNumber; }
    get canGoBack()  { return this.cursors.canGoBack; }
    get filtersOpenStr() { return String(this.filtersOpen); }

    get activeFilterCount() {
        return [this.filters.profileId, this.filters.roleId, this.filters.userType]
            .filter(Boolean).length;
    }

    get emptyHeadline() {
        return this.filters.term ? 'No active users match that search' : 'No active users to show';
    }

    get emptyDetail() {
        return this.filters.term
            ? 'Check the spelling, or clear the search to browse recently active users.'
            : 'Adjust the filters to widen the search.';
    }

    /** Display-ready rows for peListbox. Formatting happens once, here. */
    get listItems() {
        return this.rows.map((r) => ({
            id: r.userId,
            label: r.name,
            secondary: r.username,
            meta: [r.profileName, relativeTime(r.lastLogin)].filter(Boolean).join(' · ')
        }));
    }

    /* ------------------------------ loading ------------------------------ */

    async load() {
        this.state = STATE.LOADING;
        this.error = undefined;
        try {
            const result = await searchUsers({
                term: this.filters.term || null,
                profileId: this.filters.profileId,
                roleId: this.filters.roleId,
                userType: this.filters.userType,
                sortField: this.filters.sortField,
                cursor: this.cursors.current,
                pageSize: PAGE_SIZE
            });
            this.rows = result.records ?? [];
            this.hasMore = result.hasMore;
            this.capReached = result.capReached;
            this._nextCursor = result.nextCursor;
            this.state = this.rows.length ? STATE.LOADED : STATE.LOADED_EMPTY;
        } catch (e) {
            this.error = parseError(e);
            this.state = STATE.ERROR;
        }
    }

    /**
     * Any filter or search change invalidates the cursor stack. Guarded rather
     * than assumed — a stale cursor against new filters returns results that
     * look right and are not.
     */
    applyFilterChange(patch) {
        this.filters = { ...this.filters, ...patch };
        this.cursors.syncFilters(filterSignature(this.filters));
        this.load();
    }

    /* ------------------------------ handlers ------------------------------ */

    handleSearch(event) {
        this.applyFilterChange({ term: event.detail.term });
    }

    handleSort(event) {
        this.applyFilterChange({ sortField: event.target.value });
    }

    handleFilter(event) {
        const key = event.target.dataset.key;
        this.applyFilterChange({ [key]: event.target.value || null });
    }

    toggleFilters() {
        this.filtersOpen = !this.filtersOpen;
    }

    handleNext() {
        this.cursors.push(this._nextCursor);
        this.load();
    }

    handleBack() {
        this.cursors.pop();
        this.load();
    }

    handleRetry() {
        this.load();
    }

    handleSelect(event) {
        this.dispatchEvent(new CustomEvent('userselect', {
            detail: { userId: event.detail.id }
        }));
    }
}