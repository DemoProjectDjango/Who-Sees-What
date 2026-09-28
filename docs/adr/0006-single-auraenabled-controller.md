# ADR-0006: One `@AuraEnabled` controller as the sole LWC-facing surface

- **Status:** Accepted
- **Date:** Project inception

## Context

`@AuraEnabled` methods are the package's remotely-invocable surface. Anything exposed there can be
called directly, bypassing the UI entirely. Spreading that surface across several service classes
means the authorisation check must be remembered in several places — and forgetting it once is a
security finding, not a bug.

The codebase has roughly twenty LWC components and eight domain services.

## Decision

`PermissionExplorerController` is the **only** class with `@AuraEnabled` methods, and the only class
LWCs may import from. Every method follows the same shape:

```apex
@AuraEnabled
public static PEDto.Something doThing(Id userId, ...) {
    try {
        PEAccessGate.assertAuthorisedAndLog('ACTION', userId, detail);
        User u = PEAccessGate.assertInspectable(userId);
        // delegate to a service, map to a DTO
    } catch (Exception e) {
        throw toAura(e);
    }
}
```

Domain services contain no `@AuraEnabled` members and are never imported by a component. Errors are
funnelled through a single `toAura` mapper producing a user-facing message and a `retryable` flag.

Only `getFilterOptions` is `cacheable=true`, because it returns org-shaped reference data rather than
user-specific access.

## Consequences

**Positive**

- The security review surface is one file. "Where is authorisation enforced?" has one answer.
- Consistent error contract across every call.
- Domain services stay free of Aura-serialisation concerns, so they can return richer internal types.
- Adding a method has an unambiguous checklist.

**Negative**

- The controller grows with the feature set and must be kept thin — gate, delegate, map, nothing
  more. Query logic in the controller is a review rejection.
- Every new capability touches one shared file, which raises merge-conflict likelihood. Acceptable
  at this team size.
