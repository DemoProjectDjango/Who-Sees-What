import { LightningElement, api } from 'lwc';
import { STATE, tabVisibilityLabel } from 'c/peUtils';

const TABS = [
    { key: 'fields',      label: 'Fields' },
    { key: 'recordtypes', label: 'Record types' },
    { key: 'origin',      label: 'Origin' }
];

/**
 * One object row, expandable in place.
 *
 * The detail fetch is owned by the parent, not this component — with fifty
 * objects in an app, the parent is the only place that can cache across
 * expansions and avoid re-fetching a row the admin already opened.
 */
export default class PeObjectRow extends LightningElement {
    @api row = {};
    @api expanded = false;
    @api detail;
    @api detailState = STATE.EMPTY;
    @api detailError;

    activeTab = 'fields';

    get expandedStr() { return String(this.expanded); }
    get notExpandable() { return this.row.isObjectTab === false; }
    get showNoTabBadge() { return this.row.accessWithoutTab === true; }
    get hasTabSources() { return (this.row.tabSources?.length ?? 0) > 0; }
    get tabVisibilityText() { return tabVisibilityLabel(this.row.tabVisibility); }

    get toggleLabel() {
        return `${this.expanded ? 'Collapse' : 'Expand'} ${this.row.label}`;
    }

    get wrapperClass() {
        return this.expanded ? 'wrapper wrapper_open' : 'wrapper';
    }

    get tabs() {
        const counts = {
            fields: this.detail?.fields?.length,
            recordtypes: null,
            origin: null
        };
        return TABS.map((t) => ({
            ...t,
            label: counts[t.key] ? `${t.label} ${counts[t.key]}` : t.label,
            selectedStr: String(t.key === this.activeTab),
            class: t.key === this.activeTab ? 'tab tab_on' : 'tab'
        }));
    }

    get hasRecordTypes() {
            return (this.detail?.recordTypes?.length ?? 0) > 0;
    }
    /** Decorated here so the template carries no conditionals per row. */
    get recordTypeRows() {
        return (this.detail?.recordTypes ?? []).map((rt) => ({
            ...rt,
            stateText: rt.isMaster ? 'Master' : (rt.isActive ? 'Active' : 'Inactive'),
            stateClass: rt.isActive || rt.isMaster ? 'rt-state' : 'rt-state rt-state_inactive'
        }));
    }

    get loaded() { return this.detailState === STATE.LOADED && this.detail; }
    get showFields()      { return this.loaded && this.activeTab === 'fields'; }
    get showRecordTypes() { return this.activeTab === 'recordtypes'; }

    get showOrigin() {
        return this.loaded && this.activeTab === 'origin';
    }

    /** Decorated here so the template stays free of expressions. */
    get decoratedGrants() {
        return (this.detail?.objectPermissions ?? []).map((g) => ({
            ...g,
            grantedText: g.muted ? 'muted' : (g.granted ? 'granted' : 'no'),
            grantedClass: g.muted ? 'gflag gflag_muted'
                : (g.granted ? 'gflag gflag_on' : 'gflag gflag_off')
        }));
    }

    handleToggle() {
        if (this.notExpandable) return;
        this.dispatchEvent(new CustomEvent('toggle', {
            detail: { apiName: this.row.apiName }
        }));
    }

    handleTab(event) {
        this.activeTab = event.currentTarget.dataset.key;
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry', {
            detail: { apiName: this.row.apiName }
        }));
    }
}