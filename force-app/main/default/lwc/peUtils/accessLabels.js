/** Format helpers. Plain verbs, sentence case, no filler. */

export function sourceKindLabel(kind) {
    switch (kind) {
        case 'profile': return 'Profile';
        case 'permset': return 'Permission set';
        case 'group':   return 'Permission set group';
        case 'muting':  return 'Muted by';
        default:        return 'Source';
    }
}

/* ---------------------------------------------------------------
 * Setup deep links
 *
 * Plain hrefs, never NavigationMixin: an admin comparing five permission sets
 * opens five tabs, and a programmatic navigate gives them one. Middle-click and
 * cmd-click have to keep working.
 *
 * One home for these shapes, because Salesforce changes Setup routes and a
 * hardcoded URL in three components is three bugs.
 * --------------------------------------------------------------- */

const SETUP_NODE = {
    profile: 'EnhancedProfiles',
    permset: 'PermSets',
    group: 'PermSetGroups'
};

function setupUrl(node, id) {
    return id ? `/lightning/setup/${node}/page?address=%2F${id}` : null;
}

export function profileSetupUrl(profileId) {
    return setupUrl(SETUP_NODE.profile, profileId);
}

export function permSetSetupUrl(permSetId) {
    return setupUrl(SETUP_NODE.permset, permSetId);
}

export function permSetGroupSetupUrl(groupId) {
    return setupUrl(SETUP_NODE.group, groupId);
}

/**
 * The Setup URL for one "granted by" source, or null when there is nothing to
 * open. Reads `linkId` — never `parentId` — because for a profile source those
 * are two different records: parentId is the profile-owned PermissionSet that
 * the permission rows join on, linkId is the ProfileId that Setup addresses.
 *
 * `linkable` is the server's verdict, so protected managed-package sets and
 * muting sets with no known group render as plain text rather than as a link
 * that 404s.
 */
export function sourceUrl(source) {
    if (!source || source.linkable === false || !source.linkId) return null;

    switch (source.kind) {
        case 'profile':
            return profileSetupUrl(source.linkId);
        case 'permset':
            return permSetSetupUrl(source.linkId);
        // A group chip names the group, so it opens the group. A muting set has
        // no standalone page at all — it is reachable only from inside its
        // group, which is why linkId already carries the group Id for both.
        case 'group':
        case 'muting':
            return permSetGroupSetupUrl(source.groupId ?? source.linkId);
        default:
            return null;
    }
}

/**
 * Opens a Setup URL in a real new browser tab.
 *
 * These are deliberately wired up on <button> elements, not <a> tags.
 * Lightning Experience's own navigation shell listens for clicks on anchors
 * pointing at internal `/lightning/...` routes in the CAPTURE phase, ahead of
 * any bubble-phase click handler a component adds — so even calling
 * `preventDefault()` from inside an anchor's own onclick never runs in time to
 * stop it. A <button> has no href for that shell to recognise or intercept in
 * the first place, so this always lands on a genuine new tab.
 */
export function openInNewTab(url) {
    if (url) {
        window.open(url, '_blank', 'noopener,noreferrer');
    }
}

export function tabVisibilityLabel(visibility) {
    switch (visibility) {
        case 'DefaultOn':  return 'Default on';
        case 'DefaultOff': return 'Default off';
        case 'Hidden':     return 'Tab hidden';
        case 'NoTab':      return 'No tab';
        default:           return 'Unknown';
    }
}

export function relativeTime(value) {
    if (!value) return 'Never signed in';
    const then = new Date(value).getTime();
    const days = Math.floor((Date.now() - then) / 86400000);
    if (days <= 0) {
        return 'Signed in today';
    }
    if (days === 1) {
        return 'Signed in yesterday';
    }
    if (days < 30) {
        return `Signed in ${days} days ago`;
    }
    if (days < 365) {
        return `Signed in ${Math.floor(days / 30)} months ago`;
    }
    return `Signed in ${Math.floor(days / 365)} years ago`;
}

export function asOf(datetime) {
    if (!datetime) {
        return '';
    }
    return new Date(datetime).toLocaleTimeString([], {
        hour: '2-digit', minute: '2-digit'
    });
}