import { LightningElement, api } from 'lwc';

const REASON_LABELS = {
    Owner: 'Owner',
    Manual: 'Manual share',
    Rule: 'Sharing rule',
    Team: 'Team',
    Territory: 'Territory',
    ImplicitChild: 'Parent record',
    ImplicitParent: 'Child record'
};

/**
 * The record list. Presentational: the page owns fetching and paging.
 *
 * Its one editorial job is the delete contradiction. When object permissions
 * allow delete but the record does not - the normal state for anything reached
 * by a manual share, since a manual share can only grant Read or Read/Write -
 * the row says so rather than leaving it to be inferred from two chips.
 */
export default class PeRecordTable extends LightningElement {
    @api rows = [];
    @api loading = false;
    @api hasMore = false;
    @api loadingMore = false;
    @api showReason = false;

    get displayRows() {
        return (this.rows ?? []).map((r) => ({
            ...r,
            reasonLabel: REASON_LABELS[r.reason] ?? r.reason ?? '—',
            ownerDisplay: r.ownerName ?? '—',
            readClass: this.chipClass(r.canRead),
            editClass: this.chipClass(r.canEdit),
            deleteClass: this.chipClass(r.canDelete),
            rowClass: r.deleteBlockedByRecord ? 'row row_flagged' : 'row',
            deleteTitle: r.deleteBlockedByRecord
                ? 'Object permissions allow delete, but this record does not. A share can grant Read or Read/Write only.'
                : undefined
        }));
    }

    chipClass(on) {
        return on ? 'chip chip_on' : 'chip chip_off';
    }

    get hasRows() {
        return this.displayRows.length > 0;
    }

    get flaggedCount() {
        return (this.rows ?? []).filter((r) => r.deleteBlockedByRecord).length;
    }

    get hasFlagged() {
        return this.flaggedCount > 0;
    }

    get flaggedNote() {
        const n = this.flaggedCount;
        return `${n} ${n === 1 ? 'record' : 'records'} on this page can be read but not deleted, ` +
            'despite delete being granted at object level.';
    }

    get moreLabel() {
        return this.loadingMore ? 'Loading…' : 'Load more';
    }

    handleMore() {
        this.dispatchEvent(new CustomEvent('loadmore'));
    }
}
