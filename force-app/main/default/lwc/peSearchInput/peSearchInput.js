import { LightningElement, api } from 'lwc';

export default class PeSearchInput extends LightningElement {
    @api placeholder = 'Search';
    @api ariaLabel = 'Search';
    @api minChars = 1;
    @api debounce = 250;

    _draft = '';
    _timer;

    @api
    get value() {
        return this._draft;
    }
    set value(v) {
        const next = v ?? '';
        if (this._draft === next) return;
        this._draft = next;
        const input = this.template?.querySelector('input');
        if (input && input.value !== next) {
            input.value = next;
        }
    }

    get clearClass() {
        return (this._draft && this._draft.length > 0) ? 'clear visible' : 'clear';
    }

    handleInput(event) {
        this._draft = event.target.value ?? '';
        clearTimeout(this._timer);
        const term = this._draft.trim();

        // If user completely cleared the input, dispatch immediately to restore browse
        if (!term) {
            this.dispatchEvent(new CustomEvent('search', { detail: { term: '' } }));
            return;
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation -- Intentional UI timing operation.
        this._timer = setTimeout(() => {
            this.dispatchEvent(new CustomEvent('search', {
                detail: { term: term.length >= this.minChars ? term : '' }
            }));
        }, this.debounce);
    }

    handleKeyDown(event) {
        if (event.key === 'Enter') {
            clearTimeout(this._timer);
            const term = (this._draft ?? '').trim();
            this.dispatchEvent(new CustomEvent('search', {
                detail: { term: term.length >= this.minChars ? term : '' }
            }));
        }
    }

    handleClear(event) {
        event?.preventDefault();
        event?.stopPropagation();
        clearTimeout(this._timer);
        this._draft = '';
        const input = this.template?.querySelector('input');
        if (input) {
            input.value = '';
            input.focus();
        }
        this.dispatchEvent(new CustomEvent('search', { detail: { term: '' } }));
    }

    @api
    clear() {
        clearTimeout(this._timer);
        this._draft = '';
        const input = this.template?.querySelector('input');
        if (input) {
            input.value = '';
        }
    }
}