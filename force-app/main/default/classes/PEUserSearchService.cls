/**
 * Column 1 queries. Active users only, enforced here rather than in the UI —
 * a filter that only exists in the client is not a filter.
 *
 * Frozen users stay in scope: freezing lives on UserLogin.IsFrozen, not
 * User.IsActive, and a frozen user is a common reason to open this tool.
 *
 * Pagination is keyset, not OFFSET. See PEKeysetCursor for why.
 */
public with sharing class PEUserSearchService {

    /** User column filter state supplied by the LWC before building the keyset search query. */
    public class Filters {
        public String term;
        public Id profileId;
        public Id roleId;
        public String userType;
        public String sortField = 'Name';   // 'Name' | 'LastLoginDate'
    }

    // ------------------------------------------------------------------
    // Query fragments.
    //
    // Every fragment below is a compile-time constant. No user-supplied
    // value is ever concatenated into the query string — filters are
    // applied by CHOOSING which constant to append, and all values reach
    // the query through the named bind map passed to queryWithBinds.
    //
    // Keeping these as `final` constants rather than inline literals is
    // deliberate: it makes the "no interpolation" property checkable by
    // reading the declarations, rather than by tracing the builder.
    // ------------------------------------------------------------------
    private static final String SELECT_CLAUSE =
        'SELECT Id, Name, Username, Email, Profile.Name, UserRole.Name, LastLoginDate FROM User';
    private static final String BASE_FILTER   = ' WHERE IsActive = true';
    private static final String TERM_FILTER   =
        ' AND (Name LIKE :term OR Username LIKE :term OR Email LIKE :term OR Alias LIKE :term)';
    private static final String PROFILE_FILTER = ' AND ProfileId = :profileId';
    private static final String ROLE_FILTER    = ' AND UserRoleId = :roleId';
    private static final String TYPE_FILTER    = ' AND UserType = :userType';
    private static final String CURSOR_LAST_LOGIN_DESC    =
        ' AND (LastLoginDate < :cursorDate OR (LastLoginDate = :cursorDate AND Id > :cursorId))';
    private static final String CURSOR_NAME_ASC     =
        ' AND (Name > :cursorValue OR (Name = :cursorValue AND Id > :cursorId))';
    private static final String ORDER_LAST_LOGIN_DESC     = ' ORDER BY LastLoginDate DESC NULLS LAST, Id ASC';
    private static final String ORDER_NAME_ASC      = ' ORDER BY Name ASC NULLS LAST, Id ASC';
    private static final String LIMIT_CLAUSE   = ' LIMIT :fetchSize';

    /**
     * Browse defaults to LastLoginDate DESC. On a 5,000-user org, Name order
     * means the admin stares at everyone whose surname starts with A, while the
     * users they actually need skew heavily toward recently active ones.
     *
     * Injection safety, stated here because the query is assembled rather than
     * literal — no suppression is needed and none should be added:
     *
     *  - The string is built exclusively from the private static final constants
     *    above. Filters are applied by CHOOSING which constant to append; no
     *    user-supplied value is ever concatenated into it.
     *  - Every value reaches the database through the named bind map passed to
     *    Database.queryWithBinds, never through the string.
     *  - The one identifier that varies is the sort column, and it is not taken
     *    from input either: sortField is validated by
     *    PEKeysetCursor.isAllowedSort, falls back to 'Name', and the sort is
     *    then applied by selecting between two constant fragments rather than
     *    by interpolation. PermissionExplorerTest.disallowedSortFieldIsRejected
     *    asserts the allowlist.
     *  - The query runs in AccessLevel.USER_MODE, so object and field
     *    permissions are enforced for the running user.
     *
     * If this ever moves back to Database.query(String), the analyser will flag
     * it and it should be treated as a real finding, not suppressed.
     *
     * @param f Filter selections from the column header
     * @param encodedCursor Opaque keyset cursor from the previous page, or null for the first page
     * @param pageSize Requested page size, or null for the default
     * @return PEDto.PagedResult one page of matching users plus the cursor for the next
     */
    public static PEDto.PagedResult search(Filters f, String encodedCursor, Integer pageSize) {
        PEDto.PagedResult result = new PEDto.PagedResult();
        result.pageSize = pageSize == null ? PEConstants.USER_PAGE_SIZE : pageSize;

        String sortField = PEKeysetCursor.isAllowedSort(f.sortField) ? f.sortField : 'Name';
        // Field and direction travel together. Selecting on the field rather than a
        // derived boolean means a future third sort option cannot pair the wrong
        // cursor predicate with the wrong ORDER BY.
        Boolean byLastLogin = sortField == 'LastLoginDate';
        PEKeysetCursor cursor = PEKeysetCursor.decode(encodedCursor);

        String cursorValue = cursor == null ? null : cursor.sortValue;

        // Every value the query can see, by name. Nothing else is bound.
        Map<String, Object> binds = new Map<String, Object>{
            'term'        => String.isBlank(f.term) ? null : '%' + f.term.trim() + '%',
            'profileId'   => f.profileId,
            'roleId'      => f.roleId,
            'userType'    => f.userType,
            'cursorValue' => cursorValue,
            'cursorDate'  => parseDatetime(cursorValue),
            'cursorId'    => cursor == null ? null : cursor.lastId,
            'fetchSize'   => result.pageSize + 1   // +1 tells us hasMore without COUNT()
        };

        String soql = SELECT_CLAUSE + BASE_FILTER;
        if (binds.get('term') != null) {
            String trimmedTerm = f.term.trim();
            List<String> rawTokens = trimmedTerm.split('\\s+');
            List<String> tokenClauses = new List<String>();
            for (Integer i = 0; i < rawTokens.size() && i < 4; i++) {
                String tok = rawTokens[i].trim();
                if (String.isNotBlank(tok)) {
                    String key = 'tok' + i;
                    binds.put(key, '%' + tok + '%');
                    tokenClauses.add('(Name LIKE :' + key + 
                                     ' OR Username LIKE :' + key + 
                                     ' OR Email LIKE :' + key + 
                                     ' OR Alias LIKE :' + key + 
                                     ' OR Profile.Name LIKE :' + key + 
                                     ' OR UserRole.Name LIKE :' + key + ')');
                }
            }

            String compact = trimmedTerm.replaceAll('\\s+', '');
            if (compact != trimmedTerm && String.isNotBlank(compact)) {
                binds.put('compact', '%' + compact + '%');
                soql += ' AND ((' + String.join(tokenClauses, ' AND ') + ') OR Username LIKE :compact OR Email LIKE :compact)';
            } else if (!tokenClauses.isEmpty()) {
                soql += ' AND (' + String.join(tokenClauses, ' AND ') + ')';
            } else {
                soql += TERM_FILTER;
            }
        }
        if (f.profileId != null) {
            soql += PROFILE_FILTER;
        }
        if (f.roleId != null) {
            soql += ROLE_FILTER;
        }
        if (f.userType != null) {
            soql += TYPE_FILTER;
        }
        if (cursor != null) {
            soql += byLastLogin ? CURSOR_LAST_LOGIN_DESC : CURSOR_NAME_ASC;
        }
        soql += byLastLogin ? ORDER_LAST_LOGIN_DESC : ORDER_NAME_ASC;
        soql += LIMIT_CLAUSE;

        List<User> rows = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);

        result.hasMore = rows.size() > result.pageSize;
        if (result.hasMore) {
            rows.remove(rows.size() - 1);
        }
        for (User u : rows) {
            PEDto.UserRow r = new PEDto.UserRow();
            r.userId      = u.Id;
            r.name        = u.Name;
            r.username    = u.Username;
            r.profileName = u.Profile != null ? u.Profile.Name : null;
            r.roleName    = u.UserRole != null ? u.UserRole.Name : null;
            r.lastLogin   = u.LastLoginDate;
            result.records.add(r);
        }

        if (result.hasMore && !rows.isEmpty()) {
            User last = rows[rows.size() - 1];
            String lastValue = sortField == 'Name'
                ? last.Name
                : (last.LastLoginDate == null ? null : last.LastLoginDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
            result.nextCursor = new PEKeysetCursor(sortField, lastValue, last.Id).encode();
        }

        // Searching is not a browse. Past the cap, refining beats paging.
        result.capReached = binds.get('term') != null && result.hasMore;

        return result;
    }

    private static Datetime parseDatetime(String iso) {
        if (String.isBlank(iso)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Frozen state for the summary header. One extra query, only on selection.
     *
     * @param userId Id of the User to check
     * @return Boolean true if the user's login is frozen, false otherwise
     */
    public static Boolean isFrozen(Id userId) {
        List<UserLogin> logins = [
            SELECT IsFrozen FROM UserLogin WHERE UserId = :userId WITH USER_MODE LIMIT 1
        ];
        return !logins.isEmpty() && logins[0].IsFrozen;
    }

    /**
     * Filter picklists for the column header. Cached org-wide; identical for every admin.
     *
     * @return Map<String, Object> containing 'profiles' and 'roles' lists for the UI filters
     */
    public static Map<String, Object> filterOptions() {
        Object cached = PECacheManager.orgGet('userFilterOptions');
        if (cached != null) {
            return (Map<String, Object>) cached;
        }

        List<Map<String, String>> profiles = new List<Map<String, String>>();
        for (Profile p : [SELECT Id, Name FROM Profile WITH USER_MODE ORDER BY Name LIMIT 1000]) {
            profiles.add(new Map<String, String>{ 'value' => p.Id, 'label' => p.Name });
        }
        List<Map<String, String>> roles = new List<Map<String, String>>();
        for (UserRole r : [SELECT Id, Name FROM UserRole WITH USER_MODE ORDER BY Name LIMIT 1000]) {
            roles.add(new Map<String, String>{ 'value' => r.Id, 'label' => r.Name });
        }

        Map<String, Object> options = new Map<String, Object>{
            'profiles' => profiles,
            'roles'    => roles
        };
        PECacheManager.orgPut('userFilterOptions', options, 3600);
        return options;
    }
}
