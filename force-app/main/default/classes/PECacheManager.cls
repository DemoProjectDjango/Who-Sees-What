/**
 * Platform Cache access with a real no-cache fallback.
 *
 * A subscriber org may have zero cache allocation — Professional Edition
 * generally has none. Since the resolver is the expensive computation the
 * cache exists to avoid, the fallback path has to work correctly and be
 * performance-tested, not just compile.
 *
 * Refresh bumps a version token rather than clearing the partition, so one
 * admin refreshing does not cost every other admin their warm cache.
 */
public with sharing class PECacheManager {

    private static final String VERSION_KEY = 'orgVersionToken';
    private static Map<String, Object> localFallback = new Map<String, Object>();

    // Backing fields plus lazy getters. A static property whose getter reads
    // itself recurses forever, so partitions are resolved through methods.
    private static Cache.OrgPartition orgPart;
    private static Boolean orgPartResolved = false;
    private static Cache.SessionPartition sessionPart;
    private static Boolean sessionPartResolved = false;

    private static Cache.OrgPartition getOrgPartition() {
        if (!orgPartResolved) {
            orgPartResolved = true;
            try {
                orgPart = Cache.Org.getPartition('local.' + PEConstants.CACHE_ORG_PARTITION);
            } catch (Exception e) {
                orgPart = null;   // no allocation in this subscriber org
            }
        }
        return orgPart;
    }

    private static Cache.SessionPartition getSessionPartition() {
        if (!sessionPartResolved) {
            sessionPartResolved = true;
            try {
                sessionPart = Cache.Session.getPartition('local.' + PEConstants.CACHE_SESSION_PARTITION);
            } catch (Exception e) {
                sessionPart = null;
            }
        }
        return sessionPart;
    }

    public static Boolean cacheAvailable {
        get { return getOrgPartition() != null || getSessionPartition() != null; }
    }

    /* ----------------------------- version token ----------------------------- */

    /** Every session-scoped key is suffixed with this, so a bump invalidates all. */
    public static String versionToken() {
        Object v = orgGet(VERSION_KEY);
        if (v == null) {
            String fresh = newToken();
            orgPut(VERSION_KEY, fresh, 86400);
            return fresh;
        }
        return (String) v;
    }

    /** Called by the refresh button. */
    public static String bumpVersionToken() {
        String fresh = newToken();
        orgPut(VERSION_KEY, fresh, 86400);
        return fresh;
    }

    private static String newToken() {
        return String.valueOf(System.currentTimeMillis());
    }

    /* ----------------------------- org partition ----------------------------- */

    public static Object orgGet(String key) {
        String k = safeKey(key);
        Cache.OrgPartition p = getOrgPartition();
        if (p != null) {
            try { return p.get(k); } catch (Exception e) { /* fall through */ }
        }
        return localFallback.get('org:' + k);
    }

    public static void orgPut(String key, Object value, Integer ttlSeconds) {
        String k = safeKey(key);
        Cache.OrgPartition p = getOrgPartition();
        if (p != null) {
            try { p.put(k, value, ttlSeconds); return; } catch (Exception e) { /* fall through */ }
        }
        localFallback.put('org:' + k, value);   // transaction-scoped only
    }

    /* --------------------------- session partition --------------------------- */

    public static Object sessionGet(String key) {
        String k = safeKey(key + '_' + versionToken());
        Cache.SessionPartition p = getSessionPartition();
        if (p != null) {
            try { return p.get(k); } catch (Exception e) { /* fall through */ }
        }
        return localFallback.get('ses:' + k);
    }

    public static void sessionPut(String key, Object value, Integer ttlSeconds) {
        String k = safeKey(key + '_' + versionToken());
        Cache.SessionPartition p = getSessionPartition();
        if (p != null) {
            try { p.put(k, value, ttlSeconds); return; } catch (Exception e) { /* fall through */ }
        }
        localFallback.put('ses:' + k, value);
    }

    /** Platform Cache keys are alphanumeric only, max 50 chars. */
    private static String safeKey(String raw) {
        String cleaned = raw.replaceAll('[^a-zA-Z0-9]', '');
        return cleaned.length() > 50 ? cleaned.substring(cleaned.length() - 50) : cleaned;
    }
}