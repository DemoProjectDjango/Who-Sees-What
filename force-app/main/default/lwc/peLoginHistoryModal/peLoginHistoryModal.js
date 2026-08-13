import { LightningElement, api } from 'lwc';
import { STATE } from 'c/peUtils';

/**
 * Login history table.
 *
 * Three outcomes, three renderings, never collapsed into two: rows, "no
 * sign-ins recorded", and "could not be read". The third is the one that
 * matters — LoginHistory needs a permission this tool does not grant, and an
 * empty table in that case would be a lie about the user rather than a fact
 * about the tool.
 */
export default class PeLoginHistoryModal extends LightningElement {
    @api result = {};
    @api state = STATE.EMPTY;
    @api error;

    get isUnavailable() {
        return !!this.result?.notAvailableReason;
    }

    get rows() {
        return (this.result?.events ?? []).map((e, i) => {
            const failed = e.status && e.status !== 'Success';
            return {
                key: `${e.loginTime ?? 'n'}-${i}`,
                when: this.formatWhen(e.loginTime),
                status: e.status ?? '—',
                loginType: e.loginType ?? '—',
                sourceIp: e.sourceIp ?? '—',
                application: e.application ?? '—',
                client: this.formatClient(e.browser, e.platform),
                rowClass: failed ? 'row row_failed' : 'row',
                statusClass: failed ? 'status status_failed' : 'status'
            };
        });
    }

    /**
     * Absolute, to the minute, in the reader's locale. Relative time is right
     * for "last sign-in" in the header and wrong here — an audit list is read
     * to compare timestamps against something else.
     */
    formatWhen(value) {
        if (!value) return '—';
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return '—';
        return d.toLocaleString([], {
            year: 'numeric', month: 'short', day: '2-digit',
            hour: '2-digit', minute: '2-digit'
        });
    }

    formatClient(browser, platform) {
        const parts = [browser, platform].filter((p) => p && p !== 'Unknown');
        return parts.length ? parts.join(' · ') : '—';
    }

    get emptyDetail() {
        return this.result?.retentionNote ?? '';
    }

    get footnote() {
        const count = this.result?.events?.length ?? 0;
        const limit = this.result?.appliedLimit ?? 0;
        const retention = this.result?.retentionNote ?? '';

        // "Filled the page" is not proof of more rows, so it is worded as one.
        const scope = this.result?.truncated
            ? `Showing the ${count} most recent sign-ins, which is the maximum this panel requests. There may be more.`
            : `Showing all ${count} sign-in${count === 1 ? '' : 's'} found${limit ? '' : ''}.`;

        return `${scope} ${retention}`.trim();
    }

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }
}
