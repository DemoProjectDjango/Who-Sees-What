import { LightningElement, api } from 'lwc';

/**
 * Keyset pagination has no total count, so this deliberately shows "showing N"
 * and a page number rather than "page 3 of 87" — a COUNT() on a filtered user
 * query would be paid on every page for a number nobody acts on.
 */
export default class PePaginator extends LightningElement {
    @api shown = 0;
    @api pageNumber = 1;
    @api hasMore = false;
    @api canGoBack = false;
    @api loading = false;
    @api capReached = false;

    get backDisabled() { return !this.canGoBack || this.loading; }
    get nextDisabled() { return !this.hasMore || this.loading; }

    get summary() {
        if (this.loading) {
            return 'Loading…';
        }
        if (!this.shown) {
            return 'No results';
        }
        return `Showing ${this.shown} · page ${this.pageNumber}`;
    }

    handleBack() { this.dispatchEvent(new CustomEvent('back')); }
    handleNext() { this.dispatchEvent(new CustomEvent('next')); }
}