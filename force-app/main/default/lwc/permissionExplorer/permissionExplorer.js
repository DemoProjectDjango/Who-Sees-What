import { LightningElement } from "lwc";
import resolveUser from "@salesforce/apex/PermissionExplorerController.resolveUser";
import getAppObjects from "@salesforce/apex/PermissionExplorerController.getAppObjects";
import refreshCache from "@salesforce/apex/PermissionExplorerController.refreshCache";
import getObjectDetail from "@salesforce/apex/PermissionExplorerController.getObjectDetail";
import getLoginHistory from "@salesforce/apex/PermissionExplorerController.getLoginHistory";
import getAssignedPermissionSets from "@salesforce/apex/PermissionExplorerController.getAssignedPermissionSets";
import getAssignedPermissionSetGroups from "@salesforce/apex/PermissionExplorerController.getAssignedPermissionSetGroups";
import WHO_SEES_WHAT_LOGO from "@salesforce/resourceUrl/whoSeesWhatLogo";
import {
  STATE,
  parseError,
  readState,
  writeState,
  shareableLink
} from "c/peUtils";

/* Floor for the pinned viewport height, and the breathing room left under the
   component so its bottom border is not flush against the window edge. */
const MIN_EXPLORER_H = 620;

/* The three left-rail stages. */
const STAGE = { WHO: "who", APP: "app", OBJECTS: "objects" };
const VIEWPORT_GUTTER = 12;

/** Which modal is open, if any. A single value cannot represent "both". */
const MODAL = {
  NONE: null,
  LOGIN: "login",
  PERMSETS: "permsets",
  GROUPS: "groups",
  TRACE: "trace"
};

const LOGIN_HISTORY_ROWS = 50;

/**
 * Setup deep links. Plain anchors rather than NavigationMixin, because "open in
 * a new tab" should also mean middle-click and cmd-click — an admin comparing
 * five permission sets opens five tabs, and a programmatic navigate gives them
 * one.
 */
const permSetSetupUrl = (id) =>
  `/lightning/setup/PermSets/page?address=%2F${id}`;
const permSetGroupSetupUrl = (id) =>
  `/lightning/setup/PermSetGroups/page?address=%2F${id}`;

/**
 * Owns every piece of state and pushes it down as props; children are
 * presentational and emit events upward.
 *
 * That single decision is what makes URL state and the modal's prev/next
 * arrows trivial rather than a synchronisation problem — the arrows just
 * increment an index in this component's object list and the modal re-renders
 * from new props.
 */
export default class PermissionExplorer extends LightningElement {
  projectLogo = WHO_SEES_WHAT_LOGO;

  /* ------------------------------- state ------------------------------- */

  selectedUserId;
  selectedAppId;
  selectedObjectApiName;
  selectedObjectLabel;

  userSummary;
  appList = { apps: [] };
  objectRows = [];

  appState = STATE.EMPTY;
  appError;
  railState = STATE.EMPTY;
  railError;

  /* The WHAT column. Fetched per object and held for the current app, so
       clicking back and forth between two objects costs one request each. */
  objectDetail;
  detailState = STATE.EMPTY;
  detailError;
  _detailCache = {};

  activeModal = MODAL.NONE;
  resolvedAt;

  /* Left-rail stages open/closed states. Users can toggle each section independently. */
  _whoOpen = true;
  _appOpen = false;
  _objectsOpen = false;

  /* The access trace. Fed from the row that opened it rather than refetched:
       the detail is already in hand, and a second GET_OBJECT_DETAIL would write
       a second inspection log row for one user action. */
  traceApiName;
  traceLabel;
  traceDetail;
  traceCopied = false;

  copied = false;
  _copyTimer;
  _resizeHandler;
  _appliedHeight;

  /* Header drill-downs. Fetched on first open, then held for this user. */
  loginHistory = {};
  loginState = STATE.EMPTY;
  loginError;

  permSetList = { directSets: [] };
  permSetState = STATE.EMPTY;
  permSetError;

  groupList = [];
  groupState = STATE.EMPTY;
  groupError;

  _triggerElement;

  /* ------------------------------ lifecycle ------------------------------ */

  connectedCallback() {
    this.restoreFromUrl();
  }

  /* The explorer is pinned to the viewport rather than sized by its content,
       so it has to know how much Lightning chrome sits above it. That height is
       not a constant: a Developer Edition banner, an App Builder region, a
       console subtab or an Experience Cloud header each change it, and a
       hardcoded offset is wrong in all but one of them. When it is wrong by
       even a few pixels the page itself grows a scrollbar and the bottom strip
       of the columns - the object list's last rows, the filter chips - falls
       below the fold, which reads to the user as "the left panel will not
       scroll". So measure it per render and on resize instead of guessing. */
  renderedCallback() {
    if (!this._resizeHandler) {
      this._resizeHandler = () => this.syncHeight();
      window.addEventListener("resize", this._resizeHandler);
    }
    this.syncHeight();
  }

  syncHeight() {
    const el = this.template.querySelector(".explorer");
    if (!el) return;

    const top = el.getBoundingClientRect().top;
    // The floor matters: below it the cards would be crushed, and letting
    // the page scroll is the better failure.
    const height = Math.max(
      MIN_EXPLORER_H,
      Math.round(window.innerHeight - top - VIEWPORT_GUTTER)
    );

    // renderedCallback fires on every reactive change; writing the same
    // value back would invalidate layout on each one.
    if (this._appliedHeight === height) return;
    this._appliedHeight = height;
    el.style.setProperty("--pe-explorer-h", height + "px");
  }

  /** A link pasted into a support ticket should land on the exact panel. */
  async restoreFromUrl() {
    const state = readState();
    if (!state.userId) return;

    await this.loadUser(state.userId);
    if (!state.appId) return;
    if (!this.appList.apps.some((a) => a.developerName === state.appId)) return;

    await this.loadAppObjects(state.appId);
    if (!state.objectId) return;

    const row = this.objectRows.find((r) => r.apiName === state.objectId);
    if (!row) return;

    // Someone following a pasted link wants the answer, not the wizard.
    this._whoOpen = false;
    this._appOpen = false;
    this._objectsOpen = true;
    if (state.tab === "trace") this.handleExplain();
  }

  /* ------------------------------- derived ------------------------------- */

  get isLoginModal() {
    return this.activeModal === MODAL.LOGIN && !!this.userSummary;
  }
  get isPermSetModal() {
    return this.activeModal === MODAL.PERMSETS && !!this.userSummary;
  }
  get isGroupModal() {
    return this.activeModal === MODAL.GROUPS && !!this.userSummary;
  }
  get isTraceModal() {
    return (
      this.activeModal === MODAL.TRACE &&
      !!this.userSummary &&
      !!this.traceDetail
    );
  }

  /** Names the next thing to click rather than just saying the panel is empty. */
  get placeholderHeading() {
    if (!this.selectedUserId) return "Start with Who";
    if (!this.selectedAppId) return "Now choose Where";
    return "Choose an Object or Tab";
  }

  get placeholderText() {
    if (!this.selectedUserId)
      return "Choose a user from WHO on the left to begin.";
    if (!this.selectedAppId)
      return "Choose an app from WHERE on the left to see what it reaches.";
    return "Choose an object to see its permissions, fields and the source of every grant.";
  }

  get copyLabel() {
    return this.copied ? "Link copied" : "Copy link to this view";
  }

  get traceShareLink() {
    return shareableLink({
      userId: this.selectedUserId,
      appId: this.selectedAppId,
      objectId: this.traceApiName,
      tab: "trace"
    });
  }

  get selectedAppLabel() {
    const app = this.appList.apps.find(
      (a) => a.developerName === this.selectedAppId
    );
    return app?.label ?? this.selectedAppId;
  }

  /** The row peObjectList already has for the selected object — reused
        rather than re-fetched, purely to hand its tabVisibility down to the
        WHAT column's overview badges. */
  get selectedObjectRow() {
    return this.objectRows.find(
      (r) => r.apiName === this.selectedObjectApiName
    );
  }

  get selectedObjectTabVisibility() {
    return this.selectedObjectRow?.tabVisibility;
  }

  get whoSectionClass() {
    return [
      "nav_section",
      "nav_section_who",
      this.whoOpen ? "nav_section_open" : "nav_section_shut",
      this.selectedUserId ? "nav_section_done" : ""
    ].filter(Boolean).join(" ");
  }

  get whereSectionClass() {
    return [
      "nav_section",
      "nav_section_where",
      this.appStageDisabled
        ? "nav_section_waiting"
        : (this.appOpen ? "nav_section_open" : "nav_section_shut"),
      this.selectedAppId ? "nav_section_done" : ""
    ].filter(Boolean).join(" ");
  }

  get objectSectionClass() {
    return [
      "nav_section",
      "nav_section_objects",
      this.objectStageDisabled
        ? "nav_section_waiting"
        : (this.objectsOpen ? "nav_section_open" : "nav_section_shut"),
      this.selectedObjectApiName ? "nav_section_done" : ""
    ].filter(Boolean).join(" ");
  }

  get isWhoDone() {
    return Boolean(this.selectedUserId && !this.whoOpen);
  }

  get isAppDone() {
    return Boolean(this.selectedAppId && !this.appOpen);
  }

  get isObjectDone() {
    return Boolean(this.selectedObjectApiName && !this.objectsOpen);
  }

  get whoBadgeClass() {
    return this.isWhoDone
      ? "nav_step nav_step_done"
      : (this.whoOpen ? "nav_step nav_step_active" : "nav_step");
  }

  get appBadgeClass() {
    return this.isAppDone
      ? "nav_step nav_step_done"
      : (this.appOpen
          ? "nav_step nav_step_active"
          : (this.appStageDisabled ? "nav_step nav_step_disabled" : "nav_step"));
  }

  get objectBadgeClass() {
    return this.isObjectDone
      ? "nav_step nav_step_done"
      : (this.objectsOpen
          ? "nav_step nav_step_active"
          : (this.objectStageDisabled ? "nav_step nav_step_disabled" : "nav_step"));
  }

  get whoActionLabel() {
    return this.whoOpen ? (this.selectedUserId ? "Done" : "") : "Change";
  }

  get appActionLabel() {
    return this.appOpen ? (this.selectedAppId ? "Done" : "") : "Change";
  }

  get objectActionLabel() {
    return this.objectsOpen ? (this.selectedObjectApiName ? "Done" : "") : "Change";
  }

  get hasWorkspaceContext() {
    return !!this.userSummary || !!this.selectedObjectApiName;
  }

  get workspaceClass() {
    return this.hasWorkspaceContext
      ? "workspace workspace_with_context"
      : "workspace";
  }

  progressClass(done, current) {
    if (done) return "progress_step progress_done";
    if (current) return "progress_step progress_current";
    return "progress_step";
  }

  get whoProgressClass() {
    return this.progressClass(!!this.selectedUserId, !this.selectedUserId);
  }

  get appProgressClass() {
    return this.progressClass(
      !!this.selectedAppId,
      !!this.selectedUserId && !this.selectedAppId
    );
  }

  get objectProgressClass() {
    return this.progressClass(
      !!this.selectedObjectApiName,
      !!this.selectedAppId && !this.selectedObjectApiName
    );
  }

  /* ----------------------- left-rail stage state ----------------------- */

  get whoOpen() {
    return this._whoOpen;
  }
  get appOpen() {
    return this._appOpen;
  }
  get objectsOpen() {
    return this._objectsOpen;
  }

  get whoOpenStr() {
    return String(this._whoOpen);
  }
  get appOpenStr() {
    return String(this._appOpen);
  }
  get objectsOpenStr() {
    return String(this._objectsOpen);
  }

  get whoChevronClass() {
    return this._whoOpen ? "stage_chevron stage_chevron_open" : "stage_chevron";
  }
  get appChevronClass() {
    return this._appOpen ? "stage_chevron stage_chevron_open" : "stage_chevron";
  }
  get objectChevronClass() {
    return this._objectsOpen ? "stage_chevron stage_chevron_open" : "stage_chevron";
  }

  get whoToggleTitle() {
    return this._whoOpen ? "Click to collapse Who" : "Click to expand Who";
  }
  get appToggleTitle() {
    if (this.appStageDisabled) return "Select a user first to unlock";
    return this._appOpen ? "Click to collapse Where" : "Click to expand Where";
  }
  get objectToggleTitle() {
    if (this.objectStageDisabled) return "Select an application first to unlock";
    return this._objectsOpen ? "Click to collapse Object / Tab" : "Click to expand Object / Tab";
  }

  get whoHeadClass() {
    return "nav_section_head clickable_head";
  }
  get whereHeadClass() {
    return [
      "nav_section_head",
      this.appStageDisabled ? "head_disabled" : "clickable_head"
    ].join(" ");
  }
  get objectHeadClass() {
    return [
      "nav_section_head",
      this.objectStageDisabled ? "head_disabled" : "clickable_head"
    ].join(" ");
  }

  stageClass(isOpen, isDisabled) {
    let out = "stage";
    out += isOpen ? " stage_open" : " stage_shut";
    if (isDisabled) out += " stage_off";
    return out;
  }

  get whoStageClass() {
    return this.stageClass(this.whoOpen, false);
  }
  get appStageClass() {
    return this.stageClass(this.appOpen, this.appStageDisabled);
  }
  get objectStageClass() {
    return this.stageClass(this.objectsOpen, this.objectStageDisabled);
  }

  /* A stage you have not reached yet cannot be opened — there is nothing in
       it to show, and an empty panel reads as a failure rather than an order. */
  get appStageDisabled() {
    return !this.selectedUserId;
  }
  get objectStageDisabled() {
    return !this.selectedAppId;
  }

  /* Collapsed rows have to carry the selection, otherwise compressing them
       costs the user the answer they already established. */
  get whoSummary() {
    if (!this.userSummary) return "Select a user";
    const who = this.userSummary;
    return [who.name, who.username].filter(Boolean).join(" · ");
  }

  get appSummary() {
    if (!this.selectedUserId) return "Select a user first";
    if (!this.selectedAppId) return "Choose an app";
    return [this.selectedAppLabel, this.appTally].filter(Boolean).join(" · ");
  }

  get objectSummary() {
    if (!this.selectedAppId) return "Choose an app first";
    if (this.railState === STATE.LOADING) return "Loading…";
    const n = this.objectRows.length;
    if (!n) return "No objects reachable";
    return this.selectedObjectLabel
      ? `${this.selectedObjectLabel} · ${n} reachable`
      : `${n} objects reachable`;
  }

  get appTally() {
    const apps = this.appList?.apps ?? [];
    if (!apps.length) return "";
    const visible = apps.filter((a) => a.visible).length;
    return `${visible} of ${apps.length} apps visible`;
  }

  /* Surfaced on the collapsed header too: an estimate that only shows while
       the panel happens to be open is not a disclosure. */
  get showEstimateMark() {
    return !!this.appList?.setupRequired && !!this.selectedUserId;
  }

  get appEstimateNote() {
    return this.appList?.setupMessage ?? "";
  }

  get crumbs() {
    const out = [];
    if (this.userSummary) {
      out.push({ key: "u", label: this.userSummary.name, separator: false });
    }
    if (this.selectedAppId) {
      const app = this.appList.apps.find(
        (a) => a.developerName === this.selectedAppId
      );
      out.push({
        key: "a",
        label: app?.label ?? this.selectedAppId,
        separator: true
      });
    }
    if (this.selectedObjectApiName) {
      out.push({
        key: "o",
        label: this.selectedObjectLabel ?? this.selectedObjectApiName,
        separator: true
      });
    }
    return out;
  }

  /* --------------------- drill-down row shaping --------------------- */

  /**
   * Sorted here rather than in Apex: `List.sort()` on a wrapper needs
   * Comparable, and a locale-aware compare belongs on the client anyway.
   */
  get permSetItems() {
    const rows = [...(this.permSetList?.directSets ?? [])];
    rows.sort((a, b) => (a.label ?? "").localeCompare(b.label ?? ""));

    return rows.map((r, i) => {
      const linkable = r.isReadable !== false && !!r.permSetId;
      return {
        key: r.permSetId ?? `ps-${i}`,
        label: r.label ?? "Unnamed permission set",
        sublabel: r.apiName ?? null,
        url: linkable ? permSetSetupUrl(r.permSetId) : null,
        linkable,
        badge: this.permSetBadge(r.setType),
        badgeClass: "badge",
        note: linkable
          ? null
          : "This permission set belongs to a managed package and its definition is not readable, so it cannot be opened in Setup. Its permissions still apply."
      };
    });
  }

  /** Only the unusual types are worth a badge; "Regular" is the default. */
  permSetBadge(setType) {
    if (!setType || setType === "Regular") return null;
    return setType;
  }

  get permSetFootnote() {
    const via = this.permSetList?.viaGroupCount ?? 0;
    const unreadable = this.permSetList?.unreadableCount ?? 0;
    const parts = [];

    if (via) {
      parts.push(
        `${via} further permission set${via === 1 ? "" : "s"} appl${via === 1 ? "ies" : "y"} ` +
          "through assigned permission set groups and are not listed here."
      );
    }
    if (unreadable) {
      parts.push(
        `${unreadable} of these could not be read, so ${unreadable === 1 ? "its label is" : "their labels are"} unavailable.`
      );
    }
    return parts.length ? parts.join(" ") : null;
  }

  get groupItems() {
    const rows = [...(this.groupList ?? [])];
    rows.sort((a, b) =>
      (a.masterLabel ?? a.developerName ?? "").localeCompare(
        b.masterLabel ?? b.developerName ?? ""
      )
    );

    return rows.map((r, i) => ({
      key: r.groupId ?? `psg-${i}`,
      label: r.masterLabel ?? r.developerName ?? "Unnamed group",
      sublabel: r.developerName ?? null,
      url: r.groupId ? permSetGroupSetupUrl(r.groupId) : null,
      linkable: !!r.groupId,
      badge: r.isOutdated ? (r.status ?? "Not updated") : null,
      badgeClass: r.isOutdated ? "badge badge_caution" : "badge",
      note: r.isOutdated
        ? "This group is still recalculating, so its effective permissions are not yet settled."
        : null
    }));
  }

  get groupFootnote() {
    const outdated = (this.groupList ?? []).filter((g) => g.isOutdated).length;
    if (!outdated) return null;
    return (
      `${outdated} group${outdated === 1 ? " is" : "s are"} still recalculating. ` +
      "Treat any permission traced to them as provisional."
    );
  }

  /* ------------------------------- loading ------------------------------- */

  async loadUser(userId, forceRefresh = false) {
    this.selectedUserId = userId;
    this.selectedAppId = undefined;
    this.objectRows = [];
    this.clearObject();
    this.appState = STATE.LOADING;
    this.appError = undefined;
    this.resetDrillDowns();

    try {
      const ctx = await resolveUser({ userId, forceRefresh });
      this.userSummary = ctx.summary;
      this.appList = ctx.apps ?? { apps: [] };
      this.resolvedAt = ctx.summary?.resolvedAt;
      this.appState = this.appList.apps.length
        ? STATE.LOADED
        : STATE.LOADED_EMPTY;
      this._whoOpen = false;
      this._appOpen = true;
    } catch (e) {
      this.appError = parseError(e);
      this.appState = STATE.ERROR;
      this.userSummary = undefined;
      // A failed resolve leaves nothing to choose an app from, so the
      // rail stays where the user can act: on the user list.
      this._whoOpen = true;
    }
    this.syncUrl();
  }

  /** A new user invalidates all three panels; stale rows under a new name is
        the worst possible outcome for an audit tool. */
  resetDrillDowns() {
    this.activeModal = MODAL.NONE;
    this.loginHistory = {};
    this.loginState = STATE.EMPTY;
    this.loginError = undefined;
    this.permSetList = { directSets: [] };
    this.permSetState = STATE.EMPTY;
    this.permSetError = undefined;
    this.groupList = [];
    this.groupState = STATE.EMPTY;
    this.groupError = undefined;
  }

  /**
   * Fired on app click, before the modal finishes its open transition — the
   * animation buys 200–300 ms of free loading time, which is frequently the
   * entire request.
   */
  async loadAppObjects(appId) {
    this.selectedAppId = appId;
    this.railState = STATE.LOADING;
    this.railError = undefined;
    this.objectRows = [];
    this.clearObject();

    try {
      const rows = await getAppObjects({
        userId: this.selectedUserId,
        appDeveloperName: appId
      });
      this.objectRows = rows ?? [];
      this.railState = this.objectRows.length
        ? STATE.LOADED
        : STATE.LOADED_EMPTY;
      this._appOpen = false;
      this._objectsOpen = true;
    } catch (e) {
      this.railError = parseError(e);
      this.railState = STATE.ERROR;
      this._objectsOpen = true;
    }
    this.syncUrl();
  }

  /** A different app means a different set of objects; the old one must go. */
  clearObject() {
    this.selectedObjectApiName = undefined;
    this.selectedObjectLabel = undefined;
    this.objectDetail = undefined;
    this.detailState = STATE.EMPTY;
    this.detailError = undefined;
    this._detailCache = {};
  }

  /**
   * Fetch one object's detail for the WHAT column.
   *
   * Cached per app: an admin comparing two objects flips between them several
   * times, and each fetch writes a GET_OBJECT_DETAIL row into the inspection
   * log. Re-reading what is already on screen should not fill the log with
   * duplicates of one look.
   */
  async loadObjectDetail(apiName, label) {
    this.selectedObjectApiName = apiName;
    this.selectedObjectLabel = label ?? apiName;
    this.detailError = undefined;

    const cached = this._detailCache[apiName];
    if (cached) {
      this.objectDetail = cached;
      this.detailState = STATE.LOADED;
      this.syncUrl();
      return;
    }

    this.objectDetail = undefined;
    this.detailState = STATE.LOADING;

    try {
      const detail = await getObjectDetail({
        userId: this.selectedUserId,
        objectApiName: apiName
      });
      // The user may have clicked a different object while this was in
      // flight; only the current selection may write to the column.
      if (this.selectedObjectApiName !== apiName) return;

      this._detailCache = { ...this._detailCache, [apiName]: detail };
      this.objectDetail = detail;
      this.detailState = STATE.LOADED;
    } catch (e) {
      if (this.selectedObjectApiName !== apiName) return;
      this.detailError = parseError(e);
      this.detailState = STATE.ERROR;
    }
    this.syncUrl();
  }

  /* --------------------------- drill-down loading --------------------------- */

  /**
   * Login history is a query against an object the running user may not be
   * permitted to read, so it is never fetched on user selection — only when
   * someone actually asks for it.
   */
  async loadLoginHistory() {
    this.loginState = STATE.LOADING;
    this.loginError = undefined;

    try {
      const res = await getLoginHistory({
        userId: this.selectedUserId,
        maxRows: LOGIN_HISTORY_ROWS
      });
      this.loginHistory = res ?? {};
      // An unavailable panel is LOADED, not EMPTY: the component renders
      // its own explanation and must not fall through to "no sign-ins".
      this.loginState =
        res?.notAvailableReason || res?.events?.length
          ? STATE.LOADED
          : STATE.LOADED_EMPTY;
    } catch (e) {
      this.loginError = parseError(e);
      this.loginState = STATE.ERROR;
    }
  }

  async loadPermSets() {
    this.permSetState = STATE.LOADING;
    this.permSetError = undefined;

    try {
      const res = await getAssignedPermissionSets({
        userId: this.selectedUserId
      });
      this.permSetList = res ?? { directSets: [] };
      this.permSetState = this.permSetList.directSets?.length
        ? STATE.LOADED
        : STATE.LOADED_EMPTY;
    } catch (e) {
      this.permSetError = parseError(e);
      this.permSetState = STATE.ERROR;
    }
  }

  async loadGroups() {
    this.groupState = STATE.LOADING;
    this.groupError = undefined;

    try {
      const res = await getAssignedPermissionSetGroups({
        userId: this.selectedUserId
      });
      this.groupList = res ?? [];
      this.groupState = this.groupList.length
        ? STATE.LOADED
        : STATE.LOADED_EMPTY;
    } catch (e) {
      this.groupError = parseError(e);
      this.groupState = STATE.ERROR;
    }
  }

  /* ------------------------------- handlers ------------------------------- */

  /* Reopening a completed stage must not throw away what is downstream of
       it: an admin reopens WHO to re-read the list, not to reset the view.
       Only an actual change of selection cascades — see loadUser /
       loadAppObjects. */
  handleStageToggle(event) {
    if (event && event.stopPropagation) {
      event.stopPropagation();
    }
    const stage = event.currentTarget?.dataset?.stage || event.target?.dataset?.stage;
    if (!stage) return;
    if (stage === STAGE.APP && this.appStageDisabled) return;
    if (stage === STAGE.OBJECTS && this.objectStageDisabled) return;

    if (stage === STAGE.WHO) {
      this._whoOpen = !this._whoOpen;
    } else if (stage === STAGE.APP) {
      this._appOpen = !this._appOpen;
    } else if (stage === STAGE.OBJECTS) {
      this._objectsOpen = !this._objectsOpen;
    }
  }

  handleStageKeyDown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleStageToggle(event);
    }
  }

  handleUserSelect(event) {
    this.loadUser(event.detail.userId);
  }

  handleAppSelect(event) {
    this.loadAppObjects(event.detail.appId);
  }

  handleObjectSelect(event) {
    this.loadObjectDetail(event.detail.apiName, event.detail.label);
  }

  handleDetailRetry() {
    if (!this.selectedObjectApiName) return;
    const apiName = this.selectedObjectApiName;
    const rest = { ...this._detailCache };
    delete rest[apiName];
    this._detailCache = rest;
    this.loadObjectDetail(apiName, this.selectedObjectLabel);
  }

  handleAppRetry() {
    if (this.selectedUserId) this.loadUser(this.selectedUserId, true);
  }

  /* Open, then fetch only if this panel has never been loaded for this user.
       Reopening a panel should cost nothing. */

  handleOpenLoginHistory(event) {
    this._triggerElement = event.target;
    this.activeModal = MODAL.LOGIN;
    if (this.loginState === STATE.EMPTY) this.loadLoginHistory();
  }

  handleOpenPermSets(event) {
    this._triggerElement = event.target;
    this.activeModal = MODAL.PERMSETS;
    if (this.permSetState === STATE.EMPTY) this.loadPermSets();
  }

  handleOpenGroups(event) {
    this._triggerElement = event.target;
    this.activeModal = MODAL.GROUPS;
    if (this.groupState === STATE.EMPTY) this.loadGroups();
  }

  handleLoginRetry() {
    this.loadLoginHistory();
  }
  handlePermSetRetry() {
    this.loadPermSets();
  }
  handleGroupRetry() {
    this.loadGroups();
  }

  /**
   * Open the trace for the row that asked for it. The row hands over the
   * detail it already has, so this costs no round trip and writes no second
   * audit row for what the admin experiences as one action.
   */
  /**
   * The detail is already on screen, so the trace reuses it. Refetching would
   * write a second GET_OBJECT_DETAIL row for what the admin experiences as one
   * look at one object, and the inspection log is the thing we sell.
   */
  handleExplain() {
    if (!this.objectDetail) return;
    this.traceApiName = this.selectedObjectApiName;
    this.traceLabel = this.selectedObjectLabel;
    this.traceDetail = this.objectDetail;
    this.traceCopied = false;
    this.activeModal = MODAL.TRACE;
  }

  /** Closing the trace just uncovers the columns, which never went away. */
  handleTraceClose() {
    this.activeModal = MODAL.NONE;
    this.traceApiName = undefined;
    this.traceLabel = undefined;
    this.traceDetail = undefined;
  }

  handleCopyTraceLink() {
    this.writeClipboard(this.traceShareLink);
    this.traceCopied = true;
  }

  handleRailRetry() {
    if (this.selectedAppId) this.loadAppObjects(this.selectedAppId);
  }

  /** Focus returns to the control that opened the modal, not the page top. */
  handleModalClose() {
    this.activeModal = MODAL.NONE;
    this.syncUrl();
    this._triggerElement?.focus?.();
  }

  async handleRefresh() {
    await refreshCache();
    if (this.selectedUserId) {
      await this.loadUser(this.selectedUserId, true);
    }
  }

  handleCopyLink() {
    this.writeClipboard(
      shareableLink({
        userId: this.selectedUserId,
        appId: this.selectedAppId,
        objectId: this.selectedObjectApiName ?? null,
        tab: null
      })
    );
    this.copied = true;
    clearTimeout(this._copyTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- Intentional UI timing operation.
    this._copyTimer = setTimeout(() => {
      this.copied = false;
    }, 2000);
  }

  /**
   * Clipboard access is not granted in every context an admin might run this
   * from, and a silent failure on a button labelled "copied" is worse than no
   * button. The catch leaves the label unchanged so nothing is claimed.
   */
  writeClipboard(text) {
    try {
      navigator.clipboard?.writeText(text);
    } catch {
      this.copied = false;
    }
  }

  disconnectedCallback() {
    clearTimeout(this._copyTimer);
    if (this._resizeHandler) {
      window.removeEventListener("resize", this._resizeHandler);
      this._resizeHandler = undefined;
    }
  }

  syncUrl() {
    writeState({
      userId: this.selectedUserId,
      appId: this.selectedAppId,
      objectId: this.selectedObjectApiName ?? null,
      tab: null
    });
  }
}
