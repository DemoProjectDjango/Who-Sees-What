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

    public class Filters {
        public String term;
        public Id profileId;
        public Id roleId;
        public String userType;
        public String sortField = 'Name';   // 'Name' | 'LastLoginDate'
    }

    /**
     * Browse defaults to LastLoginDate DESC. On a 5,000-user org, Name order
     * means the admin stares at everyone whose surname starts with A, while the
     * users they actually need skew heavily toward recently active ones.
     */
    public static PEDto.PagedResult search(Filters f, String encodedCursor, Integer pageSize) {
        PEDto.PagedResult result = new PEDto.PagedResult();
        result.pageSize = pageSize == null ? PEConstants.USER_PAGE_SIZE : pageSize;

        String sortField = PEKeysetCursor.isAllowedSort(f.sortField) ? f.sortField : 'Name';
        Boolean descending = sortField == 'LastLoginDate';
        PEKeysetCursor cursor = PEKeysetCursor.decode(encodedCursor);

        // Bind variables, all named — no string concatenation of user input.
        String term      = String.isBlank(f.term) ? null : '%' + f.term.trim() + '%';
        Id profileId     = f.profileId;
        Id roleId        = f.roleId;
        String userType  = f.userType;
        Integer fetchSize = result.pageSize + 1;   // +1 tells us hasMore without COUNT()

        List<String> clauses = new List<String>{ 'IsActive = true' };
        if (term != null) {
            clauses.add('(Name LIKE :term OR Username LIKE :term OR Email LIKE :term OR Alias LIKE :term)');
        }
        if (profileId != null) clauses.add('ProfileId = :profileId');
        if (roleId != null)    clauses.add('UserRoleId = :roleId');
        if (userType != null)  clauses.add('UserType = :userType');

        if (cursor != null) {
            clauses.add(keysetPredicate(sortField, descending));
        }

        String direction = descending ? 'DESC NULLS LAST' : 'ASC NULLS LAST';
        String soql =
            'SELECT Id, Name, Username, Email, Profile.Name, UserRole.Name, LastLoginDate ' +
            'FROM User WHERE ' + String.join(clauses, ' AND ') +
            ' ORDER BY ' + sortField + ' ' + direction + ', Id ASC' +
            ' LIMIT :fetchSize';

        // Bound values referenced by the dynamic string.
        String cursorValue = cursor == null ? null : cursor.sortValue;
        Datetime cursorDate = parseDatetime(cursorValue);
        Id cursorId = cursor == null ? null : cursor.lastId;

        List<User> rows = Database.query(soql);

        result.hasMore = rows.size() > result.pageSize;
        if (result.hasMore) rows.remove(rows.size() - 1);

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
        result.capReached = term != null && result.hasMore;

        return result;
    }

    /**
     * The Id tiebreaker is mandatory: the sort value is never unique, and
     * without it rows duplicate or vanish across page boundaries.
     */
    private static String keysetPredicate(String sortField, Boolean descending) {
        String op = descending ? '<' : '>';
        String valueBind = sortField == 'Name' ? ':cursorValue' : ':cursorDate';
        return '(' + sortField + ' ' + op + ' ' + valueBind +
               ' OR (' + sortField + ' = ' + valueBind + ' AND Id > :cursorId))';
    }

    private static Datetime parseDatetime(String iso) {
        if (String.isBlank(iso)) return null;
        try { return (Datetime) JSON.deserialize('"' + iso + '"', Datetime.class); }
        catch (Exception e) { return null; }
    }

    /** Frozen state for the summary header. One extra query, only on selection. */
    public static Boolean isFrozen(Id userId) {
        List<UserLogin> logins = [
            SELECT IsFrozen FROM UserLogin WHERE UserId = :userId LIMIT 1
        ];
        return !logins.isEmpty() && logins[0].IsFrozen;
    }

    /** Filter picklists for the column header. Cached org-wide; identical for every admin. */
    public static Map<String, Object> filterOptions() {
        Object cached = PECacheManager.orgGet('userFilterOptions');
        if (cached != null) return (Map<String, Object>) cached;

        List<Map<String, String>> profiles = new List<Map<String, String>>();
        for (Profile p : [SELECT Id, Name FROM Profile ORDER BY Name LIMIT 1000]) {
            profiles.add(new Map<String, String>{ 'value' => p.Id, 'label' => p.Name });
        }
        List<Map<String, String>> roles = new List<Map<String, String>>();
        for (UserRole r : [SELECT Id, Name FROM UserRole ORDER BY Name LIMIT 1000]) {
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