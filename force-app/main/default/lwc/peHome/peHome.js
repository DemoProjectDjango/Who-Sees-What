import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getOrgStats from '@salesforce/apex/PermissionExplorerController.getOrgStats';
import refreshOrgStats from '@salesforce/apex/PermissionExplorerController.refreshOrgStats';
import getRecentInspections from '@salesforce/apex/PermissionExplorerController.getRecentInspections';
import getPosture from '@salesforce/apex/PermissionExplorerController.getPosture';
import refreshPosture from '@salesforce/apex/PermissionExplorerController.refreshPosture';

/* Tab API names, not labels. standard__navItemPage resolves against these. */
const TAB = {
    EXPLORER: 'Permission_Explorer',
    LICENSES: 'License_Inspector',
    GUIDE: 'Getting_Started'
};

const ROW_LIMIT = 25;

const ACTION_LABELS = {
    RESOLVE_USER: 'Resolved user',
    GET_APP_OBJECTS: 'Viewed app objects',
    GET_OBJECT_DETAIL: 'Viewed object detail',
    VIEW_LOGIN_HISTORY: 'Viewed login history',
    VIEW_PERM_SETS: 'Viewed permission sets',
    VIEW_PERM_SET_GROUPS: 'Viewed permission set groups',
    VIEW_LICENSE_USERS: 'Viewed license holders',
    UNKNOWN: 'Other'
};

const EMPTY_PAGE = {
    rows: [],
    activity: [],
    topInspectors: [],
    actionMix: [],
    windowTotal: 0,
    priorWindowTotal: 0,
    distinctInspectors: 0,
    distinctSubjects: 0,
    readable: true
};

/**
 * The app's landing page.
 *
 * Home owns both fetches and passes data down, so the chart, the figures and
 * the table can never disagree about how current they are.
 */
export default class PeHome extends NavigationMixin(LightningElement) {
    orgStats = {};
    posture = null;
    postureLoading = true;
    postureError = false;
    showAllLog = false;
    logPage = { ...EMPTY_PAGE };

    statsLoading = true;
    logLoading = true;
    refreshing = false;
    lastRefreshed;
    breakdown = 'inspectors';

    connectedCallback() {
        this.loadStats();
        this.loadLog();
        this.loadPosture();
    }

    async loadStats(force = false) {
        this.statsLoading = true;
        try {
            const call = force ? refreshOrgStats : getOrgStats;
            this.orgStats = (await call()) ?? {};
        } catch {
            /* Supporting detail, not the point of the page: a failure empties
               the strip and leaves the audit trail intact. */
            this.orgStats = {};
        } finally {
            this.statsLoading = false;
        }
    }

    async loadPosture(force = false) {
        this.postureLoading = true;
        this.postureError = false;
        try {
            this.posture = (await (force ? refreshPosture : getPosture)()) ?? null;
        } catch {
            this.posture = null;
            this.postureError = true;
        } finally {
            this.postureLoading = false;
        }
    }

    async loadLog() {
        this.logLoading = true;
        try {
            this.logPage =
                (await getRecentInspections({
                    inspectorId: null,
                    subjectId: null,
                    rowLimit: ROW_LIMIT
                })) ?? { ...EMPTY_PAGE };
        } catch {
            this.logPage = {
                ...EMPTY_PAGE,
                notice: 'Inspection history could not be loaded. Try refreshing.'
            };
        } finally {
            this.logLoading = false;
            this.lastRefreshed = new Date();
        }
    }

    async handleRefresh() {
        if (this.refreshing) return;
        this.refreshing = true;
        try {
            await Promise.all([
                this.loadPosture(true),
                this.loadLog(),
                this.loadStats(true)
            ]);
        } finally {
            this.refreshing = false;
        }
    }

    handleBreakdown(event) {
        this.breakdown = event.currentTarget.dataset.view;
    }

    handleToggleLog() {
        this.showAllLog = !this.showAllLog;
    }

    get logToggleLabel() {
        return this.showAllLog ? 'Show less' : 'View all';
    }

    get displayedLogRows() {
        return this.showAllLog ? this.logRows : this.logRows.slice(0, 5);
    }

    get hasMoreLogRows() {
        return this.logRows.length > 5;
    }

    get activeUsersValue() {
        const v = this.orgStats?.activeUsers;
        return v === null || v === undefined ? '—' : v.toLocaleString();
    }

    get permissionSetsValue() {
        const v = this.orgStats?.permissionSets;
        return v === null || v === undefined ? '—' : v.toLocaleString();
    }

    get inspectionsValue() {
        return this.logLoading && !this.lastRefreshed ? '—' : this.windowTotal.toLocaleString();
    }

    get inspectionDelta() {
        const d = this.deltaChip(this.windowTotal, this.logPage?.priorWindowTotal ?? 0);
        return d ? d.text : 'No change';
    }

    get licenseHeadline() {
        return this.postureLoading ? '—' : (this.licences ? `${this.licences.used} / ${this.licences.total}` : '—');
    }

    get attentionRows() {
        const order = { alert: 0, watch: 1, ok: 2 };
        return [...this.postureSignals].sort((a,b) => (order[a.severity] ?? 3) - (order[b.severity] ?? 3)).map(s => ({
            key: s.key,
            label: s.label,
            value: s.value === null || s.value === undefined ? '—' : s.value.toLocaleString(),
            severityLabel: s.value === null || s.value === undefined ? 'Unavailable' : s.severity === 'alert' ? 'Attention' : s.severity === 'watch' ? 'Review' : 'Clear',
            tone: s.value === null || s.value === undefined ? 'signal-pill unknown' : `signal-pill ${s.severity}`,
            remedy: s.remedy
        }));
    }

    get overviewRows() {
        const defs = [
            ['profiles', 'Profiles'], ['permissionSetGroups','Permission set groups'],
            ['reachableApps','Reachable apps'], ['objectsWithAccess','Objects with access']
        ];
        return defs.filter(([key]) => this.orgStats?.[key] !== null && this.orgStats?.[key] !== undefined)
            .map(([key,label]) => ({ key, label, value:this.orgStats[key].toLocaleString() }));
    }

    get hasOverviewRows() { return this.overviewRows.length > 0; }

    /* ----------------------------- navigation ----------------------------- */

    handleOpenExplorer() {
        this.navigate(TAB.EXPLORER);
    }
    handleOpenLicenses() {
        this.navigate(TAB.LICENSES);
    }
    handleOpenGuide() {
        this.navigate(TAB.GUIDE);
    }

    /* NavigationMixin throws outside a Lightning container — App Builder
       previews among them. The href fallback keeps the links working there. */
    navigate(apiName) {
        try {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName }
            });
        } catch {
            window.location.assign(`/lightning/n/${apiName}`);
        }
    }

    /* ------------------------------- posture ------------------------------- */

    get postureSignals() {
        return this.posture?.signals ?? [];
    }

    get hasPosture() {
        return this.postureSignals.length > 0;
    }

    /** Headline for the posture row: how many signals actually need action. */
    get attentionCount() {
        return this.postureSignals.filter((s) => s.severity === 'alert').length;
    }

    get postureSummary() {
        if (!this.hasPosture) {
            return 'Posture signals are unavailable.';
        }
        const alerts = this.attentionCount;
        const watch = this.postureSignals.filter((s) => s.severity === 'watch').length;

        if (alerts === 0 && watch === 0) {
            return 'Nothing needs attention right now.';
        }
        const parts = [];
        if (alerts) parts.push(`${alerts} needing attention`);
        if (watch) parts.push(`${watch} worth reviewing`);
        return parts.join(', ');
    }

    get postureSummaryClass() {
        return this.attentionCount > 0 ? 'summary summary-alert' : 'summary';
    }

    get licences() {
        const l = this.posture?.licences;
        if (!l || !l.total) return null;

        const pct = Math.round((l.used / l.total) * 100);
        return {
            used: l.used.toLocaleString(),
            total: l.total.toLocaleString(),
            free: l.free.toLocaleString(),
            pct: `${pct}%`,
            barStyle: `width:${Math.min(100, Math.max(2, pct))}%`,
            /* Seat pressure is one of the few places here with a real
               denominator, so a threshold is honest rather than invented. */
            barClass: pct >= 90 ? 'lic_fill lic_fill-tight' : 'lic_fill',
            unlimitedNote:
                l.unlimitedCount > 0
                    ? `${l.unlimitedCount} unlimited licence${
                          l.unlimitedCount === 1 ? '' : 's'
                      } excluded`
                    : null
        };
    }

    /* -------------------------------- KPIs -------------------------------- */

    get windowTotal() {
        return this.logPage?.windowTotal ?? 0;
    }

    get kpis() {
        const prior = this.logPage?.priorWindowTotal ?? 0;
        const peak = Math.max(0, ...this.activity.map((d) => d.total ?? 0));

        return [
            {
                key: 'inspections',
                label: 'Inspections',
                value: this.windowTotal.toLocaleString(),
                delta: this.deltaChip(this.windowTotal, prior),
                foot: `${prior.toLocaleString()} in the previous 14 days`
            },
            {
                key: 'inspectors',
                label: 'Inspectors',
                value: (this.logPage?.distinctInspectors ?? 0).toLocaleString(),
                delta: null,
                foot: 'People who ran an inspection'
            },
            {
                key: 'subjects',
                label: 'Users inspected',
                value: (this.logPage?.distinctSubjects ?? 0).toLocaleString(),
                delta: null,
                foot: `Busiest day: ${peak.toLocaleString()}`
            }
        ];
    }

    /** Direction against the preceding fortnight. The percentage is withheld
     *  when the prior window was empty — "up 100%" from zero says nothing. */
    deltaChip(now, before) {
        if (!before) {
            return now > 0 ? { text: 'new', className: 'chip chip-flat' } : null;
        }
        const diff = now - before;
        if (diff === 0) {
            return { text: 'level', className: 'chip chip-flat' };
        }
        const pct = Math.round((Math.abs(diff) / before) * 100);
        return {
            text: `${diff > 0 ? '+' : '-'}${pct}%`,
            className: diff > 0 ? 'chip chip-up' : 'chip chip-down'
        };
    }

    /* ------------------------------ activity ------------------------------ */

    get activity() {
        return this.logPage?.activity ?? [];
    }

    get hasActivity() {
        return this.activity.length > 0 && this.windowTotal > 0;
    }

    get showTruncationNote() {
        return this.logPage?.activityTruncated === true;
    }

    /* ----------------------------- breakdown ----------------------------- */

    get showingInspectors() {
        return this.breakdown === 'inspectors';
    }

    get inspectorsTabClass() {
        return this.showingInspectors ? 'seg is-on' : 'seg';
    }

    get actionsTabClass() {
        return this.showingInspectors ? 'seg' : 'seg is-on';
    }

    get breakdownRows() {
        return this.showingInspectors ? this.inspectorRows : this.actionRows;
    }

    get hasBreakdown() {
        return this.breakdownRows.length > 0;
    }

    get inspectorRows() {
        const list = this.logPage?.topInspectors ?? [];
        if (!list.length) return [];

        const peak = Math.max(...list.map((i) => i.total ?? 0), 1);
        return list.map((i) => {
            const name = i.inspectorName ?? 'Unknown user';
            const total = i.total ?? 0;
            return {
                key: i.inspectorId ?? name,
                name,
                initials: this.initials(name),
                showInitials: true,
                total: total.toLocaleString(),
                share: `${Math.round((total / this.safeWindowTotal) * 100)}%`,
                /* Width relative to the busiest row, so bars compare entries
                   against each other rather than an invisible scale. */
                barStyle: `width:${Math.max(4, Math.round((total / peak) * 100))}%`
            };
        });
    }

    get actionRows() {
        const mix = this.logPage?.actionMix ?? [];
        if (!mix.length) return [];

        const peak = Math.max(...mix.map((a) => a.total ?? 0), 1);
        return mix.map((a) => {
            const total = a.total ?? 0;
            return {
                key: a.action,
                name: ACTION_LABELS[a.action] ?? a.action,
                initials: '',
                showInitials: false,
                total: total.toLocaleString(),
                share: `${Math.round((total / this.safeWindowTotal) * 100)}%`,
                barStyle: `width:${Math.max(4, Math.round((total / peak) * 100))}%`
            };
        });
    }

    get safeWindowTotal() {
        return this.windowTotal || 1;
    }

    initials(name) {
        const parts = String(name).trim().split(/\s+/).filter(Boolean);
        if (!parts.length) return '?';
        if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
        return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }

    /* ------------------------------- other ------------------------------- */

    get logRows() {
        return this.logPage?.rows ?? [];
    }

    get hasStats() {
        return Object.values(this.orgStats ?? {}).some(
            (v) => v !== null && v !== undefined
        );
    }

    get logNotice() {
        return this.logPage?.notice || 'No inspection records yet.';
    }

    get showLogNotice() {
        return !this.logLoading && !this.logRows.length;
    }

    get lastRefreshedDisplay() {
        if (!this.lastRefreshed) return null;
        return this.lastRefreshed.toLocaleTimeString(undefined, {
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    get refreshLabel() {
        return this.refreshing ? 'Refreshing' : 'Refresh';
    }
}
