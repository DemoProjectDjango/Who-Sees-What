/**
 * Deep-link state. A link pasted into a support ticket should land the
 * recipient on the exact panel, so modal and sub-tab state travel in the URL.
 */
const KEYS = ['userId', 'appId', 'objectId', 'tab'];

export function readState() {
    const params = new URLSearchParams(window.location.search);
    const out = {};
    KEYS.forEach((k) => {
        const v = params.get(k);
        if (v) {
            out[k] = v;
        }
    });
    return out;
}

export function writeState(state) {
    const params = new URLSearchParams(window.location.search);
    KEYS.forEach((k) => {
        if (state[k]) {
            params.set(k, state[k]);
        } else {
            params.delete(k);
        }
    });
    const next = `${window.location.pathname}?${params.toString()}`;
    window.history.replaceState({}, '', next);
}

export function shareableLink(state) {
    const params = new URLSearchParams();
    KEYS.forEach((k) => state[k] && params.set(k, state[k]));
    return `${window.location.origin}${window.location.pathname}?${params.toString()}`;
}