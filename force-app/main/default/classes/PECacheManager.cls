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
 *
 * The four cache catch blocks below name their exception `ignored`. Every one
 * is a considered fall-through to localFallback, not a swallowed error: a
 * missing partition or a rejected key must degrade to no-cache, never fail an
 * inspection. The name is what tells a reader — and PMD — that this is the
 * intent rather than an oversight.
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

    /** True when at least one Platform Cache partition is available for permission inspection caching. */
    public static Boolean cacheAvailable {
        get { return getOrgPartition() != null || getSessionPartition() != null; }
    }

    /* ----------------------------- version token ----------------------------- */

    /**
     * Every session-scoped key is suffixed with this, so a bump invalidates all.
     *
     * @return Current org-wide cache version token used to separate stale permission inspection results.
     */
    public static String versionToken() {
        Object v = orgGet(VERSION_KEY);
        if (v == null) {
            String fresh = newToken();
            orgPut(VERSION_KEY, fresh, 86400);
            return fresh;
        }
        return (String) v;
    }

    /**
     * Called by the refresh button.
     *
     * @return Fresh version token that forces admins' later inspections to rebuild cached resolver data.
     */
    public static String bumpVersionToken() {
        String fresh = newToken();
        orgPut(VERSION_KEY, fresh, 86400);
        return fresh;
    }

    private static String newToken() {
        return String.valueOf(System.currentTimeMillis());
    }

    /* ----------------------------- org partition ----------------------------- */

    /**
     * Reads org-scoped cache data used across permission inspection sessions.
     *
     * @param key Logical cache key before Platform Cache-safe normalization.
     * @return Cached value, or the transaction-local fallback value when Platform Cache is unavailable.
     */
    public static Object orgGet(String key) {
        String k = safeKey(key);
        Cache.OrgPartition p = getOrgPartition();
        if (p != null) {
            try {
                return p.get(k);
            } catch (Exception ignored) {
                /* Partition present but the read failed: fall through to localFallback. */
            }
        }
        return localFallback.get('org:' + k);
    }

    /**
     * Stores org-scoped cache data so repeated admin inspections can reuse expensive resolver output.
     *
     * @param key Logical cache key before Platform Cache-safe normalization.
     * @param value Value to cache.
     * @param ttlSeconds Platform Cache time to live in seconds when a partition is available.
     */
    public static void orgPut(String key, Object value, Integer ttlSeconds) {
        String k = safeKey(key);
        Cache.OrgPartition p = getOrgPartition();
        if (p != null) {
            try {
                p.put(k, value, ttlSeconds);
                return;
            } catch (Exception ignored) {
                /* Write rejected, most often zero capacity: fall through to localFallback. */
            }
        }
        localFallback.put('org:' + k, value);   // transaction-scoped only
    }

    /* --------------------------- session partition --------------------------- */

    /**
     * Reads session-scoped cache data tied to the current version token.
     *
     * @param key Logical cache key before versioning and Platform Cache-safe normalization.
     * @return Cached session value for the current token, or transaction-local fallback data.
     */
    public static Object sessionGet(String key) {
        String k = safeKey(key + '_' + versionToken());
        Cache.SessionPartition p = getSessionPartition();
        if (p != null) {
            try {
                return p.get(k);
            } catch (Exception ignored) {
                /* Partition present but the read failed: fall through to localFallback. */
            }
        }
        return localFallback.get('ses:' + k);
    }

    /**
     * Stores session-scoped permission inspection data under the current version token.
     *
     * @param key Logical cache key before versioning and Platform Cache-safe normalization.
     * @param value Value to cache for the current admin session.
     * @param ttlSeconds Platform Cache time to live in seconds when a partition is available.
     */
    public static void sessionPut(String key, Object value, Integer ttlSeconds) {
        String k = safeKey(key + '_' + versionToken());
        Cache.SessionPartition p = getSessionPartition();
        if (p != null) {
            try {
                p.put(k, value, ttlSeconds);
                return;
            } catch (Exception ignored) {
                /* Write rejected, most often zero capacity: fall through to localFallback. */
            }
        }
        localFallback.put('ses:' + k, value);
    }

    /**
     * Platform Cache keys are alphanumeric only, max 50 chars.
     *
     * @param raw Product cache key that may include separators or IDs.
     * @return Platform Cache-safe key preserving the most specific suffix of long values.
     */
    private static String safeKey(String raw) {
        String cleaned = raw.replaceAll('[^a-zA-Z0-9]', '');
        return cleaned.length() > 50 ? cleaned.substring(cleaned.length() - 50) : cleaned;
    }
}