import { LightningElement, api } from 'lwc';
import { STATE, openInNewTab } from 'c/peUtils';

/**
 * A list of things that live in Setup, each openable in a new tab.
 *
 * Deliberately dumb: it receives pre-shaped rows and renders them. Permission
 * sets and permission set groups differ only in which Setup page they point at
 * and which badge they carry, so mapping happens once in the root component
 * rather than twice in two near-identical components.
 *
 * Each item is `{ key, label, sublabel, url, linkable, badge, badgeClass, note }`.
 * `linkable: false` is not an oversight — a managed-package permission set the
 * running user cannot read has no Setup page they can open, and a link that
 * lands on an error is worse than plain text plus a reason.
 */
export default class PeUserListModal extends LightningElement {
    @api items = [];
    @api state = STATE.EMPTY;
    @api error;
    @api emptyHeadline = 'Nothing assigned';
    @api emptyDetail = '';
    /** Anything the list itself cannot say — counts that apply but are not listed. */
    @api footnote;

    handleRetry() {
        this.dispatchEvent(new CustomEvent('retry'));
    }

    /** A <button>, not an <a>, so Lightning's own navigation shell has
        nothing to intercept — see peUtils/accessLabels.js. */
    handleOpenSetup(event) {
        openInNewTab(event.currentTarget.dataset.url);
    }
}
