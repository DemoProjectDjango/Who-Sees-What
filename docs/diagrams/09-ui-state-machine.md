# 09 — UI State Machine: WHO / WHERE / WHAT

Staged navigation in `permissionExplorer`. The accordion behaviour is deliberate, not decorative:
collapsing a completed stage keeps the answer — not the navigation — on screen.

```mermaid
stateDiagram-v2
    [*] --> Idle

    Idle: <b>Idle</b><br/>WHO open · WHERE locked · WHAT locked<br/>Org stats bar visible
    Idle --> Searching: administrator types

    Searching: <b>Searching</b><br/>peSearchInput debounced<br/>peStateWrapper shows peSkeleton
    Searching --> UserResults: results returned
    Searching --> SearchEmpty: no matches
    Searching --> SearchCapped: capReached = true
    SearchEmpty --> Searching: refine term
    SearchCapped --> Searching: refine term

    UserResults: <b>User results</b><br/>peListbox + pePaginator<br/>keyset cursors held in cursorStack
    UserResults --> Searching: change term or filters
    UserResults --> Resolving: select user

    Resolving: <b>Resolving</b><br/>resolveUser(userId)<br/>gate → audit → resolver → cache
    Resolving --> UserResolved: success
    Resolving --> ErrorState: NOT_AUTHORISED / NOT_FOUND / INACTIVE_USER

    UserResolved: <b>User resolved</b><br/><b>WHO collapses</b> · WHERE opens (apps)<br/>Summary header + granted-by panel<br/>Outdated-group warning if present
    UserResolved --> Resolving: refresh (forceRefresh = true)
    UserResolved --> Idle: clear user
    UserResolved --> AppSelected: select app

    AppSelected: <b>App selected</b><br/>WHERE splits: app picker collapses,<br/>object list opens<br/>Includes "access without a tab" section
    AppSelected --> UserResolved: change app
    AppSelected --> ObjectLoading: select object

    ObjectLoading: <b>Loading object detail</b><br/>peStateWrapper → peSkeleton
    ObjectLoading --> ObjectDetail: success
    ObjectLoading --> ErrorState: failure

    ObjectDetail: <b>WHAT — terminal</b><br/>Does <i>not</i> auto-collapse<br/>CRUD chips + field table + attribution<br/>URL now fully deep-linkable
    ObjectDetail --> ObjectLoading: select another object
    ObjectDetail --> AppSelected: change app
    ObjectDetail --> Resolving: change user
    ObjectDetail --> TraceOpen: explain this access
    ObjectDetail --> ModalOpen: login history / user list

    TraceOpen: <b>Access trace</b><br/>peAccessTrace overlay
    TraceOpen --> ObjectDetail: close

    ModalOpen: <b>Modal</b><br/>peModal · peLoginHistoryModal · peUserListModal
    ModalOpen --> ObjectDetail: close

    ErrorState: <b>Error</b><br/>Typed message + retryable flag<br/>Retry offered only when retryable
    ErrorState --> Resolving: retry (retryable = true)
    ErrorState --> Idle: dismiss

    note right of ObjectDetail
        Deep link: the URL encodes user,
        app and object throughout, so any
        state from UserResolved onward
        reproduces exactly in a new tab.
        Handled by peUtils/urlState.js.
    end note

    note right of UserResolved
        WHO and WHERE collapse on selection.
        WHAT is terminal and stays open —
        it holds the answer the user came for.
    end note
```

## Rules

- **Only WHO and WHERE collapse.** WHAT is the payload; collapsing it would hide the answer.
- Changing an upstream selection invalidates downstream state rather than leaving a stale field
  table attached to a different user.
- Every asynchronous region is wrapped in `peStateWrapper`, so loading, empty and error presentation
  is identical everywhere.
- Retry is offered only when the error carries `retryable = true`. Offering retry on
  `NOT_AUTHORISED` would waste the user's time.
