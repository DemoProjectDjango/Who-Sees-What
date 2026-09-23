import { LightningElement, api } from 'lwc';
import { relativeTime } from 'c/peUtils';

export default class PeUserSummaryHeader extends LightningElement {
    @api summary = {};

    copied = false;
    _copyTimer;

    get profileText()  { return this.summary.profileName ?? '—'; }
    get roleText()     { return this.summary.roleName ?? 'No role'; }
    get licenseText()  { return this.summary.licenseName ?? '—'; }
    get lastLoginText(){ return relativeTime(this.summary.lastLogin); }
    get emailText()     { return this.summary.email ?? null; }
    get departmentText(){ return this.summary.department ?? null; }
    get managerText()   { return this.summary.managerName ?? null; }
    get hasEmail()      { return !!this.emailText; }
    get hasDepartment() { return !!this.departmentText; }
    get hasManager()    { return !!this.managerText; }

    get copyTitle() {
        return this.copied ? 'Copied to clipboard!' : 'Copy email address';
    }

    async handleCopyEmail(event) {
        event.stopPropagation();
        if (!this.emailText) {
            return;
        }
        try {
            if (navigator?.clipboard?.writeText) {
                await navigator.clipboard.writeText(this.emailText);
            } else {
                const ta = document.createElement('textarea');
                ta.value = this.emailText;
                ta.style.position = 'fixed';
                ta.style.opacity = '0';
                document.body.appendChild(ta);
                ta.select();
                document.execCommand('copy');
                document.body.removeChild(ta);
            }
            this.copied = true;
            clearTimeout(this._copyTimer);
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._copyTimer = setTimeout(() => {
                this.copied = false;
            }, 2000);
        } catch (e) {
            console.warn('Copy email failed', e);
        }
    }

    get initials() {
        const name = (this.summary.name ?? '').trim();
        if (!name) {
            return '?';
        }
        const parts = name.split(/\s+/);
        const first = parts[0]?.[0] ?? '';
        const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
        return (first + last).toUpperCase() || '?';
    }

    get statusLabel() { return this.summary.isFrozen ? 'Frozen' : 'Active'; }
    get statusClass() {
        return this.summary.isFrozen ? 'status status_frozen' : 'status status_active';
    }

    get permSetCount() { return this.summary.permSetCount ?? 0; }
    get groupCount()   { return this.summary.permSetGroupCount ?? 0; }

    /**
     * The buttons appear only where there is something behind them. A "View"
     * that opens an empty list is a worse answer than no button at all —
     * the number already said zero.
     */
    get hasPermSets() { return this.permSetCount > 0; }
    get hasGroups()   { return this.groupCount > 0; }

    get permSetText() {
        const n = this.permSetCount;
        return n === 1 ? '1 assigned' : `${n} assigned`;
    }

    get groupText() {
        const n = this.groupCount;
        return n === 1 ? '1 assigned' : `${n} assigned`;
    }

    /* The visible labels are short because the row is dense; the accessible
       names carry the context a screen reader has no column header for. */
    get loginHistoryAriaLabel() {
        return `View login history for ${this.summary.name ?? 'this user'}`;
    }

    get permSetAriaLabel() {
        const n = this.permSetCount;
        return `View the ${n} permission set${n === 1 ? '' : 's'} assigned to ${this.summary.name ?? 'this user'}`;
    }

    get groupAriaLabel() {
        const n = this.groupCount;
        return `View the ${n} permission set group${n === 1 ? '' : 's'} assigned to ${this.summary.name ?? 'this user'}`;
    }

    get mutingText() {
        const n = this.summary.mutingSetCount ?? 0;
        return n === 1 ? '1 muting permission set' : `${n} muting permission sets`;
    }

    get unreadableText() {
        const n = this.summary.unreadableCount ?? 0;
        return n === 1
            ? '1 assigned permission set'
            : `${n} assigned permission sets`;
    }

    get hasOutdatedGroups() {
        return (this.summary.outdatedGroups ?? []).length > 0;
    }

    get outdatedText() {
        const groups = this.summary.outdatedGroups ?? [];
        return groups.length === 1
            ? `Permission set group ${groups[0]} is`
            : `${groups.length} permission set groups are`;
    }

    /* ------------------------------- events ------------------------------- */

    /**
     * The header owns no data beyond its summary, so it asks rather than
     * fetches. The root component holds every request and every cache.
     */
    handleLoginHistory() {
        this.dispatchEvent(new CustomEvent('openloginhistory'));
    }

    handlePermSets() {
        this.dispatchEvent(new CustomEvent('openpermsets'));
    }

    handleGroups() {
        this.dispatchEvent(new CustomEvent('opengroups'));
    }
}
