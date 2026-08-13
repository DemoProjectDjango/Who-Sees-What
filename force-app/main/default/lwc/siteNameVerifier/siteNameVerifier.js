import { LightningElement, track } from 'lwc';
import doesSiteExist from '@salesforce/apex/SiteNameCheckController.doesSiteExist';

export default class SiteNameVerifier extends LightningElement {

    @track inputValue = '';
    @track verdict = null;          // null = not checked, true = exists, false = not exists
    @track isLoading = false;
    @track error = null;

    handleInputChange(event) {
        this.inputValue = event.target.value;
        // Optional: clear verdict when user starts typing again
        this.verdict = null;
        this.error = null;
    }

    async handleVerify() {
        if (!this.inputValue.trim()) {
            this.verdict = null;
            this.error = 'Please enter a site name';
            return;
        }

        this.isLoading = true;
        this.verdict = null;
        this.error = null;

        try {
            const exists = await doesSiteExist({ siteName: this.inputValue });
            this.verdict = exists;
        } catch (err) {
            console.error(err);
            this.error = 'Error checking site name. Please try again.';
        } finally {
            this.isLoading = false;
        }
    }

    get verdictClass() {
        return this.verdict === true ? 'slds-text-color_success' 
             : this.verdict === false ? 'slds-text-color_error' 
             : '';
    }

    get verdictText() {
        if (this.verdict === true)  return 'Verified';
        if (this.verdict === false) return 'Failed';
        return '';
    }

    handleShowInstructions() {
        this.dispatchEvent(new CustomEvent('showinstructions'));
    }
}