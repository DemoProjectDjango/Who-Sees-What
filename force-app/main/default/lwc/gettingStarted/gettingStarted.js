import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { openInNewTab } from 'c/peUtils';
import HIW_STEP1 from '@salesforce/resourceUrl/hiwStep1';
import HIW_STEP2 from '@salesforce/resourceUrl/hiwStep2';
import HIW_STEP3 from '@salesforce/resourceUrl/hiwStep3';
import HIW_STEP4 from '@salesforce/resourceUrl/hiwStep4';
import LIC_INSPECTOR_GUIDE from '@salesforce/resourceUrl/licInspectorGuide';
import WHO_SEES_WHAT_LOGO from '@salesforce/resourceUrl/whoSeesWhatLogo';

const TOPICS = [
    { id: 'setup', num: '1', title: 'Initial Setup Checklist', badge: 'Required', badgeClass: 'topic-badge tb-orange', desc: 'Permission sets & app setup' },
    { id: 'explorer', num: '2', title: 'Permission Explorer Guide', badge: 'Walkthrough', badgeClass: 'topic-badge tb-blue', desc: 'Step-by-step visual walkthrough' },
    { id: 'licenses', num: '3', title: 'License Inspector', badge: 'Inventory', badgeClass: 'topic-badge tb-green', desc: 'Seat allocation & analytics' },
    { id: 'contact', num: '4', title: 'Contact Info', badge: 'Support', badgeClass: 'topic-badge tb-blue', desc: 'TwinStack team & booking' }
];

const MIN_GS_H = 460;
const VIEWPORT_GUTTER = 14;

export default class GettingStarted extends NavigationMixin(LightningElement) {
    @track activeTopic = 'setup'; // Default open topic is Initial Setup Checklist
    copied = false;
    copyTimeout;
    _appliedHeight = 0;
    _resizeHandler;

    step1Img = HIW_STEP1;
    step2Img = HIW_STEP2;
    step3Img = HIW_STEP3;
    step4Img = HIW_STEP4;
    licInspectorImg = LIC_INSPECTOR_GUIDE;
    projectLogo = WHO_SEES_WHAT_LOGO;

    @track previewModalOpen = false;
    previewImgSrc = '';
    previewImgTitle = '';

    handleOpenPreview(event) {
        const step = event.currentTarget.dataset.step;
        if (step === '1') {
            this.previewImgSrc = this.step1Img;
            this.previewImgTitle = 'Step 1: Select or Search the User or Profile';
        } else if (step === '2') {
            this.previewImgSrc = this.step2Img;
            this.previewImgTitle = 'Step 2: Select the Application';
        } else if (step === '3') {
            this.previewImgSrc = this.step3Img;
            this.previewImgTitle = 'Step 3: Choose the Object or Tab';
        } else if (step === '4') {
            this.previewImgSrc = this.step4Img;
            this.previewImgTitle = 'Step 4: View Permissions, Field-Level Security & Access Sources';
        } else if (step === 'licenses' || step === 'lic') {
            this.previewImgSrc = this.licInspectorImg;
            this.previewImgTitle = 'License Inspector: Real-Time Org License Inventory';
        }
        this.previewModalOpen = true;
    }

    handleClosePreview() {
        this.previewModalOpen = false;
    }

    connectedCallback() {
        this._resizeHandler = () => this.syncHeight();
        window.addEventListener('resize', this._resizeHandler);
    }

    disconnectedCallback() {
        if (this._resizeHandler) {
            window.removeEventListener('resize', this._resizeHandler);
        }
    }

    renderedCallback() {
        this.syncHeight();
    }

    syncHeight() {
        const el = this.template.querySelector('.gs-wrapper');
        if (!el) return;

        const top = el.getBoundingClientRect().top;
        const height = Math.max(
            MIN_GS_H,
            Math.round(window.innerHeight - top - VIEWPORT_GUTTER)
        );

        if (this._appliedHeight === height) return;
        this._appliedHeight = height;
        el.style.setProperty('--pe-gs-h', `${height}px`);
    }

    get topicCountLabel() {
        return `${TOPICS.length} Topics`;
    }

    get topicList() {
        return TOPICS.map((t) => {
            const isActive = t.id === this.activeTopic;
            return {
                ...t,
                isActive,
                itemClass: isActive ? 'sidebar-item sidebar-item-active' : 'sidebar-item',
                ariaCurrent: isActive ? 'true' : 'false'
            };
        });
    }

    get isSetupTopic() {
        return this.activeTopic === 'setup';
    }

    get isExplorerTopic() {
        return this.activeTopic === 'explorer';
    }

    get isLicensesTopic() {
        return this.activeTopic === 'licenses';
    }

    get isContactTopic() {
        return this.activeTopic === 'contact';
    }

    @track copiedField = '';
    copiedFieldTimeout;

    get isWebsiteCopied() { return this.copiedField === 'website'; }
    get isCompanyMailCopied() { return this.copiedField === 'companyMail'; }
    get isEmployeeMailCopied() { return this.copiedField === 'employeeMail'; }
    get isPhoneCopied() { return this.copiedField === 'phone'; }
    get isWhatsappCopied() { return this.copiedField === 'whatsapp'; }
    get isCalendarCopied() { return this.copiedField === 'calendar'; }

    get contactList() {
        const c = this.copiedField;
        return [
            {
                key: 'website',
                label: 'Website',
                text: 'twinstack.net',
                value: 'twinstack.net',
                href: 'https://twinstack.net',
                actionLabel: 'Open',
                copied: c === 'website'
            },
            {
                key: 'companyMail',
                label: 'Company Mail',
                text: 'info@twinstack.net',
                value: 'info@twinstack.net',
                href: 'mailto:info@twinstack.net',
                actionLabel: 'Email',
                copied: c === 'companyMail'
            },
            {
                key: 'employeeMail',
                label: 'Employee Mail',
                text: 'saiful@twinstack.net',
                value: 'saiful@twinstack.net',
                href: 'mailto:saiful@twinstack.net',
                actionLabel: 'Email',
                copied: c === 'employeeMail'
            },
            {
                key: 'phone',
                label: 'Direct Message (US)',
                text: '+19292037060 (US)',
                value: '+19292037060',
                href: 'tel:+19292037060',
                actionLabel: 'Call',
                copied: c === 'phone'
            },
            {
                key: 'whatsapp',
                label: 'WhatsApp (BD)',
                text: '+8801556777043 (BD)',
                value: '+8801556777043',
                href: 'https://wa.me/8801556777043',
                actionLabel: 'Chat',
                copied: c === 'whatsapp'
            },
            {
                key: 'calendar',
                label: 'Calendar Link',
                text: 'calendar.app.google/HP3LiuNFisCt6xLo6',
                value: 'https://calendar.app.google/HP3LiuNFisCt6xLo6',
                href: 'https://calendar.app.google/HP3LiuNFisCt6xLo6',
                actionLabel: 'Book',
                copied: c === 'calendar'
            }
        ];
    }

    handleCopyContact(event) {
        const key = event.currentTarget.dataset.key;
        const val = event.currentTarget.dataset.value;
        if (!val) return;

        const markCopied = () => {
            this.copiedField = key;
            clearTimeout(this.copiedFieldTimeout);
            this.copiedFieldTimeout = setTimeout(() => {
                this.copiedField = '';
            }, 2000);
        };

        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(val).then(() => {
                markCopied();
            }).catch(() => {
                this.fallbackCopy(val);
                markCopied();
            });
        } else {
            this.fallbackCopy(val);
            markCopied();
        }
    }

    handleSelectTopic(event) {
        const id = event.currentTarget.dataset.id;
        if (id) {
            this.activeTopic = id;
            // Scroll content area back to top when switching topics
            const content = this.template.querySelector('.gs-content');
            if (content) {
                content.scrollTop = 0;
            }
        }
    }

    handleCopyPermSet() {
        const text = 'PermissionCheckerPermissionSet';
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(() => {
                this.setCopied();
            }).catch(() => {
                this.fallbackCopy(text);
            });
        } else {
            this.fallbackCopy(text);
        }
    }

    setCopied() {
        this.copied = true;
        clearTimeout(this.copyTimeout);
        this.copyTimeout = setTimeout(() => {
            this.copied = false;
        }, 2000);
    }

    fallbackCopy(text) {
        try {
            const input = document.createElement('textarea');
            input.value = text;
            input.style.position = 'fixed';
            input.style.opacity = '0';
            document.body.appendChild(input);
            input.select();
            document.execCommand('copy');
            document.body.removeChild(input);
            this.setCopied();
        } catch (e) {
            // copy fallback complete
        }
    }

    handleOpenPermSetsSetup() {
        openInNewTab('/lightning/setup/PermSets/home');
    }

    handleOpenProfilesSetup() {
        openInNewTab('/lightning/setup/EnhancedProfiles/home');
    }

    handleOpenAppManager() {
        openInNewTab('/lightning/setup/NavigationMenus/home');
    }

    handleOpenPermExplorer() {
        try {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: {
                    apiName: 'Permission_Explorer'
                }
            });
        } catch (e) {
            window.location.assign('/lightning/n/Permission_Explorer');
        }
    }

    handleOpenLicenseInspector() {
        try {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: {
                    apiName: 'License_Inspector'
                }
            });
        } catch (e) {
            window.location.assign('/lightning/n/License_Inspector');
        }
    }
}
