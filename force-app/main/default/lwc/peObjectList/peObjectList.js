import { LightningElement, api } from 'lwc';
import { STATE } from 'c/peUtils';

const PAGE = 40;

/**
 * The object list for one app, living in the WHERE column.
 *
 * This replaced the object modal. The modal made the admin lose the app they
 * were standing in every time they looked at an object, which is exactly the
 * context the question depends on: "why can she not see Opportunities *in
 * Service*" is a different question from "does she have read on Opportunity".
 */
export default class PeObjectList extends LightningElement {
    @api appLabel;
    @api state = STATE.EMPTY;
    @api error;
    @api selectedApiName;

    _rows = [];
    term = '';
    chip = 'all';
    limit = PAGE;

    @api
    get rows() { return this._rows; }
    set rows(value) {
        this._rows = value ?? [];
        this.limit = PAGE;
    }

    get countText() {
        const n = this._rows.filter((r) => r.isObjectTab !== false).length;
        return `${n} object${n === 1 ? '' : 's'}`;
    }

    /** Distinguishes "app has nothing" from "your filter matched nothing". */
    get isEmptyApp() {
        return this.state === STATE.LOADED_EMPTY || (this.state === STATE.LOADED && !this._rows.length);
    }

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

    /**
     * One dot and one word per row. The dot alone would not survive being
     * printed, and the word alone scans too slowly down forty rows.
     */
    get visibleRows() {
        return this.filtered.slice(0, this.limit).map((r) => {
            const notAnObject = r.isObjectTab === false;
            const selected = r.apiName === this.selectedApiName;

            let tone = 'grant';
            let tag = 'Tab';

            if (notAnObject) {
                tone = 'na';
                tag = 'Not an object';
            } else if (!r.canRead) {
                tone = 'deny';
                tag = 'No access';
            } else if (r.accessWithoutTab) {
                tone = 'mute';
                tag = 'No tab';
            }

            return {
                ...r,
                notAnObject,
                selectedStr: String(selected),
                rowClass: selected ? 'orow orow_on' : 'orow',
                dotClass: `odot odot_${tone}`,
                tagClass: `otag otag_${tone}`,
                tag
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
        ].map((c) => ({ ...c, class: c.key === this.chip ? 'chip chip_on' : 'chip' }));
    }

    get hasMore() { return this.filtered.length > this.limit; }

    handleFilter(event) {
        this.term = event.target.value ?? '';
        this.limit = PAGE;
    }

    handleChip(event) {
        this.chip = event.currentTarget.dataset.key;
        this.limit = PAGE;
    }

    showMore() { this.limit += PAGE; }

    handleSelect(event) {
        const el = event.currentTarget;
        this.dispatchEvent(new CustomEvent('objectselect', {
            detail: { apiName: el.dataset.api, label: el.dataset.label }
        }));
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}
