import { LightningElement, api } from 'lwc';
import getRecordPage from '@salesforce/apex/PermissionExplorerController.getRecordPage';

/* The reason and access-level label maps moved out with the aggregate block.
   peRecordTable keeps its own copy for the Reason column, which is now the only
   place a RowCause is shown. */

/**
 * Record-level reach for one object, laid out like the Explorer's object panel.
 *
 * The one thing this must not get wrong is the difference between an exact
 * figure and a floor. Everything else is presentation.
 */
export default class PeRecordAccessPanel extends LightningElement {
    @api loading = false;
    @api error;

    _reach;
    _userId;

    @api
    get reach() {
        return this._reach;
    }
    set reach(value) {
        const sameObject =
            this._reach &&
            value &&
            this._reach.objectApiName === value.objectApiName;

        this._reach = value;
        /* Setter rather than connectedCallback: the panel is reused as the
           selection changes, so the fetch has to follow the data in, not the
           component's first render. */
        /* A recount on the object already shown is not a new selection. Clearing
           the rows there empties the table for the length of a round trip and
           throws away the mode, the sort and the page the admin had scrolled
           to - all to redisplay the same list. Only a genuine change of object
           resets. */
        if (!sameObject) {
            this.resetList();
        }

        if (value && value.hasObjectRead !== false) {
            /* On a public object, or one the user holds View All on, access does
               not come from share rows - there usually are none. Opening in
               ACCESSIBLE mode there shows an empty list beneath a headline
               saying every record is reachable, which reads as a contradiction.
               Those objects open on ALL records instead. */
            this.loadPage(false, sameObject);
        }
    }

    @api
    get userId() {
        return this._userId;
    }
    set userId(value) {
        this._userId = value;
    }

    rows = [];
    reachableOnly = true;
    totalReachable;
    totalRecords;
    totalIsFloor = false;
    sharingBypassed = false;
    showReason = true;
    uniformReason;
    sortField = 'Name';
    searchTerm = '';
    cursor;
    hasMore = false;
    listLoading = false;
    loadingMore = false;
    searchSupported = true;
    listNotes = [];

    get hasReach() {
        return !!this.reach && this.reach.hasObjectRead !== false;
    }

    get blocked() {
        return !!this.reach && this.reach.hasObjectRead === false;
    }

    /* --------------------------- the card strip --------------------------- */

    /* Four cards in the Explorer's tile register. Null counts are rendered as
       an em dash with a muted tile: a question that does not apply to this
       object is not the same as an answer of zero. */
    get tiles() {
        const r = this.reach;
        if (!r) return [];

        return [
            {
                key: 'sharing',
                label: 'Sharing model',
                text: r.sharingLabel ?? 'Unknown',
                tileClass: r.isPublic ? 'tile tile_caution' : 'tile tile_grant'
            },
            {
                key: 'total',
                label: 'Records in scope',
                text: this.fmt(r.totalRecords),
                tileClass: 'tile'
            },
            {
                key: 'owned',
                label: 'Owned by user',
                text: this.fmt(r.ownedRecords),
                tileClass: r.ownedRecords ? 'tile tile_grant' : 'tile'
            },
            {
                key: 'shared',
                label: 'Shared to user',
                text: this.fmt(r.sharedRecords),
                tileClass: r.sharedRecords ? 'tile tile_grant' : 'tile'
            },
            {
                key: 'reachable',
                /* The qualifier rides in the label rather than its own card.
                   Dropping it entirely would let the panel imply a precision it
                   does not have: role hierarchy and implicit sharing are
                   invisible to these counts, which matters most in the orgs
                   where nobody can eyeball the table and check. */
                label: r.isExact ? 'Reachable (exact)' : 'Reachable (at least)',
                text: this.reachableText,
                tileClass: r.isExact ? 'tile tile_strong' : 'tile tile_caution'
            }
        ];
    }

    fmt(n) {
        return n === null || n === undefined ? '—' : n.toLocaleString();
    }

    get reachableText() {
        const n = this.reach?.reachableRecords;
        const t = this.reach?.totalRecords;
        if (n === null || n === undefined) return '—';
        return t === null || t === undefined
            ? n.toLocaleString()
            : `${n.toLocaleString()} of ${t.toLocaleString()}`;
    }

    get basisLine() {
        return this.reach?.basis;
    }

    /* ----------------------------- explanation ----------------------------- */

    /* The old "How they reach it" getters lived here. They were named `rows`,
       which the record-list field of the same name shadowed once it arrived -
       so that block silently started printing record labels instead of the
       owned/shared split. "Why they reach it" answers the same question from
       the share table with the reason attached, so the block is gone rather
       than renamed. */

    get notes() {
        return (this.reach?.notes ?? []).map((text, i) => ({ key: `n${i}`, text }));
    }

    get hasNotes() {
        return this.notes.length > 0;
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }

    /* The "Why they reach it" aggregate lived here. Removed: the table's Reason
       column answers the same question per row, and two views of one fact on a
       single panel is how they drift apart. getReasonBreakdown stays in the
       Apex - it is still the cheapest way to get the split without reading
       every record, if a future view needs it. */

    /* Sharing is not the mechanism on a public object, so offering a mode that
       lists share rows invites the question of why it is empty. */
    get modeSwitchAvailable() {
        return !(this._reach?.isPublic || this._reach?.hasViewAll);
    }

    /* -------------------------------- list -------------------------------- */

    resetList() {
        this.rows = [];
        this.cursor = undefined;
        this.hasMore = false;
        this.totalReachable = undefined;
        this.listNotes = [];
    }

    async loadPage(append, quiet) {
        if (!this._reach || !this._userId) return;

        if (append) {
            this.loadingMore = true;
        } else if (quiet) {
            /* Rows stay on screen and are swapped only when the new ones land.
               A table that blanks and refills on every recount reads as a
               failure even when nothing went wrong. */
            this.listLoading = false;
        } else {
            this.listLoading = true;
            this.rows = [];
        }

        try {
            const page = await getRecordPage({
                userId: this._userId,
                objectApiName: this._reach.objectApiName,
                reachableOnly: this.reachableOnly,
                searchTerm: this.searchTerm,
                sortField: this.sortField,
                cursor: append ? this.cursor : null
            });

            const incoming = page?.rows ?? [];
            this.rows = append ? [...this.rows, ...incoming] : incoming;
            /* A quiet reload lands on the first page, so any cursor from the
               previous scroll position no longer describes where we are. */
            this.cursor = page?.nextCursor;
            this.hasMore = page?.hasMore === true;
            this.totalReachable = page?.totalReachable;
            this.totalRecords = page?.totalRecords;
            this.totalIsFloor = page?.totalIsFloor === true;
            this.sharingBypassed = page?.sharingBypassed === true;
            this.showReason = page?.showReason !== false;
            this.uniformReason = page?.uniformReason;
            this.searchSupported = page?.searchSupported !== false;
            this.listNotes = page?.notes ?? [];
        } catch (e) {
            this.listNotes = ['Records could not be listed. Try again.'];
            if (!append) {
                this.rows = [];
            }
        } finally {
            this.listLoading = false;
            this.loadingMore = false;
        }
    }

    handleFilterToggle(event) {
        this.reachableOnly = event.target.checked;
        /* A search typed while unfiltered means nothing once the share table
           drives the page, and carrying it over would silently narrow a list
           that cannot honour it. */
        if (this.reachableOnly) {
            this.searchTerm = '';
        }
        this.resetList();
        this.loadPage(false);
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    handleSearchCommit(event) {
        if (event.type === 'keydown' && event.key !== 'Enter') return;
        this.resetList();
        this.loadPage(false);
    }

    handleSortChange(event) {
        this.sortField = event.target.value;
        this.resetList();
        this.loadPage(false);
    }

    handleLoadMore() {
        this.loadPage(true);
    }

    /* ------------------------------ list view ------------------------------ */

    /* Both figures come from their own queries, so neither is the size of the
       page. That is what makes this line honest - the earlier design avoided a
       filtered list precisely because I thought it could not be. */
    get showingLine() {
        const shown = this.rows.length.toLocaleString();

        if (!this.reachableOnly) {
            return this.totalRecords === null || this.totalRecords === undefined
                ? `Showing ${shown}`
                : `Showing ${shown} of ${this.totalRecords.toLocaleString()} records`;
        }
        if (this.totalReachable === null || this.totalReachable === undefined) {
            return `Showing ${shown}`;
        }
        const qualifier = this.totalIsFloor ? 'at least ' : '';
        return `Showing ${shown} of ${qualifier}${this.totalReachable.toLocaleString()} reachable`;
    }

    /* The floor caveat appears once, beside the count it qualifies, and only
       where hierarchy access can actually hide from a share table. */
    get floorNote() {
        return this.reachableOnly && this.totalIsFloor
            ? 'Records reached only through role hierarchy or implicit sharing leave no share row, so the total may be higher.'
            : null;
    }

    get searchDisabled() {
        return !this.searchSupported;
    }

    get searchPlaceholder() {
        return this.searchSupported
            ? 'Search name'
            : 'Search unavailable in this mode';
    }

    get sortOptions() {
        return [
            { value: 'Name', label: 'Sort: Name' },
            { value: 'CreatedDate', label: 'Sort: Created' },
            { value: 'LastModifiedDate', label: 'Sort: Modified' },
            { value: 'Id', label: 'Sort: Id' }
        ].map((o) => ({ ...o, selected: o.value === this.sortField }));
    }

    get hasListNotes() {
        return this.listNotes.length > 0;
    }

    get listNoteRows() {
        return this.listNotes.map((text, i) => ({ key: `ln${i}`, text }));
    }
}
