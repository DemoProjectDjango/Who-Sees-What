import { LightningElement, api } from 'lwc';

const PAGE = 60;

/**
 * Field permissions table.
 *
 * A 500-field object rendering a source chip per row will crawl, so rendering is
 * capped and grown on demand rather than virtualised. Search and the access
 * filter are the affordances an admin actually reaches for — nobody scrolls 500
 * rows looking for one field — so they do the real narrowing, and "show more"
 * covers the rest without a scroll-position calculation to get wrong.
 */
export default class PeFieldTable extends LightningElement {
    _fields = [];
    term = '';
    segment = 'all';
    limit = PAGE;

    @api
    get fields() { return this._fields; }
    set fields(value) {
        this._fields = value ?? [];
        this.limit = PAGE;
    }

    get filtered() {
        const term = this.term.toLowerCase();
        return this._fields.filter((f) => {
            if (term && !`${f.apiName} ${f.label}`.toLowerCase().includes(term)) return false;
            switch (this.segment) {
                case 'readable': return f.readable;
                case 'editable': return f.editable;
                case 'none':     return !f.readable && !f.editable && !f.flsNotApplicable;
                default:         return true;
            }
        });
    }

    get visibleRows() {
        return this.filtered.slice(0, this.limit).map((f) => ({
            ...f,
            // Sentence case, matching the CRUD tiles directly above. Two
            // registers for the same verdict on one screen reads as two
            // different kinds of fact.
            readText:  f.readable ? 'Yes' : 'No',
            editText:  f.editable ? 'Yes' : 'No',
            readClass: f.readable ? 'flag flag_on' : 'flag flag_off',
            editClass: f.editable ? 'flag flag_on' : 'flag flag_off',
            hasSources: (f.readSources?.length ?? 0) > 0 || (f.editSources?.length ?? 0) > 0,
            // Edit implies read, so the narrower grant is the more useful chip.
            bestSources: f.editSources?.length ? f.editSources : f.readSources,
            naShort: 'FLS not applicable'
        }));
    }

    get segments() {
        const counts = this._fields;
        return [
            { key: 'all',      label: `All ${counts.length}` },
            { key: 'readable', label: `Readable ${counts.filter((f) => f.readable).length}` },
            { key: 'editable', label: `Editable ${counts.filter((f) => f.editable).length}` },
            { key: 'none',     label: `No access ${counts.filter((f) => !f.readable && !f.editable && !f.flsNotApplicable).length}` }
        ].map((s) => ({
            ...s,
            class: s.key === this.segment ? 'seg seg_on' : 'seg'
        }));
    }

    get hasMore() { return this.filtered.length > this.limit; }

    get tally() {
        const shown = Math.min(this.limit, this.filtered.length);
        return `Showing ${shown} of ${this.filtered.length}`;
    }

    handleSearch(event) {
        this.term = event.target.value ?? '';
        this.limit = PAGE;
    }

    handleSegment(event) {
        this.segment = event.currentTarget.dataset.key;
        this.limit = PAGE;
    }

    showMore() {
        this.limit += PAGE;
    }
}