# 08 — Entity Relationship

The one object this package creates, and the platform objects it reads.

## Packaged object

```mermaid
erDiagram
    USER ||--o{ PE_INSPECTION_LOG__C : "Inspector_User__c"
    USER ||--o{ PE_INSPECTION_LOG__C : "Subject_User__c"

    PE_INSPECTION_LOG__C {
        Id       Id                PK
        Text     Action__c         "RESOLVE_USER, OBJECT_DETAIL, …"
        Text     Detail__c         "app, object, filter context"
        DateTime Inspected_At__c
        Lookup   Inspector_User__c FK "who looked"
        Lookup   Subject_User__c   FK "who was looked at"
    }

    USER {
        Id       Id         PK
        Text     Name
        Text     Username
        Boolean  IsActive
        Id       ProfileId  FK
        Id       UserRoleId FK
        DateTime LastLoginDate
    }
```

Create and Read are granted. **Edit, Delete, View All and Modify All are withheld**, which is what
makes the trail worth keeping. See [ADR-0002](../adr/0002-custom-permission-gate-and-audit.md).

## Permission graph read from the platform

```mermaid
erDiagram
    USER ||--|| PROFILE : "ProfileId"
    PROFILE ||--|| PERMISSIONSET : "IsOwnedByProfile = true"
    USER ||--o{ PERMISSIONSETASSIGNMENT : "AssigneeId"
    PERMISSIONSETASSIGNMENT }o--|| PERMISSIONSET : "PermissionSetId"
    PERMISSIONSETASSIGNMENT }o--o| PERMISSIONSETGROUP : "PermissionSetGroupId"
    PERMISSIONSETGROUP ||--o{ PERMISSIONSETGROUPCOMPONENT : "contains"
    PERMISSIONSETGROUPCOMPONENT }o--|| PERMISSIONSET : "component or muting set"
    PERMISSIONSET ||--o{ OBJECTPERMISSIONS : "ParentId"
    PERMISSIONSET ||--o{ FIELDPERMISSIONS : "ParentId"
    PERMISSIONSET ||--o{ PERMISSIONSETTABSETTING : "ParentId — custom tabs only"
    PERMISSIONSET ||--o{ SETUPENTITYACCESS : "ParentId — custom permissions"

    PERMISSIONSET {
        Id      Id    PK
        Text    Label
        Text    Name
        Text    Type  "Regular | Group | Muting | Profile-owned"
        Id      ProfileId FK
    }
    PERMISSIONSETGROUP {
        Id   Id     PK
        Text MasterLabel
        Text Status "Updated | Updating | Outdated | Failed"
    }
    OBJECTPERMISSIONS {
        Id      ParentId FK
        Text    SobjectType
        Boolean PermissionsRead
        Boolean PermissionsCreate
        Boolean PermissionsEdit
        Boolean PermissionsDelete
        Boolean PermissionsViewAllRecords
        Boolean PermissionsModifyAllRecords
    }
    FIELDPERMISSIONS {
        Id      ParentId FK
        Text    SobjectType
        Text    Field
        Boolean PermissionsRead
        Boolean PermissionsEdit
    }
```

**`PermissionSet.Type = 'Muting'` is the single field the entire differentiator rests on.**
`PermissionSetGroup.Status` is the second — it determines whether the computed answer is also the
live answer.

## Licensing read from the platform

```mermaid
erDiagram
    USER }o--|| USERLICENSE : "via Profile.UserLicenseId"
    USER ||--o{ PERMISSIONSETLICENSEASSIGN : "AssigneeId"
    PERMISSIONSETLICENSEASSIGN }o--|| PERMISSIONSETLICENSE : "PermissionSetLicenseId"
    USER ||--o{ USERPACKAGELICENSE : "UserId"
    USERPACKAGELICENSE }o--|| PACKAGELICENSE : "PackageLicenseId"
    ORGANIZATION ||--o{ TENANTUSAGEENTITLEMENT : "usage entitlements"

    USERLICENSE {
        Id   Id PK
        Text Name
        Int  TotalLicenses
        Int  UsedLicenses
    }
    PERMISSIONSETLICENSE {
        Id   Id PK
        Text MasterLabel
        Int  TotalLicenses
        Int  UsedLicenses
    }
```

## Not represented

No queryable entity exists for per-user record type visibility, page layout assignment,
per-permission-set app visibility, or standard object tab visibility. These live only in Metadata API
representations. See [ADR-0007](../adr/0007-defer-record-types-to-metadata-api.md).
