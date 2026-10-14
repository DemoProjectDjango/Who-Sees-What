import { LightningElement, api } from 'lwc';

const SEVERITY_ORDER = { alert: 0, watch: 1, ok: 2 };

/**
 * The actionable signals, worst first.
 *
 * Sorting by severity rather than a fixed order means the thing that needs
 * attention is always in the top-left, where the eye lands. A fixed order makes
 * an administrator read all five every time to find out whether any of them
 * matters.
 */
export default class PePostureGrid extends LightningElement {
    _signals = [];

    @api
    get signals() {
        return this._signals;
    }
    set signals(value) {
        this._signals = Array.isArray(value) ? value : [];
    }

    get rows() {
        return [...this._signals]
            .sort(
                (a, b) =>
                    (SEVERITY_ORDER[a.severity] ?? 3) - (SEVERITY_ORDER[b.severity] ?? 3)
            )
            .map((s) => {
                /* null is not zero. A failed query rendered as 0 on a risk panel
                   reads as an all-clear, which is the most dangerous thing this
                   component could do. */
                const unavailable = s.value === null || s.value === undefined;
                const severity = unavailable ? 'unknown' : s.severity ?? 'ok';

                return {
                    key: s.key,
                    label: s.label,
                    remedy: s.remedy,
                    unavailable,
                    value: unavailable ? '—' : s.value.toLocaleString(),
                    outOf:
                        !unavailable && s.outOf
                            ? `of ${s.outOf.toLocaleString()}`
                            : null,
                    share:
                        !unavailable && s.outOf
                            ? `${Math.round((s.value / s.outOf) * 100)}%`
                            : null,
                    barStyle:
                        !unavailable && s.outOf
                            ? `width:${Math.min(
                                  100,
                                  Math.max(2, Math.round((s.value / s.outOf) * 100))
                              )}%`
                            : null,
                    cardClass: `tile tile-${severity}`,
                    dotClass: `dot dot-${severity}`,
                    statusText: this.statusText(severity)
                };
            });
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    statusText(severity) {
        switch (severity) {
            case 'alert':
                return 'Needs attention';
            case 'watch':
                return 'Worth reviewing';
            case 'unknown':
                return 'Unavailable';
            default:
                return 'Clear';
        }
    }
}
