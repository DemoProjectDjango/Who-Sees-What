import { LightningElement, api } from 'lwc';

export default class PeSkeleton extends LightningElement {
    @api count = 6;
    @api height = 'var(--pe-row-h)';

    get rows() {
        return Array.from({ length: Number(this.count) }, (_, i) => i);
    }

    get lineStyle() {
        return `height:${this.height}`;
    }
}