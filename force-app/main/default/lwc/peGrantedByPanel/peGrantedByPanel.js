import { LightningElement, api } from 'lwc';
import { openInNewTab } from 'c/peUtils';

const KIND_LABEL = {
    profile: 'Profile',
    permset: 'Permission Set',
    group: 'Permission Set Group',
    muting: 'Muting Permission Set'
};

/**
 * Condensed "who granted this" sidebar card: one row per distinct source
 * touching the selected object, always visible rather than behind a button.
 *
 * Built entirely from the ObjectDetail the WHAT column already holds — same
 * source data as the "Explain this access" trace modal (peAccessTrace), just
 * deduplicated to source identity rather than broken out per permission. For
 * the full grant-by-grant chain (including the +/− muting math), that modal
 * is still the tool for the job; this card is the one-glance version of it.
 */
export default class PeGrantedByPanel extends LightningElement {
    @api detail;

    get grants() { return this.detail?.objectPermissions ?? []; }

    get sources() {
        const bySource = new Map();

        this.grants.forEach((g) => {
            (g.sources ?? []).forEach((s) => {
                const kind = s.kind ?? 'permset';
                const key = `${kind}|${s.parentId ?? ''}|${s.label ?? ''}`;
                if (!bySource.has(key)) {
                    bySource.set(key, {
                        key,
                        kind,
                        kindLabel: KIND_LABEL[kind] ?? 'Source',
                        label: s.label ?? 'Unnamed',
                        outdated: s.isOutdatedGroup === true,
                        linkId: s.linkable === false ? null : s.linkId,
                        url: null
                    });
                }
            });
        });

        return [...bySource.values()]
            .filter((s) => s.kind !== 'muting')
            .map((s) => ({ ...s, url: s.linkId ? this.setupUrl(s.kind, s.linkId) : null }))
            .sort((a, b) => a.kindLabel.localeCompare(b.kindLabel));
    }

    get mutingSources() {
        const bySource = new Map();
        this.grants.forEach((g) => {
            (g.sources ?? []).forEach((s) => {
                if (s.kind !== 'muting') return;
                const key = `${s.parentId ?? ''}|${s.label ?? ''}`;
                if (!bySource.has(key)) bySource.set(key, s.label ?? 'A muting permission set');
            });
        });
        return [...bySource.values()];
    }

    get hasMuting() { return this.mutingSources.length > 0; }
    get mutingText() {
        return this.mutingSources.length === 1
            ? `${this.mutingSources[0]} reduces this user's access below what's listed here.`
            : `${this.mutingSources.length} muting permission sets reduce this user's access below what's listed here.`;
    }

    get hasSources() { return this.sources.length > 0; }

    setupUrl(kind, id) {
        switch (kind) {
            case 'profile': return `/lightning/setup/EnhancedProfiles/page?address=%2F${id}`;
            case 'permset': return `/lightning/setup/PermSets/page?address=%2F${id}`;
            case 'group':   return `/lightning/setup/PermSetGroups/page?address=%2F${id}`;
            default:        return null;
        }
    }

    handleOpen(event) {
        openInNewTab(event.currentTarget.dataset.url);
    }
}
