import { LightningElement, api } from 'lwc';
import { SEARCH_DEBOUNCE_MS, SEARCH_MIN_CHARS } from 'c/peUtils';

export default class PeSearchInput extends LightningElement {
    @api placeholder = 'Search';
    @api ariaLabel = 'Search';
    @api value = '';
    @api minChars = SEARCH_MIN_CHARS;
    @api debounce = SEARCH_DEBOUNCE_MS;

    _draft = '';
    _timer;

    get hasValue() { return (this._draft ?? '').length > 0; }

    get showMinHint() {
        const len = (this._draft ?? '').length;
        return len > 0 && len < this.minChars;
    }

    get remaining() { return this.minChars - (this._draft ?? '').length; }

    handleInput(event) {
        this._draft = event.target.value;
        clearTimeout(this._timer);
        const term = this._draft;

        // Below the minimum, emit an empty term so the column returns to browse
        // rather than sitting on a stale result set.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._timer = setTimeout(() => {
            this.dispatchEvent(new CustomEvent('search', {
                detail: { term: term.length >= this.minChars ? term : '' }
            }));
        }, this.debounce);
    }

    handleClear() {
        clearTimeout(this._timer);
        this._draft = '';
        this.dispatchEvent(new CustomEvent('search', { detail: { term: '' } }));
    }
}