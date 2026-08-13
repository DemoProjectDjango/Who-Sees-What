/**
 * Opaque cursor for keyset pagination on the user column.
 *
 * SOQL OFFSET is capped at 2000, so page 41 at 50 rows/page throws
 * NUMBER_OUTSIDE_VALID_RANGE. Numbered pagination therefore cannot work in the
 * large orgs it would exist for. Keyset pagination has no ceiling.
 *
 * The sort key is never unique on its own, so (sortValue, Id) is the real key —
 * without the Id tiebreaker rows silently duplicate or vanish across page
 * boundaries, which is the bug that ships unnoticed.
 *
 * The client never sends raw bind values: it sends this encoded blob back, and
 * decode() validates it.
 */
public with sharing class PEKeysetCursor {

    public String sortField;    // 'Name' | 'LastLoginDate'
    public String sortValue;    // last row's value, ISO-8601 for datetimes
    public Id lastId;

    private static final Set<String> ALLOWED_SORTS = new Set<String>{ 'Name', 'LastLoginDate' };

    public PEKeysetCursor(String sortField, String sortValue, Id lastId) {
        this.sortField = sortField;
        this.sortValue = sortValue;
        this.lastId = lastId;
    }

    public String encode() {
        return EncodingUtil.base64Encode(Blob.valueOf(
            JSON.serialize(new Map<String, String>{
                'f' => sortField,
                'v' => sortValue,
                'i' => String.valueOf(lastId)
            })
        ));
    }

    public static PEKeysetCursor decode(String encoded) {
        if (String.isBlank(encoded)) return null;
        if (encoded.length() > PEConstants.CURSOR_MAX_LENGTH) {
            throw badCursor();
        }
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(
                EncodingUtil.base64Decode(encoded).toString()
            );
            String f = (String) raw.get('f');
            if (!ALLOWED_SORTS.contains(f)) throw badCursor();
            return new PEKeysetCursor(f, (String) raw.get('v'), (Id) raw.get('i'));
        } catch (PermissionExplorerException e) {
            throw e;
        } catch (Exception e) {
            throw badCursor();
        }
    }

    public static Boolean isAllowedSort(String field) {
        return ALLOWED_SORTS.contains(field);
    }

    private static PermissionExplorerException badCursor() {
        return PermissionExplorerException.build(
            PermissionExplorerException.UNKNOWN,
            'That page link is no longer valid. Start from the first page.',
            false
        );
    }
}