import { LightningElement, api } from 'lwc';

/**
 * C R U D chips. Filled or hollow, and the letter is always present — no
 * colour-only encoding, because an admin auditing 300 objects will be scanning
 * these at speed and a colourblind admin must scan them just as fast.
 */
export default class PeCrudChips extends LightningElement {
    @api canRead = false;
    @api canCreate = false;
    @api canEdit = false;
    @api canDelete = false;
    @api viewAll = false;
    @api modifyAll = false;

    get chips() {
        return [
            { key: 'c', letter: 'C', on: this.canCreate, name: 'Create' },
            { key: 'r', letter: 'R', on: this.canRead, name: 'Read' },
            { key: 'u', letter: 'U', on: this.canEdit, name: 'Edit' },
            { key: 'd', letter: 'D', on: this.canDelete, name: 'Delete' }
        ].map((c) => ({
            ...c,
            class: c.on ? 'chip chip_on' : 'chip chip_off',
            title: `${c.name}: ${c.on ? 'granted' : 'no access'}`
        }));
    }

    get showAllMarker() {
        return this.viewAll || this.modifyAll;
    }

    get allMarkerText() {
        return this.modifyAll ? 'MOD ALL' : 'VIEW ALL';
    }

    get allMarkerTitle() {
        return this.modifyAll
            ? 'Modify All Records — bypasses sharing on every record'
            : 'View All Records — bypasses sharing for read';
    }

    get ariaLabel() {
        const on = this.chips.filter((c) => c.on).map((c) => c.name);
        const base = on.length ? `Granted: ${on.join(', ')}` : 'No object access';
        if (this.modifyAll) {
            return `${base}. Modify All Records.`;
        }
        if (this.viewAll) {
            return `${base}. View All Records.`;
        }
        return base;
    }
}