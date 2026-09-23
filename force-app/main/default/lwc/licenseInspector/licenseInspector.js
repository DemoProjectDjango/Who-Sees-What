import { LightningElement } from 'lwc';
import getLicenses from '@salesforce/apex/PermissionExplorerController.getLicenses';
import getLicenseUsers from '@salesforce/apex/PermissionExplorerController.getLicenseUsers';
import { STATE, parseError } from 'c/peUtils';

const PAGE_SIZE = 12;

const CATEGORY_LABELS = {
    UserLicense: 'User license',
    PermissionSetLicense: 'Permission set license',
    PackageLicense: 'Package license',
    UsageEntitlement: 'Usage entitlement'
};

const CATEGORY_BADGE_CLASS = {
    UserLicense: 'badge badge_ul',
    PermissionSetLicense: 'badge badge_psl',
    PackageLicense: 'badge badge_pkg',
    UsageEntitlement: 'badge badge_use'
};

export default class LicenseInspector extends LightningElement {
    state = STATE.LOADING;
    error;
    licenses = [];
    lastRefreshed;

    searchTerm = '';
    quickFilter = 'all';
    statusFilter = 'ALL';
    sortKey = 'name';
    sortDir = 'asc';
    page = 1;

    _userCache = new Map();
    _previewLoading = new Set();
    _previewErrors = new Set();
    previewVersion = 0;

    connectedCallback() {
        this.loadLicenses();
    }

    async loadLicenses() {
        this.state = STATE.LOADING;
        this.error = undefined;

        try {
            const raw = await getLicenses();
            const res = raw ? JSON.parse(raw) : [];

            this.licenses = Array.isArray(res) ? res : [];
            this.state = this.licenses.length ? STATE.LOADED : STATE.LOADED_EMPTY;
            this.lastRefreshed = new Date();

            this.prefetchVisibleUsers();
        } catch (e) {
            this.error = parseError(e);
            this.state = STATE.ERROR;
        }
    }

    handleRetry() {
        this.loadLicenses();
    }

    handleRefresh() {
        this._userCache.clear();
        this._previewLoading.clear();
        this._previewErrors.clear();
        this.previewVersion += 1;
        this.page = 1;
        this.loadLicenses();
    }

    get lastRefreshedDisplay() {
        if (!this.lastRefreshed) {
            return '';
        }

        const now = new Date();
        const sameDay = now.toDateString() === this.lastRefreshed.toDateString();
        const time = this.lastRefreshed.toLocaleTimeString(undefined, {
            hour: 'numeric',
            minute: '2-digit'
        });

        return sameDay
            ? `Today at ${time}`
            : `${this.lastRefreshed.toLocaleDateString()} at ${time}`;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value ?? '';
        this.page = 1;
        this.prefetchVisibleUsers();
    }

    handleClearSearch() {
        this.searchTerm = '';
        this.page = 1;
        this.template.querySelector('.search-input')?.focus();
        this.prefetchVisibleUsers();
    }

    handleQuickFilter(event) {
        this.quickFilter = event.currentTarget.dataset.key;
        this.page = 1;
        this.prefetchVisibleUsers();
    }

    handleStatusFilter(event) {
        this.statusFilter = event.target.value;
        this.page = 1;
        this.prefetchVisibleUsers();
    }

    get hasLicenses() {
        return this.licenses.length > 0;
    }

    get allRows() {
        return this.licenses.map((license) => this.toRow(license));
    }

    toRow(license) {
        const name = license.name || '(unnamed)';
        const used = Number(license.used ?? 0);
        const unlimited = !!license.isUnlimited;
        const total = unlimited ? null : Number(license.total ?? 0);
        const free = unlimited
            ? null
            : Number(license.free ?? Math.max(0, total - used));

        const pctUsed = unlimited || !total
            ? 0
            : Math.min(100, Math.round((used / total) * 100));

        const isUsageEntitlement = license.licenseType === 'UsageEntitlement';
        const key = `${license.licenseType}:${license.licenseId}`;

        // eslint-disable-next-line no-void
        void this.previewVersion;

        const cachedUsers = this._userCache.get(key);
        const previewFailed = this._previewErrors.has(key);
        const assignedPreview = this.buildAssignedUsersPreview(
            cachedUsers,
            used,
            isUsageEntitlement,
            previewFailed
        );

        const availableClass = this.getAvailableClass(unlimited, free, total);
        const barClass = this.getBarClass(unlimited, used, total, pctUsed);
        const rowMeta = this.buildRowMeta(license);

        const status = license.status || '';
        const isStatusActive = status.toLowerCase() === 'active';
        const isStatusDisabled = status.toLowerCase() === 'disabled';
        const statusBadgeClass = isStatusActive
            ? 'status-pill status-active'
            : isStatusDisabled
            ? 'status-pill status-disabled'
            : status
            ? 'status-pill status-neutral'
            : '';

        return {
            key,
            licenseId: license.licenseId,
            licenseType: license.licenseType,
            name,
            orgStatus: license.status,
            statusBadgeClass,
            frequency: license.frequency,
            expirationDate: license.expirationDate,
            expirationDisplay: license.expirationDate
                ? new Date(license.expirationDate).toLocaleDateString()
                : null,

            typeLabel: CATEGORY_LABELS[license.licenseType] ?? license.licenseType,
            typeClass: CATEGORY_BADGE_CLASS[license.licenseType] ?? 'badge',
            hasUsers: !isUsageEntitlement,

            total,
            used,
            free,
            unlimited,
            pctUsed,

            usedDisplay: this.formatNumber(used),
            totalDisplay: unlimited ? '\u221E' : this.formatNumber(total),
            freeDisplay: unlimited ? '\u221E' : this.formatNumber(free),
            showProgress: !unlimited,
            barClass,
            barStyle: `width:${pctUsed}%`,
            progressAriaLabel: `${pctUsed}% used`,
            availableClass,
            rowMeta,

            assignedUsers: assignedPreview.users,
            showAssignedUsers: assignedPreview.showUsers,
            assignedUsersDisplay: assignedPreview.display,
            assignedUsersTitle: assignedPreview.title,
            assignedUsersClass: assignedPreview.cssClass
        };
    }

    buildRowMeta(license) {
        const parts = [];

        if (license.frequency) {
            parts.push(license.frequency);
        }

        if (license.expirationDate) {
            parts.push(`Expires ${new Date(license.expirationDate).toLocaleDateString()}`);
        }

        return parts.join(' \u2022 ');
    }

    getAvailableClass(unlimited, free, total) {
        if (unlimited) {
            return 'avail-value avail-unlimited';
        }

        if (free === 0) {
            return 'avail-badge avail-exhausted';
        }

        if (free <= 2 && total > 2) {
            return 'avail-badge avail-warning';
        }

        return 'avail-badge avail-positive';
    }

    getBarClass(unlimited, used, total, pctUsed) {
        if (unlimited) {
            return 'bar-fill bar-normal';
        }

        if (total > 0 && used >= total) {
            return 'bar-fill bar-danger';
        }

        if (pctUsed >= 80) {
            return 'bar-fill bar-warning';
        }

        return 'bar-fill bar-normal';
    }

    buildAssignedUsersPreview(cachedUsers, used, isUsageEntitlement, previewFailed) {
        if (isUsageEntitlement) {
            return {
                users: [],
                showUsers: false,
                display: 'Not applicable',
                title: 'Usage entitlements are org-wide allowances and are not assigned to individual users.',
                cssClass: 'assigned-users assigned-users_not-applicable'
            };
        }

        if (!used) {
            return {
                users: [],
                showUsers: false,
                display: 'None',
                title: 'No users currently hold this license.',
                cssClass: 'assigned-users assigned-users_muted'
            };
        }

        if (Array.isArray(cachedUsers)) {
            const users = cachedUsers
                .filter((user) => user?.userId && user?.name)
                .map((user) => ({
                    key: user.userId,
                    name: user.name,
                    username: user.username || '',
                    url: `/lightning/r/User/${user.userId}/view`
                }));

            if (users.length) {
                return {
                    users,
                    showUsers: true,
                    display: '',
                    title: '',
                    cssClass: 'assigned-users'
                };
            }

            return {
                users: [],
                showUsers: false,
                display: `${used} user${used === 1 ? '' : 's'}`,
                title: 'Assigned users were returned without displayable names.',
                cssClass: 'assigned-users assigned-users_muted'
            };
        }

        if (previewFailed) {
            return {
                users: [],
                showUsers: false,
                display: `${used} user${used === 1 ? '' : 's'}`,
                title: 'The assigned-user names could not be loaded.',
                cssClass: 'assigned-users assigned-users_muted'
            };
        }

        return {
            users: [],
            showUsers: false,
            display: 'Loading\u2026',
            title: 'Loading assigned users\u2026',
            cssClass: 'assigned-users assigned-users_muted'
        };
    }

    get quickFilterCounts() {
        const rows = this.allRows;
        const count = (type) => rows.filter((row) => row.licenseType === type).length;

        return {
            all: rows.length,
            UserLicense: count('UserLicense'),
            PermissionSetLicense: count('PermissionSetLicense'),
            PackageLicense: count('PackageLicense'),
            UsageEntitlement: count('UsageEntitlement')
        };
    }

    get quickFilterPills() {
        const counts = this.quickFilterCounts;
        const active = this.quickFilter;

        return [
            {
                key: 'all',
                label: 'All',
                count: counts.all,
                cls: this.pillClass(active === 'all')
            },
            {
                key: 'UserLicense',
                label: 'User Licenses',
                count: counts.UserLicense,
                cls: this.pillClass(active === 'UserLicense')
            },
            {
                key: 'PermissionSetLicense',
                label: 'Permission Set Licenses',
                count: counts.PermissionSetLicense,
                cls: this.pillClass(active === 'PermissionSetLicense')
            },
            {
                key: 'PackageLicense',
                label: 'Package Licenses',
                count: counts.PackageLicense,
                cls: this.pillClass(active === 'PackageLicense')
            },
            {
                key: 'UsageEntitlement',
                label: 'Usage Entitlements',
                count: counts.UsageEntitlement,
                cls: this.pillClass(active === 'UsageEntitlement')
            }
        ];
    }

    pillClass(isActive) {
        return isActive ? 'pill-btn active' : 'pill-btn';
    }

    get matchesFilters() {
        const term = this.searchTerm.trim().toLowerCase();
        const quick = this.quickFilter;
        const status = this.statusFilter;

        return (row) => {
            if (term) {
                const nameMatch = row.name.toLowerCase().includes(term);
                const categoryMatch = row.typeLabel.toLowerCase().includes(term);
                const statusMatch = (row.orgStatus || '').toLowerCase().includes(term);

                if (!nameMatch && !categoryMatch && !statusMatch) {
                    return false;
                }
            }

            if (quick !== 'all' && row.licenseType !== quick) {
                return false;
            }

            if (status === 'IN_USE' && row.used <= 0) {
                return false;
            }

            if (status === 'AVAILABLE' && !row.unlimited && row.free <= 0) {
                return false;
            }

            if (status === 'EXHAUSTED' && (row.unlimited || row.free > 0)) {
                return false;
            }

            return true;
        };
    }

    get filteredRows() {
        return this.allRows.filter(this.matchesFilters);
    }

    handleSort(event) {
        const key = event.currentTarget.dataset.key;

        if (this.sortKey === key) {
            this.sortDir = this.sortDir === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortKey = key;
            this.sortDir = key === 'name' || key === 'category' ? 'asc' : 'desc';
        }

        this.prefetchVisibleUsers();
    }

    get sortedRows() {
        const rows = [...this.filteredRows];
        const dir = this.sortDir === 'asc' ? 1 : -1;
        const key = this.sortKey;

        rows.sort((a, b) => {
            let av;
            let bv;

            if (key === 'name') {
                av = a.name.toLowerCase();
                bv = b.name.toLowerCase();
            } else if (key === 'category') {
                av = a.typeLabel.toLowerCase();
                bv = b.typeLabel.toLowerCase();
            } else if (key === 'used') {
                av = a.used;
                bv = b.used;
            } else if (key === 'free') {
                av = a.unlimited ? Infinity : a.free;
                bv = b.unlimited ? Infinity : b.free;
            } else {
                av = a.pctUsed;
                bv = b.pctUsed;
            }

            if (av < bv) {
                return -1 * dir;
            }

            if (av > bv) {
                return 1 * dir;
            }

            return a.name.localeCompare(b.name);
        });

        return rows;
    }

    get sortIndicator() {
        return this.sortDir === 'asc' ? '\u2191' : '\u2193';
    }

    headClass(key) {
        return this.sortKey === key ? 'sort-button active' : 'sort-button';
    }

    get nameSortClass() {
        return this.headClass('name');
    }

    get categorySortClass() {
        return this.headClass('category');
    }

    get usedSortClass() {
        return this.headClass('used');
    }

    get freeSortClass() {
        return this.headClass('free');
    }

    get nameSortArrow() {
        return this.sortKey === 'name' ? this.sortIndicator : '\u21C5';
    }

    get categorySortArrow() {
        return this.sortKey === 'category' ? this.sortIndicator : '\u21C5';
    }

    get usedSortArrow() {
        return this.sortKey === 'used' ? this.sortIndicator : '\u21C5';
    }

    get freeSortArrow() {
        return this.sortKey === 'free' ? this.sortIndicator : '\u21C5';
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.sortedRows.length / PAGE_SIZE));
    }

    get safePage() {
        return Math.min(this.page, this.totalPages);
    }

    get pagedRows() {
        const start = (this.safePage - 1) * PAGE_SIZE;
        return this.sortedRows.slice(start, start + PAGE_SIZE);
    }

    get isEmptyFiltered() {
        return this.state === STATE.LOADED && this.sortedRows.length === 0;
    }

    get paginationSummary() {
        const total = this.sortedRows.length;

        if (!total) {
            return 'Showing 0\u20130 of 0 licenses';
        }

        const start = (this.safePage - 1) * PAGE_SIZE + 1;
        const end = Math.min(total, start + PAGE_SIZE - 1);

        return `Showing ${start}\u2013${end} of ${total} license${total === 1 ? '' : 's'}`;
    }

    get pageNumbers() {
        const total = this.totalPages;
        const current = this.safePage;
        const nums = [];

        const push = (n) => {
            nums.push({
                n,
                key: `p${n}`,
                cls: n === current ? 'pg-num active' : 'pg-num',
                gap: false
            });
        };

        const pushGap = (key) => {
            nums.push({
                n: null,
                key,
                cls: 'pg-ellipsis',
                gap: true
            });
        };

        if (total <= 7) {
            for (let i = 1; i <= total; i += 1) {
                push(i);
            }
        } else {
            push(1);

            if (current > 3) {
                pushGap('gap1');
            }

            const from = Math.max(2, current - 1);
            const to = Math.min(total - 1, current + 1);

            for (let i = from; i <= to; i += 1) {
                push(i);
            }

            if (current < total - 2) {
                pushGap('gap2');
            }

            push(total);
        }

        return nums;
    }

    get hasPrevPage() {
        return this.safePage > 1;
    }

    get hasNextPage() {
        return this.safePage < this.totalPages;
    }

    get isFirstPage() {
        return !this.hasPrevPage;
    }

    get isLastPage() {
        return !this.hasNextPage;
    }

    handlePrevPage() {
        if (this.hasPrevPage) {
            this.page = this.safePage - 1;
            this.prefetchVisibleUsers();
        }
    }

    handleNextPage() {
        if (this.hasNextPage) {
            this.page = this.safePage + 1;
            this.prefetchVisibleUsers();
        }
    }

    handleGoToPage(event) {
        const n = Number(event.currentTarget.dataset.n);

        if (n) {
            this.page = n;
            this.prefetchVisibleUsers();
        }
    }

    get exportDisabled() {
        return !this.hasLicenses || this.sortedRows.length === 0;
    }

    get summary() {
        let seats = 0;
        let free = 0;
        let hasUnlimited = false;

        for (const row of this.allRows) {
            seats += row.used;

            if (row.unlimited) {
                hasUnlimited = true;
            } else {
                free += row.free;
            }
        }

        return {
            types: this.allRows.length,
            seats,
            free,
            hasUnlimited,
            typesDisplay: this.formatNumber(this.allRows.length),
            seatsDisplay: this.formatNumber(seats),
            freeDisplay: this.formatNumber(free)
        };
    }

    handleExport() {
        const rows = this.sortedRows;
        const header = [
            'License Name',
            'Category',
            'Org Status',
            'Used',
            'Total',
            'Available',
            'Utilization %',
            'Expiration',
            'Frequency',
            'Assigned Users'
        ];

        const lines = [header.join(',')];

        for (const row of rows) {
            const assignedUsers = Array.isArray(row.assignedUsers)
                ? row.assignedUsers.map((user) => user.name).join('; ')
                : '';

            const cells = [
                row.name,
                row.typeLabel,
                row.orgStatus ?? '',
                row.used,
                row.unlimited ? 'Unlimited' : row.total,
                row.unlimited ? 'Unlimited' : row.free,
                row.unlimited ? '' : row.pctUsed,
                row.expirationDisplay ?? '',
                row.frequency ?? '',
                assignedUsers
            ].map(this.csvCell);

            lines.push(cells.join(','));
        }

        const csv = lines.join('\r\n');
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        const stamp = new Date().toISOString().slice(0, 10);

        anchor.href = url;
        anchor.download = `license-inspector-${stamp}.csv`;
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
        URL.revokeObjectURL(url);
    }

    csvCell(value) {
        const valueString = String(value ?? '');

        return /[",\n]/.test(valueString)
            ? `"${valueString.replace(/"/g, '""')}"`
            : valueString;
    }

    formatNumber(value) {
        const numeric = Number(value ?? 0);

        return Number.isFinite(numeric)
            ? numeric.toLocaleString()
            : String(value ?? '');
    }

    prefetchVisibleUsers() {
        Promise.resolve().then(() => {
            for (const row of this.pagedRows) {
                if (!row.hasUsers || !row.used) {
                    continue;
                }

                if (this._userCache.has(row.key) || this._previewLoading.has(row.key)) {
                    continue;
                }

                this.prefetchUsersForRow(row);
            }
        });
    }

    async prefetchUsersForRow(row) {
        this._previewLoading.add(row.key);
        this._previewErrors.delete(row.key);
        this.previewVersion += 1;

        try {
            const raw = await getLicenseUsers({
                licenseId: row.licenseId,
                licenseType: row.licenseType
            });

            const res = raw ? JSON.parse(raw) : [];
            const list = Array.isArray(res) ? res : [];

            this._userCache.set(row.key, list);
        } catch {
            this._previewErrors.add(row.key);
        } finally {
            this._previewLoading.delete(row.key);
            this.previewVersion += 1;
        }
    }
}
