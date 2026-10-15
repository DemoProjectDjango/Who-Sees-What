import { LightningElement, api } from 'lwc';

/**
 * Daily inspection volume as rounded columns.
 *
 * Laid out with CSS flex and percentage heights rather than SVG. The bars are
 * plain elements, so the hover card, the focus ring and the rounded corners are
 * all ordinary CSS — in SVG each of those costs geometry maths, and nothing
 * here needs a path.
 *
 * Every label arrives preformatted from Apex. Nothing in this file parses a
 * date; doing so cost a fortnight of wrongly-labelled columns once already.
 */
export default class PeActivityChart extends LightningElement {
    _days = [];
    hoveredKey;

    @api
    get days() {
        return this._days;
    }
    set days(value) {
        this._days = Array.isArray(value) ? value : [];
    }

    get hasData() {
        return this._days.length > 0;
    }

    /** Peak sets the scale and also decides which column gets the full accent.
     *  Floored at 1 so an all-zero window renders a baseline, not a divide. */
    get peak() {
        return Math.max(1, ...this._days.map((d) => d.total ?? 0));
    }

    get columns() {
        const peak = this.peak;
        const peakIndex = this._days.reduce(
            (best, d, i) => ((d.total ?? 0) > (this._days[best].total ?? 0) ? i : best),
            0
        );

        return this._days.map((d, i) => {
            const total = d.total ?? 0;
            const isPeak = i === peakIndex && total > 0;
            const key = d.label ?? `d${i}`;

            /* A 2% floor keeps quiet days visible. A zero drawn as nothing is
               indistinguishable from a day the query never returned. */
            const pct = total === 0 ? 2 : Math.max(6, Math.round((total / peak) * 100));

            let fill = 'col_bar';
            if (total === 0) fill += ' col_bar-zero';
            else if (isPeak) fill += ' col_bar-peak';
            if (d.isToday) fill += ' col_bar-today';

            return {
                key,
                label: d.label ?? '',
                fullLabel: d.fullLabel ?? d.label ?? '',
                total,
                totalDisplay: total.toLocaleString(),
                barClass: fill,
                barStyle: `height:${pct}%`,
                showCard: this.hoveredKey === key && total > 0,
                columnClass: this.hoveredKey === key ? 'col is-active' : 'col',
                title: `${d.fullLabel ?? d.label ?? ''} — ${total} ${
                    total === 1 ? 'inspection' : 'inspections'
                }`
            };
        });
    }

    handleEnter(event) {
        this.hoveredKey = event.currentTarget.dataset.key;
    }

    handleLeave() {
        this.hoveredKey = undefined;
    }
}
