import { LightningElement, api } from 'lwc';

/* Each figure is shown against the largest figure in its own group, so the bar
   answers "how much of this org's surface is this?" rather than implying a quota
   that does not exist. */
const GROUPS = [
    {
        key: 'people',
        title: 'People',
        keys: [
            { key: 'activeUsers', label: 'Active users' },
            { key: 'profiles', label: 'Profiles' }
        ]
    },
    {
        key: 'grants',
        title: 'Grants',
        keys: [
            { key: 'permissionSets', label: 'Permission sets' },
            { key: 'permissionSetGroups', label: 'Permission set groups' }
        ]
    },
    {
        key: 'reach',
        title: 'Reach',
        keys: [
            { key: 'reachableApps', label: 'Apps' },
            { key: 'objectsWithAccess', label: 'Objects with access' }
        ]
    }
];

/**
 * Org-wide counts, grouped by the question each pair answers.
 *
 * A count that came back null is omitted rather than rendered as 0 — see
 * PEOrgStatsService, where each query is independently try/caught. A fabricated
 * zero is indistinguishable from a genuine one, and on an access dashboard that
 * difference matters.
 */
export default class PeOrgStatsBar extends LightningElement {
    @api stats = {};
    @api loading = false;

    get groups() {
        const stats = this.stats ?? {};

        return GROUPS.map((group) => {
            const present = group.keys.filter(
                (f) => stats[f.key] !== null && stats[f.key] !== undefined
            );
            const peak = Math.max(...present.map((f) => stats[f.key]), 1);

            return {
                key: group.key,
                title: group.title,
                figures: present.map((f) => ({
                    key: f.key,
                    label: f.label,
                    value: stats[f.key].toLocaleString(),
                    barStyle: `width:${Math.max(4, Math.round((stats[f.key] / peak) * 100))}%`
                }))
            };
        }).filter((group) => group.figures.length > 0);
    }

    get hasCards() {
        return this.groups.length > 0;
    }
}
