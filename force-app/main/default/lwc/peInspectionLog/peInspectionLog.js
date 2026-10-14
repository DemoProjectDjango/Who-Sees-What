import { LightningElement, api } from 'lwc';

/* Action codes are written by PEAccessGate, not chosen here. Anything not in
   this map renders as its raw code rather than a blank cell — an unmapped
   action is still evidence, and hiding it would be the wrong failure. */
const ACTION_LABELS = {
    RESOLVE_USER: 'Resolved user',
    GET_APP_OBJECTS: 'Viewed app objects',
    GET_OBJECT_DETAIL: 'Viewed object detail',
    VIEW_LOGIN_HISTORY: 'Viewed login history',
    VIEW_PERM_SETS: 'Viewed permission sets',
    VIEW_PERM_SET_GROUPS: 'Viewed permission set groups',
    VIEW_LICENSE_USERS: 'Viewed license holders'
};

const MINUTE = 60000;
const HOUR = 3600000;
const DAY = 86400000;

/**
 * The inspection table. Presentational: Home owns the fetch, so the chart, the
 * figures and this table can never disagree about how current they are.
 */
export default class PeInspectionLog extends LightningElement {
    _rows = [];

    @api
    get rows() {
        return this._rows;
    }
    set rows(value) {
        this._rows = Array.isArray(value) ? value : [];
    }

    get displayRows() {
        return this._rows.map((r) => ({
            ...r,
            actionLabel: ACTION_LABELS[r.action] ?? r.action,
            /* A null name means FLS on the lookup was not granted, or the user
               was deleted. Which one is unknowable from here, so claim neither. */
            inspectorDisplay: r.inspectorName ?? 'Unknown user',
            subjectDisplay: r.subjectName ?? 'Not user-specific',
            subjectClass: r.subjectName ? 'cell_subject' : 'cell_subject is-none',
            detailDisplay: r.detail ?? '',
            relative: this.relativeTime(r.inspectedAt),
            exact: this.exactTime(r.inspectedAt)
        }));
    }

    get hasRows() {
        return this._rows.length > 0;
    }

    /* Relative time is what an auditor scanning for "was this recent?" actually
       reads; the exact stamp stays available on hover for the one row that
       matters. */
    relativeTime(value) {
        if (!value) return '';
        const then = new Date(value).getTime();
        if (Number.isNaN(then)) return '';

        const delta = Date.now() - then;
        if (delta < MINUTE) return 'just now';
        if (delta < HOUR) {
            const m = Math.floor(delta / MINUTE);
            return `${m} min ago`;
        }
        if (delta < DAY) {
            const h = Math.floor(delta / HOUR);
            return h === 1 ? '1 hour ago' : `${h} hours ago`;
        }
        const d = Math.floor(delta / DAY);
        if (d === 1) return 'yesterday';
        if (d < 7) return `${d} days ago`;
        return this.exactTime(value);
    }

    exactTime(value) {
        if (!value) return '';
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return '';
        return d.toLocaleString(undefined, {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }
}
