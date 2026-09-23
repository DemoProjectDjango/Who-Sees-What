import { LightningElement, api } from 'lwc';

/**
 * Six org-wide counts across the top of Permission Explorer. Each is
 * independently optional (see PEOrgStatsService) — a card for a count that
 * came back null just doesn't render, rather than showing a fabricated 0
 * that would be indistinguishable from a genuine zero.
 */
export default class PeOrgStatsBar extends LightningElement {
    @api stats = {};
    @api loading = false;

    get cards() {
        const defs = [
            { key: 'activeUsers', label: 'Active Users', value: this.stats.activeUsers },
            { key: 'permissionSets', label: 'Permission Sets', value: this.stats.permissionSets },
            { key: 'permissionSetGroups', label: 'Permission Set Groups', value: this.stats.permissionSetGroups },
            { key: 'profiles', label: 'Profiles', value: this.stats.profiles },
            { key: 'reachableApps', label: 'Reachable Apps', value: this.stats.reachableApps },
            { key: 'objectsWithAccess', label: 'Objects with Access', value: this.stats.objectsWithAccess }
        ];
        return defs
            .filter((d) => d.value !== null && d.value !== undefined)
            .map((d) => ({ ...d, display: d.value.toLocaleString() }));
    }

    get hasCards() { return this.cards.length > 0; }
}
