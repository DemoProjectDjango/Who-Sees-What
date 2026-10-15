import { LightningElement, api } from 'lwc';

const REASON_LABELS = {
    Owner: 'Owner',
    Manual: 'Manual share',
    Rule: 'Sharing rule',
    Team: 'Team',
    Territory: 'Territory',
    ImplicitChild: 'Parent record',
    ImplicitParent: 'Child record',
    OrgWideDefault: 'Org-wide default',
    ViewAllRecords: 'View All Records',
    /* Deduced, not reported: not the owner, no share row, private org-wide
       default, and yet the platform grants read. Which of role hierarchy,
       implicit sharing or Apex sharing is not knowable from here, so the row
       says so rather than picking one. */
    HierarchyOrImplicit: 'Hierarchy or implicit'
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
    @api objectApiName;
    @api loading = false;
    @api hasMore = false;
    @api loadingMore = false;
    @api showReason = false;

    get displayRows() {
        return (this.rows ?? []).map((r) => ({
            ...r,
            recordUrl: this.objectApiName && r.recordId
                ? `/lightning/r/${encodeURIComponent(this.objectApiName)}/${encodeURIComponent(r.recordId)}/view`
                : (r.recordId ? `/${encodeURIComponent(r.recordId)}` : null),
            reasonBadgeClass: `reason_badge ${r.reason === 'Owner' ? 'reason_owner' : r.reason === 'Manual' ? 'reason_manual' : 'reason_default'}`,
            reasonLabel: REASON_LABELS[r.reason] ?? r.reason ?? '—',
            reasonClass: r.reasonInferred ? 'cell_reason is_inferred' : 'cell_reason',
            reasonTitle: r.reasonInferred
                ? 'Deduced: the platform reports access, but no share row explains it.'
                : undefined,
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
