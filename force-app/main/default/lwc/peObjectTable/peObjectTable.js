import { LightningElement, api } from 'lwc';
import { STATE } from 'c/peUtils';

const PAGE = 40;

/**
 * The expandable object table that replaced the rail plus sub-tabs.
 *
 * Everything is visible at once, several rows can be open side by side for
 * comparison, and there is no close–click–reopen cycle per object. That is what
 * the prev/next arrows in the old design were compensating for, so they are gone.
 *
 * Rendering is capped at 40 rows and grown on demand: an app with fifty objects
 * is normal here, and the filter chips do the real narrowing.
 */
export default class PeObjectTable extends LightningElement {
    @api state = STATE.EMPTY;
    @api error;

    _rows = [];
    _details = {};       // apiName -> { detail, state, error }
    _expanded = new Set();

    term = '';
    chip = 'all';
    limit = PAGE;

    @api
    get rows() { return this._rows; }
    set rows(value) {
        this._rows = value ?? [];
        this._expanded = new Set();
        this._details = {};
        this.limit = PAGE;
    }

    /** Parent pushes fetched detail in through this. */
    @api
    setDetail(apiName, detail, state, error) {
        this._details = {
            ...this._details,
            [apiName]: { detail, state, error }
        };
    }

    /* ------------------------------ filtering ------------------------------ */

    get filtered() {
        const term = this.term.toLowerCase();
        return this._rows.filter((r) => {
            if (term && !`${r.apiName} ${r.label}`.toLowerCase().includes(term)) return false;
            switch (this.chip) {
                case 'readable': return r.canRead;
                case 'editable': return r.canEdit;
                case 'none':     return r.isObjectTab && !r.canRead;
                case 'notab':    return r.accessWithoutTab;
                default:         return true;
            }
        });
    }

    get visibleRows() {
        return this.filtered.slice(0, this.limit).map((r) => {
            const d = this._details[r.apiName] ?? {};
            return {
                ...r,
                isExpanded: this._expanded.has(r.apiName),
                detail: d.detail,
                detailState: d.state ?? STATE.LOADING,
                detailError: d.error
            };
        });
    }

    get chips() {
        const r = this._rows;
        return [
            { key: 'all',      label: `All ${r.length}` },
            { key: 'readable', label: `Readable ${r.filter((x) => x.canRead).length}` },
            { key: 'editable', label: `Editable ${r.filter((x) => x.canEdit).length}` },
            { key: 'none',     label: `No access ${r.filter((x) => x.isObjectTab && !x.canRead).length}` },
            { key: 'notab',    label: `No tab ${r.filter((x) => x.accessWithoutTab).length}` }
        ].map((c) => ({
            ...c,
            class: c.key === this.chip ? 'chip chip_on' : 'chip'
        }));
    }

    get hasMore() { return this.filtered.length > this.limit; }

    get tally() {
        const shown = Math.min(this.limit, this.filtered.length);
        return `Showing ${shown} of ${this.filtered.length}`;
    }

    /* ------------------------------ handlers ------------------------------ */

    handleFilter(event) {
        this.term = event.target.value ?? '';
        this.limit = PAGE;
    }

    handleChip(event) {
        this.chip = event.currentTarget.dataset.key;
        this.limit = PAGE;
    }

    showMore() {
        this.limit += PAGE;
    }

    /**
     * Collapse is local. Expand asks the parent to fetch, but only the first
     * time — a row the admin already opened stays cached, so re-expanding costs
     * nothing.
     */
    handleToggle(event) {
        const apiName = event.detail.apiName;
        const next = new Set(this._expanded);

        if (next.has(apiName)) {
            next.delete(apiName);
        } else {
            next.add(apiName);
            if (!this._details[apiName]) {
                this.dispatchEvent(new CustomEvent('loaddetail', { detail: { apiName } }));
            }
        }
        this._expanded = next;
    }

    handleRowRetry(event) {
        const apiName = event.detail.apiName;
        const rest = { ...this._details };
        delete rest[apiName];
        this._details = rest;
        this.dispatchEvent(new CustomEvent('loaddetail', { detail: { apiName } }));
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}