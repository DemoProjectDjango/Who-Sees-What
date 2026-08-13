import { LightningElement, api } from 'lwc';

/**
 * Explicit "not analysed" disclosure.
 *
 * An empty tab reads as "no access". For a permissions tool that is a confident
 * wrong answer, which is the worst failure mode available. So anything the tool
 * cannot introspect says so, and names what it would need.
 */
export default class PeNotAnalysed extends LightningElement {
    @api headline = 'Not analysed';
    @api detail;
    @api source;

    get hasRecordTypes() {
        return (this.detail?.recordTypes?.length ?? 0) > 0;
    }
}