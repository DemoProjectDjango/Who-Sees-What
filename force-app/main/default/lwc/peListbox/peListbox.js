import { LightningElement, api } from 'lwc';

/**
 * Generic keyboard-navigable list used by both columns and the modal rail.
 *
 * Column browsers are keyboard-hostile by default, and writing the keyboard
 * model once here is the only way it stays consistent across three lists.
 * Arrow keys move within the list, Tab leaves it, and typeahead jumps — the
 * behaviour an admin already expects from Setup.
 */
export default class PeListbox extends LightningElement {
    /**
     * Row shape — the consumer formats, this component renders:
     *   { id, label, secondary, meta, badge,
     *     showCrud, canRead, canCreate, canEdit, canDelete, viewAll, modifyAll,
     *     sources }
     *
     * A named slot cannot repeat per row in LWC, so rendering lives here and
     * consumers pass display-ready fields. That also keeps the three lists
     * visually identical without three copies of the markup.
     */
    @api items = [];
    @api selectedId;
    @api ariaLabel = 'Options';
    @api idPrefix = 'opt';

    activeIndex = 0;
    _typeahead = '';
    _typeaheadTimer;

    get decorated() {
        return (this.items ?? []).map((item, index) => {
            const selected = item.id === this.selectedId;
            const active = index === this.activeIndex;
            return {
                ...item,
                domId: `${this.idPrefix}-${index}`,
                selectedStr: String(selected),
                rowClass: [
                    'row',
                    selected ? 'row_selected pe-spine' : '',
                    active ? 'row_active' : ''
                ].filter(Boolean).join(' ')
            };
        });
    }

    get activeDescendantId() {
        return `${this.idPrefix}-${this.activeIndex}`;
    }

    handleClick(event) {
        const id = event.currentTarget.dataset.id;
        const index = this.items.findIndex((i) => i.id === id);
        if (index >= 0) {
            this.activeIndex = index;
        }
        this.select(id);
    }

    handleKeyDown(event) {
        const last = (this.items?.length ?? 0) - 1;
        if (last < 0) {
            return;
        }

        switch (event.key) {
            case 'ArrowDown':
                event.preventDefault();
                this.activeIndex = Math.min(this.activeIndex + 1, last);
                this.scrollActiveIntoView();
                break;
            case 'ArrowUp':
                event.preventDefault();
                this.activeIndex = Math.max(this.activeIndex - 1, 0);
                this.scrollActiveIntoView();
                break;
            case 'Home':
                event.preventDefault();
                this.activeIndex = 0;
                this.scrollActiveIntoView();
                break;
            case 'End':
                event.preventDefault();
                this.activeIndex = last;
                this.scrollActiveIntoView();
                break;
            case 'Enter':
            case ' ':
                event.preventDefault();
                this.select(this.items[this.activeIndex].id);
                break;
            default:
                if (event.key.length === 1 && !event.metaKey && !event.ctrlKey) {
                    this.handleTypeahead(event.key);
                }
        }
    }

    handleTypeahead(char) {
        clearTimeout(this._typeaheadTimer);
        this._typeahead += char.toLowerCase();
        const match = this.items.findIndex(
            (i) => (i.label ?? '').toLowerCase().startsWith(this._typeahead)
        );
        if (match >= 0) {
            this.activeIndex = match;
            this.scrollActiveIntoView();
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._typeaheadTimer = setTimeout(() => { this._typeahead = ''; }, 600);
    }

    select(id) {
        this.dispatchEvent(new CustomEvent('rowselect', { detail: { id } }));
    }

    scrollActiveIntoView() {
        const el = this.template.querySelector(`[id="${this.activeDescendantId}"]`);
        if (el) {
            el.scrollIntoView({ block: 'nearest' });
        }
    }

    /** Lets the parent restore focus after the modal closes. */
    @api
    focusRow(id) {
        const index = this.items.findIndex((i) => i.id === id);
        if (index >= 0) {
            this.activeIndex = index;
        }
        this.template.querySelector('.listbox')?.focus();
    }
}