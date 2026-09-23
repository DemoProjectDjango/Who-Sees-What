import { LightningElement, api } from 'lwc';
import { openInNewTab } from 'c/peUtils';

/**
 * The access trace: every assignment that touches one object, drawn as
 * contributions, and the effective result underneath.
 *
 * Built entirely from the ObjectDetail the caller already holds. There is no
 * second Apex round trip, deliberately — a trace is one admin action and should
 * write one inspection log row, not two.
 *
 * The one thing this panel exists to show is that muting is SUBTRACTION. A tool
 * that ORs every assignment together reports Delete as granted whenever any set
 * in the stack grants it, and the platform does not agree. So muting sources get
 * their own card, their own sign, and their own colour.
 */

const KIND_ORDER = { profile: 0, permset: 1, group: 2, muting: 3 };

const KIND_LABEL = {
    profile: 'Profile',
    permset: 'Permission set',
    group: 'Permission set group',
    muting: 'Muting permission set'
};

/**
 * Setup deep links. Plain anchors rather than NavigationMixin, so middle-click
 * and cmd-click keep working — an admin comparing four sources opens four tabs.
 */
const SETUP_URL = {
    profile: (id) => `/lightning/setup/EnhancedProfiles/page?address=%2F${id}`,
    permset: (id) => `/lightning/setup/PermSets/page?address=%2F${id}`,
    group: (id) => `/lightning/setup/PermSetGroups/page?address=%2F${id}`,
    muting: (id) => `/lightning/setup/PermSetGroups/page?address=%2F${id}`
};

export default class PeAccessTrace extends LightningElement {
    @api userName;
    @api appLabel;
    @api objectLabel;
    @api objectApiName;
    @api detail;
    @api shareLink;
    @api copied = false;

    get copyLabel() { return this.copied ? 'Link copied' : 'Copy link'; }

    get grants() { return this.detail?.objectPermissions ?? []; }

    get hasChain() { return this.chain.length > 0; }

    /**
     * Invert the shape. The payload is grant -> sources; an admin reads it the
     * other way round, source -> what it contributed, because that is the row
     * they will go and edit in Setup.
     */
    get chain() {
        const bySource = new Map();

        this.grants.forEach((g) => {
            (g.sources ?? []).forEach((s) => {
                const kind = s.kind ?? 'permset';
                const key = `${kind}|${s.parentId ?? ''}|${s.label ?? ''}`;
                if (!bySource.has(key)) {
                    bySource.set(key, {
                        key,
                        kind,
                        label: s.label ?? 'Unnamed',
                        outdated: s.isOutdatedGroup === true,
                        linkId: s.linkable === false ? null : s.linkId,
                        grants: []
                    });
                }
                const cutting = kind === 'muting';
                bySource.get(key).grants.push({
                    key: `${key}|${g.name}`,
                    label: g.label ?? g.name,
                    sign: cutting ? '\u2212' : '+',
                    pillClass: cutting ? 'gpill gpill_cut' : 'gpill gpill_add'
                });
            });
        });

        return [...bySource.values()]
            .sort((a, b) => (KIND_ORDER[a.kind] ?? 9) - (KIND_ORDER[b.kind] ?? 9))
            .map((c) => ({
                ...c,
                kindLabel: KIND_LABEL[c.kind] ?? c.kind,
                kindClass: `kind kind_${c.kind}`,
                cardClass: c.kind === 'muting' ? 'link link_cut' : 'link',
                url: c.linkId && SETUP_URL[c.kind] ? SETUP_URL[c.kind](c.linkId) : null
            }));
    }

    /** Three states, each named in words as well as coloured. */
    get effective() {
        return this.grants.map((g) => {
            let text = `${g.label} \u2014 no`;
            let tone = 'deny';

            if (g.muted) {
                text = `${g.label} \u2014 muted`;
                tone = 'mute';
            } else if (g.granted) {
                text = g.label;
                tone = 'grant';
            }

            return {
                key: g.name,
                text,
                pillClass: `effpill effpill_${tone}`,
                dotClass: `effdot effdot_${tone}`
            };
        });
    }

    get mutedNote() {
        const muted = this.grants.filter((g) => g.muted);
        if (!muted.length) return null;

        const names = muted.map((g) => g.label).join(', ');
        return `${names} ${muted.length === 1 ? 'is' : 'are'} granted somewhere in this stack and removed by a ` +
            'muting permission set. A tool that simply merges assignments would report ' +
            `${muted.length === 1 ? 'it' : 'them'} as granted here \u2014 the platform does not.`;
    }

    get logFacts() {
        return [
            { key: 'subject', k: 'Subject user', v: this.userName ?? '\u2014' },
            { key: 'scope', k: 'Scope', v: `${this.appLabel ?? '\u2014'} \u203a ${this.objectLabel ?? this.objectApiName}` },
            { key: 'action', k: 'Action', v: 'GET_OBJECT_DETAIL' },
            { key: 'when', k: 'Resolved', v: this.resolvedText }
        ];
    }

    get resolvedText() {
        const raw = this.detail?.resolvedAt;
        if (!raw) return 'This session';
        const d = new Date(raw);
        return Number.isNaN(d.getTime()) ? 'This session' : d.toLocaleString();
    }

    handleCopy() {
        this.dispatchEvent(new CustomEvent('copylink'));
    }

    /** A <button>, not an <a>, so Lightning's own navigation shell has
        nothing to intercept — see peUtils/accessLabels.js. */
    handleOpenSetup(event) {
        openInNewTab(event.currentTarget.dataset.url);
    }
}
