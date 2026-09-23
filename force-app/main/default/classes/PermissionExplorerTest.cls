/**
 * Tests for the pure-logic core: permission arithmetic, FLS classification,
 * cursor encoding, and query chunking.
 *
 * Deliberately weighted toward logic that needs no org state. Four assumptions
 * in this codebase turned out wrong during the first deploy — two Apex reserved
 * words, a muting type string, and a method that was written but never called.
 * All four were found by hand. These tests exist so the fifth is found here.
 */
@IsTest
// Whole class is pure-logic unit tests (applyGrant arithmetic, FLS describe
// classification, keyset cursor codec, SOQL chunking) plus the PEAccessGate
// subject-guards. None asserts a property of the running user's own context,
// and the USER_MODE queries would simply resolve different row sets for a runAs
// user, so there is no meaningful runAs to implement.
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
private class PermissionExplorerTest {

    /* ===============================================================
     * Permission arithmetic — union then subtract
     * =============================================================== */

    @IsTest
    static void grantIsUnionAcrossParents() {
        Id psA = fakeId(PermissionSet.SObjectType, 1);
        Id psB = fakeId(PermissionSet.SObjectType, 2);

        PEPermissionResolver.Resolved r = resolvedWith(new Set<Id>{ psA, psB });
        r.sourcesById.put(psA, new PEDto.Source(psA, 'Set A', 'permset'));
        r.sourcesById.put(psB, new PEDto.Source(psB, 'Set B', 'permset'));

        PEDto.Grant g = PEPermissionResolver.applyGrant(
            'PermissionsRead', 'Read', r,
            new Map<Id, Boolean>{ psA => false, psB => true },
            new Map<Id, Boolean>()
        );

        Assert.isTrue(g.granted, 'One parent granting is enough');
        Assert.isFalse(g.muted, 'Nothing was muted');
        Assert.areEqual(1, g.sources.size(), 'Only the granting parent is a source');
        Assert.areEqual('Set B', g.sources[0].label, 'Wrong parent credited');
    }

    @IsTest
    static void grantIsDeniedWhenNoParentGrants() {
        Id psA = fakeId(PermissionSet.SObjectType, 1);
        PEPermissionResolver.Resolved r = resolvedWith(new Set<Id>{ psA });

        PEDto.Grant g = PEPermissionResolver.applyGrant(
            'PermissionsEdit', 'Edit', r,
            new Map<Id, Boolean>{ psA => false },
            new Map<Id, Boolean>()
        );

        Assert.isFalse(g.granted, 'No parent grants it');
        Assert.isTrue(g.sources.isEmpty(), 'A denied grant has no sources');
    }

    @IsTest
    static void absentRowMeansNoAccessNotUnknown() {
        Id psA = fakeId(PermissionSet.SObjectType, 1);
        PEPermissionResolver.Resolved r = resolvedWith(new Set<Id>{ psA });

        // Empty map: the parent has no ObjectPermissions row at all.
        PEDto.Grant g = PEPermissionResolver.applyGrant(
            'PermissionsDelete', 'Delete', r,
            new Map<Id, Boolean>(),
            new Map<Id, Boolean>()
        );

        Assert.isFalse(g.granted,
            'A missing permission row means no access, never unknown');
    }

    @IsTest
    static void mutingSubtractsAGrantedPermission() {
        Id psA    = fakeId(PermissionSet.SObjectType, 1);
        Id muting = fakeId(PermissionSet.SObjectType, 9);

        PEPermissionResolver.Resolved r = resolvedWith(new Set<Id>{ psA });
        r.mutingParents.add(muting);
        r.sourcesById.put(psA, new PEDto.Source(psA, 'Set A', 'permset'));
        r.sourcesById.put(muting, new PEDto.Source(muting, 'Mute Me', 'muting'));

        PEDto.Grant g = PEPermissionResolver.applyGrant(
            'PermissionsRead', 'Read', r,
            new Map<Id, Boolean>{ psA => true },
            new Map<Id, Boolean>{ muting => true }
        );

        Assert.isFalse(g.granted,
            'A muted permission must not read as granted — this is the failure ' +
            'mode that produces confidently wrong answers');
        Assert.isTrue(g.muted, 'Must be flagged as muted, not merely absent');
        Assert.areEqual(2, g.sources.size(),
            'Both the granting and the muting parent matter to a revoke decision');
    }

    @IsTest
    static void mutingDoesNotInventAGrant() {
        Id psA    = fakeId(PermissionSet.SObjectType, 1);
        Id muting = fakeId(PermissionSet.SObjectType, 9);

        PEPermissionResolver.Resolved r = resolvedWith(new Set<Id>{ psA });
        r.mutingParents.add(muting);

        PEDto.Grant g = PEPermissionResolver.applyGrant(
            'PermissionsRead', 'Read', r,
            new Map<Id, Boolean>{ psA => false },
            new Map<Id, Boolean>{ muting => true }
        );

        Assert.isFalse(g.granted, 'Still denied');
        Assert.isFalse(g.muted,
            'Nothing was granted, so nothing was muted — flagging it would mislead');
    }

    @IsTest
    static void mutingDoesNotLeakAcrossPermissions() {
        Id psA    = fakeId(PermissionSet.SObjectType, 1);
        Id muting = fakeId(PermissionSet.SObjectType, 9);

        PEPermissionResolver.Resolved r = resolvedWith(new Set<Id>{ psA });
        r.mutingParents.add(muting);
        r.sourcesById.put(psA, new PEDto.Source(psA, 'Set A', 'permset'));

        PEDto.Grant edit = PEPermissionResolver.applyGrant(
            'PermissionsEdit', 'Edit', r,
            new Map<Id, Boolean>{ psA => true },
            new Map<Id, Boolean>{ muting => false }
        );

        Assert.isTrue(edit.granted, 'Muting Read must not affect Edit');
        Assert.isFalse(edit.muted, 'Edit was not muted');
    }

    /* ===============================================================
     * FLS classification — decides whether the field table tells the truth
     * =============================================================== */

    @IsTest
    static void recordIdIsNotFlsControllable() {
        PEFlsClassifier.Verdict v = classify('Account', 'Id');
        Assert.isTrue(v.notApplicable, 'Id is never FLS-controllable');
        Assert.isTrue(v.reason.containsIgnoreCase('Record Id'),
            'Reason should name the Id, got: ' + v.reason);
    }

    @IsTest
    static void nameFieldIsAlwaysReadable() {
        PEFlsClassifier.Verdict v = classify('Account', 'Name');
        Assert.isTrue(v.notApplicable, 'Name is always readable');
        Assert.isTrue(v.reason.containsIgnoreCase('Name field'),
            'Reason should name the Name field, got: ' + v.reason);
    }

    @IsTest
    static void auditFieldsAreLabelledAsAuditNotMasterDetail() {
        PEFlsClassifier.Verdict created = classify('Account', 'CreatedDate');
        Assert.isTrue(created.notApplicable, 'CreatedDate is not FLS-controllable');
        Assert.isTrue(created.reason.containsIgnoreCase('audit'),
            'CreatedDate should be labelled an audit field, got: ' + created.reason);

        // CreatedById is a non-nillable reference. A master-detail heuristic
        // based on nillability alone mislabels it, and a tool that explains
        // itself wrongly is barely better than one that says nothing.
        PEFlsClassifier.Verdict createdBy = classify('Account', 'CreatedById');
        Assert.isTrue(createdBy.notApplicable, 'CreatedById is not FLS-controllable');
        Assert.isFalse(createdBy.reason.containsIgnoreCase('master-detail'),
            'CreatedById is not a master-detail relationship, got: ' + createdBy.reason);
    }

    @IsTest
    static void ordinaryFieldIsFlsControllable() {
        PEFlsClassifier.Verdict v = classify('Account', 'Description');
        Assert.isFalse(v.notApplicable,
            'Description is an ordinary nillable field and must be reported as ' +
            'a real permission, not excused as structural');
        Assert.isNull(v.reason, 'An applicable field carries no reason');
    }

    /* ===============================================================
     * Keyset cursor — the pagination that has no 2000-row ceiling
     * =============================================================== */

    @IsTest
    static void cursorSurvivesARoundTrip() {
        Id lastId = fakeId(User.SObjectType, 7);
        String encoded = new PEKeysetCursor('Name', 'Rahman', lastId).encode();

        PEKeysetCursor back = PEKeysetCursor.decode(encoded);

        Assert.areEqual('Name', back.sortField, 'Sort field lost in transit');
        Assert.areEqual('Rahman', back.sortValue, 'Sort value lost in transit');
        Assert.areEqual(lastId, back.lastId,
            'The Id tiebreaker is what stops rows duplicating across pages');
    }

    @IsTest
    static void blankCursorMeansFirstPage() {
        Assert.isNull(PEKeysetCursor.decode(null), 'Null cursor is page one');
        Assert.isNull(PEKeysetCursor.decode(''), 'Empty cursor is page one');
    }

    @IsTest
    static void tamperedCursorIsRejected() {
        Boolean threw = false;
        try {
            PEKeysetCursor.decode('not-a-real-cursor');
        } catch (PermissionExplorerException e) {
            threw = true;
        }
        Assert.isTrue(threw,
            'The client must not be able to hand arbitrary values to a bound query');
    }

    @IsTest
    static void disallowedSortFieldIsRejected() {
        // Hand-built cursor naming a field outside the allow-list.
        String hostile = EncodingUtil.base64Encode(Blob.valueOf(
            '{"f":"ProfileId","v":"x","i":"' + fakeId(User.SObjectType, 1) + '"}'
        ));

        Boolean threw = false;
        try {
            PEKeysetCursor.decode(hostile);
        } catch (PermissionExplorerException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Only allow-listed sort fields may reach the ORDER BY');
        Assert.isFalse(PEKeysetCursor.isAllowedSort('ProfileId'), 'Allow-list breach');
        Assert.isTrue(PEKeysetCursor.isAllowedSort('Name'), 'Name must be sortable');
        Assert.isTrue(PEKeysetCursor.isAllowedSort('LastLoginDate'),
            'Recently-active is the default browse order');
    }

    /* ===============================================================
     * Chunking — what keeps a 200-permission-set org inside limits
     * =============================================================== */

    @IsTest
    static void chunkingSplitsAtTheBoundary() {
        List<Id> ids = new List<Id>();
        for (Integer i = 1; i <= 250; i++) {
            ids.add(fakeId(PermissionSet.SObjectType, i));
        }

        List<List<Id>> chunks = PESoqlChunker.chunk(ids, 100);

        Assert.areEqual(3, chunks.size(), 'Expected 100 + 100 + 50');
        Assert.areEqual(100, chunks[0].size(), 'First chunk full');
        Assert.areEqual(100, chunks[1].size(), 'Second chunk full');
        Assert.areEqual(50, chunks[2].size(), 'Remainder must not be dropped');

        Integer total = 0;
        for (List<Id> c : chunks) {
            total += c.size();
        }
        Assert.areEqual(250, total, 'No Id may be lost while chunking');
    }

    @IsTest
    static void chunkingHandlesExactMultiplesAndEmpty() {
        List<Id> exact = new List<Id>();
        for (Integer i = 1; i <= 200; i++) {
            exact.add(fakeId(PermissionSet.SObjectType, i));
        }
        Assert.areEqual(2, PESoqlChunker.chunk(exact, 100).size(),
            'An exact multiple must not produce a trailing empty chunk');

        Assert.isTrue(PESoqlChunker.chunk(new List<Id>(), 100).isEmpty(),
            'Empty input yields no chunks');
        Assert.isTrue(PESoqlChunker.chunk(new Set<Id>()).isEmpty(),
            'Empty set yields no chunks');
    }

    /* ===============================================================
     * Target-user guards — active only, enforced server-side
     * =============================================================== */

    @IsTest
    static void inactiveUserIsRejected() {
        User u = buildUser('pe.inactive@test.invalid');
        u.IsActive = false;
        insert u;

        String cause;
        try {
            PEAccessGate.assertInspectable(u.Id);
        } catch (PermissionExplorerException e) {
            cause = e.causeCode;
        }

        Assert.areEqual(PermissionExplorerException.INACTIVE_USER, cause,
            'The cause must be specific so the UI explains it instead of ' +
            'showing an empty result');
    }

    @IsTest
    static void activeUserIsAccepted() {
        User u = buildUser('pe.active@test.invalid');
        insert u;

        User found = PEAccessGate.assertInspectable(u.Id);
        Assert.areEqual(u.Id, found.Id, 'Active users are inspectable');
    }

    @IsTest
    static void missingUserIsNotFound() {
        String cause;
        try {
            PEAccessGate.assertInspectable(fakeId(User.SObjectType, 999));
        } catch (PermissionExplorerException e) {
            cause = e.causeCode;
        }
        Assert.areEqual(PermissionExplorerException.NOT_FOUND, cause,
            'NOT_FOUND and INACTIVE_USER need different messages to the admin');
    }

    /* ===============================================================
     * Error shape — the UI branches on cause, not on message text
     * =============================================================== */

    @IsTest
    static void errorInfoCarriesACause() {
        PermissionExplorerException e = PermissionExplorerException.build(
            PermissionExplorerException.CALLOUT_FAILED, 'Could not reach metadata', true
        );
        PEDto.ErrorInfo info = e.toInfo();

        Assert.areEqual(PermissionExplorerException.CALLOUT_FAILED, info.cause,
            'Cause must survive so the client can branch on it');
        Assert.isTrue(info.retryable, 'A callout failure is retryable');
        Assert.areEqual('Could not reach metadata', info.message, 'Message lost');
    }

    /* ===============================================================
     * Helpers
     * =============================================================== */

    private static PEPermissionResolver.Resolved resolvedWith(Set<Id> parents) {
        PEPermissionResolver.Resolved r = new PEPermissionResolver.Resolved();
        r.effectiveParents.addAll(parents);
        return r;
    }

    private static PEFlsClassifier.Verdict classify(String objectName, String fieldName) {
        Schema.DescribeFieldResult dfr = Schema.getGlobalDescribe()
            .get(objectName).getDescribe().fields.getMap()
            .get(fieldName).getDescribe();
        return PEFlsClassifier.classify(dfr);
    }

    private static User buildUser(String username) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' WITH USER_MODE LIMIT 1];
        return new User(
            FirstName = 'PE',
            LastName = 'Tester',
            Username = username,
            Email = username,
            Alias = 'petest',
            ProfileId = p.Id,
            TimeZoneSidKey = 'GMT',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = true
        );
    }

    /**
     * Synthetic Ids let the pure-logic tests run without touching the database.
     *
     * @param sot SObject type whose key prefix should make the fake Id look realistic.
     * @param index Numeric suffix used to keep generated test Ids distinct.
     * @return Synthetic Salesforce Id for resolver and grant logic tests.
     */
    private static Id fakeId(Schema.SObjectType sot, Integer index) {
        String suffix = String.valueOf(index);
        return sot.getDescribe().getKeyPrefix()
            + '0'.repeat(12 - suffix.length())
            + suffix;
    }
}
