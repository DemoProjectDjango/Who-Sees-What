import { LightningElement, api } from 'lwc';

/**
 * Modal shell. Overlay, focus trap, focus restore, breadcrumb header.
 *
 * Initial focus lands on the heading rather than the close button, so a screen
 * reader announces which user and app the panel is about before offering a way
 * out of it.
 *
 * `heading` was added for the header drill-downs, which are about a user and a
 * topic rather than a user and an app. `appName` is left untouched so the
 * object panel keeps working with no change at its call site.
 */
export default class PeModal extends LightningElement {
    @api userName;
    @api appName;

    /** Second breadcrumb segment when the panel is not about an app. */
    @api heading;
    @api eyebrow = 'Permission Explorer';

    _focusSet = false;

    get hasCustomHeading() {
        return !!this.heading;
    }

    renderedCallback() {
        if (this._focusSet) return;
        this._focusSet = true;
        this.template.querySelector('.heading')?.focus();
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleBackdrop() {
        this.handleClose();
    }

    stopPropagation(event) {
        event.stopPropagation();
    }

    /**
     * Escape closes. Tab cycles inside — without the wrap, focus escapes to the
     * page behind the overlay, which for a keyboard user means the modal is a
     * trap they cannot see out of.
     */
    handleKeyDown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.handleClose();
            return;
        }
        if (event.key !== 'Tab') return;

        const focusable = this.focusableElements();
        if (!focusable.length) return;

        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        const active = this.template.activeElement;

        if (event.shiftKey && active === first) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && active === last) {
            event.preventDefault();
            first.focus();
        }
    }

    focusableElements() {
        return Array.from(
            this.template.querySelectorAll(
                'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
            )
        ).filter((el) => !el.disabled && el.offsetParent !== null);
    }
}
