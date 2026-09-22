import { LightningElement, api } from 'lwc';
import { sourceKindLabel, sourceUrl } from 'c/peUtils';

/**
 * "Granted by" pill. One source shown inline; the rest behind a counter,
 * because a permission granted by six sets should not push the row to two
 * lines — but the admin still needs to know all six before revoking one.
 *
 * Every source that has a Setup page gets an explicit, labelled action —
 * "Open permission set", not a name that happens to be clickable. An admin
 * scanning 245 objects should not have to hover things to discover which of
 * them go somewhere.
 */

/**
 * The noun for the action label. Deliberately not `sourceKindLabel`: that
 * returns "Muted by" for the muting kind, which reads as nonsense in
 * "Open muted by". Muting sets have no page of their own, so the action opens
 * the group that contains them, and the label has to say so.
 */
const OPEN_NOUN = {
    profile: 'profile',
    permset: 'permission set',
    group: 'group',
    muting: 'group'
};

/** Why an action is absent. Shown in place of the button, never left blank. */
const NO_LINK_NOTE = {
    muting: 'No Setup page',
    default: 'Not readable'
};

export default class PeSourceChip extends LightningElement {
    @api sources = [];
    expanded = false;

    /**
     * Decorated once per render pass and reused by both the inline chip and the
     * expanded list, so the two can never disagree about what is actionable.
     *
     * The key carries kind and index, not just parentId: a permission set that
     * both grants and mutes appears twice in this list, and a duplicate key
     * makes LWC reuse the wrong element.
     */
    get decorated() {
        return (this.sources ?? []).map((s, i) => {
            const url = sourceUrl(s);
            const noun = OPEN_NOUN[s.kind] ?? 'record';

            return {
                ...s,
                key: `${s.parentId}-${s.kind}-${i}`,
                kindLabel: sourceKindLabel(s.kind),
                url,
                linked: !!url,

                // Visible button text. Short enough for a dense row, specific
                // enough to be worth reading.
                openLabel: `Open ${noun}`,

                // The screen-reader version names the actual record, because
                // twelve buttons all reading "Open permission set" are useless
                // in a rotor list.
                openAria: `Open ${noun} ${s.label} in Setup, opens in a new tab`,

                noLinkNote: NO_LINK_NOTE[s.kind] ?? NO_LINK_NOTE.default,
                title: this.titleFor(s, !!url)
            };
        });
    }

    get hasSources()   { return this.decorated.length > 0; }
    get primary()      { return this.decorated[0]; }
    get rest()         { return this.decorated; }
    get hasOverflow()  { return this.decorated.length > 1; }
    get overflowCount(){ return this.decorated.length - 1; }
    get expandedStr()  { return String(this.expanded); }

    get primaryKind()  { return this.primary?.kindLabel; }
    get primaryLinked(){ return this.primary?.linked === true; }
    get primaryTitle() { return this.primary?.title ?? ''; }
    get primaryOpenLabel() { return this.primary?.openLabel; }
    get primaryOpenAria()  { return this.primary?.openAria; }
    get primaryUrl()   { return this.primary?.url; }

    get primaryClass() {
        const base = 'chip';
        const kind = this.primary?.kind ?? 'permset';
        if (kind === 'muting') return `${base} chip_muting`;
        if (this.primary?.isOutdatedGroup) return `${base} chip_stale`;
        return `${base} chip_${kind}`;
    }

    /**
     * The tooltip does double duty as the explanation for why a source has no
     * action — an admin who cannot click something deserves to be told why
     * rather than left wondering whether the UI is broken.
     */
    titleFor(s, linked) {
        const kind = sourceKindLabel(s.kind);
        const via = s.groupLabel ? ` via ${s.groupLabel}` : '';
        const stale = s.isOutdatedGroup ? ' — group is still recalculating' : '';
        const base = `${kind}: ${s.label}${via}${stale}`;

        if (linked) return base;
        if (s.kind === 'muting') {
            return `${base} — muting permission sets have no Setup page of their own`;
        }
        return `${base} — this definition is not readable, so it cannot be opened in Setup`;
    }

    toggle() {
        this.expanded = !this.expanded;
    }
}
