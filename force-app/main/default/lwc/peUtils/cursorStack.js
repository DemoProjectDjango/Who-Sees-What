/**
 * Keyset pagination has no "previous" query, so visited cursors are kept on a
 * stack and back pops it. Cheap, and avoids reverse-ordering the query.
 *
 * The reset guard matters: a stale cursor against a new filter set returns
 * plausible-looking wrong results, which is the failure mode that never gets
 * reported as a bug.
 */
export class CursorStack {
    constructor() {
        this.stack = [];
        this.signature = null;
    }

    /** Call on every filter or search change. Returns true if it reset. */
    syncFilters(signature) {
        if (this.signature === signature) return false;
        this.signature = signature;
        this.stack = [];
        return true;
    }

    get current() {
        return this.stack.length ? this.stack[this.stack.length - 1] : null;
    }

    get pageNumber() {
        return this.stack.length + 1;
    }

    get canGoBack() {
        return this.stack.length > 0;
    }

    push(cursor) {
        if (cursor) this.stack.push(cursor);
    }

    pop() {
        this.stack.pop();
    }

    reset() {
        this.stack = [];
    }
}

/** Stable signature for a filter set, so unrelated re-renders do not reset. */
export function filterSignature(filters) {
    return JSON.stringify({
        t: filters.term ?? '',
        p: filters.profileId ?? '',
        r: filters.roleId ?? '',
        u: filters.userType ?? '',
        s: filters.sortField ?? ''
    });
}