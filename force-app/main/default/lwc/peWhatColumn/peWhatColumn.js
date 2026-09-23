import { LightningElement, api } from 'lwc';
import { STATE } from 'c/peUtils';

const VIEWS = [
    { key: 'fields', label: 'Fields' },
    { key: 'recordtypes', label: 'Record types' }
];

/**
 * The WHAT column: one object, in full.
 *
 * This is where the modal went. Fields used to live inside an expanded row
 * inside a table inside a modal, three levels of nesting deep, which is why the
 * table never had room to breathe. Given its own column it gets the width the
 * GRANTED BY chips always needed.
 */
export default class PeWhatColumn extends LightningElement {
    @api objectLabel;
    @api objectApiName;
    @api tabVisibility;
    @api detail;
    @api state = STATE.EMPTY;
    @api error;

    activeView = 'fields';

    get loaded() { return this.state === STATE.LOADED && !!this.detail; }
    get hasGrants() { return (this.detail?.objectPermissions?.length ?? 0) > 0; }
    get showFields() { return this.loaded && this.activeView === 'fields'; }
    get showRecordTypes() { return this.activeView === 'recordtypes'; }
    get hasRecordTypes() { return (this.detail?.recordTypes?.length ?? 0) > 0; }

    /** Nothing to explain until there is a resolved grant list to explain. */
    get explainDisabled() { return !this.hasGrants; }

    /* ---------------------------------------------------------------
     * Overview header: object identity + five glance badges
     * --------------------------------------------------------------- */

    get objectTypeLabel() {
        const api = this.objectApiName ?? '';
        if (api.endsWith('__mdt')) return 'Custom Metadata Type';
        if (api.endsWith('__x')) return 'External Object';
        if (api.endsWith('__c')) return 'Custom Object';
        return 'Standard Object';
    }

    get tabVisibilityLabel() {
        switch (this.tabVisibility) {
            case 'Hidden': return 'Hidden';
            case 'NoTab': return 'No tab';
            case 'DefaultOn':
            case 'DefaultOff': return 'Visible';
            default: return '—';
        }
    }
    get tabVisibilityClass() {
        return this.tabVisibility === 'Hidden' || this.tabVisibility === 'NoTab'
            ? 'bpill bpill_muted' : 'bpill bpill_on';
    }

    /** Read/Create/Edit/Delete only — View All / Modify All are shown in the
        full CRUD strip below, not repeated in this compact badge. */
    get objectAccessLabel() {
        const granted = (this.detail?.objectPermissions ?? [])
            .filter((g) => ['PermissionsRead', 'PermissionsCreate', 'PermissionsEdit', 'PermissionsDelete'].includes(g.name) && g.granted)
            .map((g) => g.label);
        return granted.length ? granted.join(', ') : 'No access';
    }

    /** Same underlying grants as Object Access — Salesforce doesn't expose
        page-layout quick-action metadata without a Metadata API callout, so
        this reads as the closest honest proxy: can this user open and edit
        a record at all. */
    get recordActionsLabel() {
        const granted = (this.detail?.objectPermissions ?? [])
            .filter((g) => ['PermissionsRead', 'PermissionsEdit'].includes(g.name) && g.granted)
            .map((g) => g.name === 'PermissionsRead' ? 'View' : 'Edit');
        return granted.length ? granted.join(', ') : 'No access';
    }

    get standardFieldsLabel() { return this.fieldAccessLabel(false); }
    get customFieldsLabel() { return this.fieldAccessLabel(true); }

    fieldAccessLabel(custom) {
        const fields = (this.detail?.fields ?? []).filter((f) => (f.apiName ?? '').endsWith('__c') === custom);
        if (!fields.length) return '—';
        const anyEditable = fields.some((f) => f.editable);
        const anyReadable = fields.some((f) => f.readable);
        if (anyEditable) return 'Read, Edit';
        if (anyReadable) return 'Read';
        return 'No access';
    }

    get views() {
        const count = this.detail?.fields?.length;
        return VIEWS.map((v) => ({
            ...v,
            label: v.key === 'fields' && count ? `Fields ${count}` : v.label,
            selectedStr: String(v.key === this.activeView),
            class: v.key === this.activeView ? 'view view_on' : 'view'
        }));
    }

    get recordTypeRows() {
        return (this.detail?.recordTypes ?? []).map((rt) => ({
            ...rt,
            stateText: rt.isMaster ? 'Master' : (rt.isActive ? 'Active' : 'Inactive'),
            stateClass: rt.isActive || rt.isMaster ? 'rt-state' : 'rt-state rt-state_inactive'
        }));
    }

    handleView(event) {
        this.activeView = event.currentTarget.dataset.key;
    }

    handleExplain() {
        this.dispatchEvent(new CustomEvent('explain'));
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}
