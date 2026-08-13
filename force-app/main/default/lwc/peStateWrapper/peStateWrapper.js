import { LightningElement, api } from 'lwc';
import { STATE, errorHeadline, asOf } from 'c/peUtils';

/**
 * Every column and panel wraps its content in this, so the six required states
 * are written once instead of reinvented per panel. Empty screens are an
 * invitation to act, not a mood — hence a headline plus a next step, never a
 * shrug.
 */
export default class PeStateWrapper extends LightningElement {
    @api state = STATE.EMPTY;
    @api error;                     // parsed ErrorInfo
    @api emptyHeadline = 'Nothing selected yet';
    @api emptyDetail = '';
    @api skeletonRows = 6;
    @api staleSince;

    get showLoading()  { return this.state === STATE.LOADING; }
    get showError()    { return this.state === STATE.ERROR && this.error; }
    get showEmpty()    { return this.state === STATE.EMPTY || this.state === STATE.LOADED_EMPTY; }
    get showStale()    { return this.state === STATE.LOADED && this.staleSince; }

    get errorHeadline() { return errorHeadline(this.error?.cause); }
    get staleAt()       { return asOf(this.staleSince); }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}