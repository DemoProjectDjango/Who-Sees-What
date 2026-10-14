/**
 * Reads back the audit trail that PEInspectionAuditLogger writes.
 *
 * The log has been append-only and invisible since it was introduced: every
 * inspection wrote a row, and nothing in the product ever showed one. That is
 * the wrong shape for the delegation argument - the trail is what makes handing
 * inspection rights to a non-admin defensible, and a trail nobody can read
 * defends nothing.
 *
 * Read-only by construction. There is no update or delete path here, and the
 * packaged permission set grants Read and Create on the object but not Edit or
 * Delete, so an inspector can see history without being able to rewrite it.
 */
public with sharing class PEInspectionLogService {

    /** Rows returned at once. Deliberately small: this is a recent-activity
     *  panel on a landing page, not a reporting surface. */
    private static final Integer DEFAULT_LIMIT = 25;
    private static final Integer MAX_LIMIT     = 200;

    /** Days covered by the activity chart and the top-inspector list. Two weeks
     *  shows a working rhythm without the chart becoming a hairline comb. */
    private static final Integer ACTIVITY_DAYS  = 14;
    private static final Integer TOP_INSPECTORS = 5;

    /** Ceiling on the bucketing read. Fourteen days of audit rows is normally
     *  far below this; the cap turns a pathological org into a truncated chart
     *  instead of a governor failure. */
    private static final Integer ACTIVITY_SCAN_CAP = 20000;

    /* Formatted server-side so no date crosses the boundary as a string the
       browser has to parse. See DayCount. */
    private static final Map<Integer, String> WEEKDAYS = new Map<Integer, String>{
        0 => 'Sun', 1 => 'Mon', 2 => 'Tue', 3 => 'Wed',
        4 => 'Thu', 5 => 'Fri', 6 => 'Sat'
    };
    private static final Map<Integer, String> MONTHS = new Map<Integer, String>{
        1 => 'Jan', 2 => 'Feb', 3 => 'Mar',  4 => 'Apr',  5 => 'May',  6 => 'Jun',
        7 => 'Jul', 8 => 'Aug', 9 => 'Sep', 10 => 'Oct', 11 => 'Nov', 12 => 'Dec'
    };

    /* ---------------------------------------------------------------
     * Result types
     * --------------------------------------------------------------- */

    /** One inspection event, flattened for display. */
    public class LogRow {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String action;
        @AuraEnabled public String detail;
        @AuraEnabled public Datetime inspectedAt;
        @AuraEnabled public Id inspectorId;
        @AuraEnabled public String inspectorName;
        @AuraEnabled public Id subjectId;
        @AuraEnabled public String subjectName;
    }

    /**
     * Inspections on one calendar day, for the activity chart.
     *
     * The labels are formatted here rather than in the browser. A Date crossing
     * the Apex-to-JavaScript boundary arrives as a date-only string, which
     * `new Date()` parses as UTC midnight and then renders in local time - so
     * every bar west of Greenwich was labelled with the previous day. Formatting
     * server-side removes the parse entirely.
     */
    public class DayCount {
        @AuraEnabled public Date day;
        @AuraEnabled public Integer total;
        /** Axis label, already formatted: "Mon 13". */
        @AuraEnabled public String label;
        /** Full label for the hover title: "Mon 13 Oct". */
        @AuraEnabled public String fullLabel;
        /** True for today's column, so the chart can mark the live edge. */
        @AuraEnabled public Boolean isToday = false;
    }

    /** Inspection volume by action type over the window. */
    public class ActionCount {
        @AuraEnabled public String action;
        @AuraEnabled public Integer total;
    }

    /** One person's inspection volume over the window. */
    public class InspectorCount {
        @AuraEnabled public Id inspectorId;
        @AuraEnabled public String inspectorName;
        @AuraEnabled public Integer total;
    }

    /** A page of inspection history plus the counts the panel header shows. */
    public class LogPage {
        @AuraEnabled public List<LogRow> rows = new List<LogRow>();
        /** Total rows readable by the running user, or null when the count failed. */
        @AuraEnabled public Integer totalCount;
        /** Rows written in the last 7 days, or null when the count failed. */
        @AuraEnabled public Integer last7Days;
        /** False when the running user cannot read the object at all. */
        @AuraEnabled public Boolean readable = true;
        /** Set when the panel has something to say about why it is empty. */
        @AuraEnabled public String notice;
        /** One entry per day in the activity window, zero-filled. */
        @AuraEnabled public List<DayCount> activity = new List<DayCount>();
        /** Busiest inspectors in the window, descending. */
        @AuraEnabled public List<InspectorCount> topInspectors = new List<InspectorCount>();
        /** Inspections inside the activity window. Summed in Apex, not the browser. */
        @AuraEnabled public Integer windowTotal = 0;
        /** The equivalent window immediately before this one, for the trend figure. */
        @AuraEnabled public Integer priorWindowTotal = 0;
        /** Volume by action type inside the window, descending. */
        @AuraEnabled public List<ActionCount> actionMix = new List<ActionCount>();
        /** True when the window held more rows than the bucketing query reads. */
        @AuraEnabled public Boolean activityTruncated = false;
        /** Distinct people who inspected anything inside the window. */
        @AuraEnabled public Integer distinctInspectors = 0;
        /** Distinct people who were inspected inside the window. */
        @AuraEnabled public Integer distinctSubjects = 0;
    }

    /* ---------------------------------------------------------------
     * Query
     * --------------------------------------------------------------- */

    /**
     * Most recent inspections first, optionally narrowed to one inspector or
     * one subject.
     *
     * WITH USER_MODE means a subscriber who has not granted FLS on the lookups
     * gets null names rather than an exception, so the panel degrades to
     * timestamps and actions instead of failing outright.
     *
     * @param inspectorId Filter to inspections performed by this user, or null for all.
     * @param subjectId Filter to inspections of this user, or null for all.
     * @param rowLimit Maximum rows to return; clamped to a sane range.
     * @return A page of inspection history, with readable set false when the object is not accessible.
     */
    // Four near-identical queries rather than one dynamic string: WITH USER_MODE
    // on a literal query is what enforces FLS at compile time, and assembling the
    // WHERE clause dynamically would give that up to save a few lines.
    @SuppressWarnings('PMD.CognitiveComplexity,PMD.CyclomaticComplexity')
    public static LogPage getRecent(Id inspectorId, Id subjectId, Integer rowLimit) {
        LogPage page = new LogPage();

        // Describe before querying: an org that never granted Read on the
        // object should get an explanation, not a stack trace.
        if (!Schema.SObjectType.PE_Inspection_Log__c.isAccessible()) {
            page.readable = false;
            page.notice =
                'You do not have read access to Inspection Log. ' +
                'Ask an administrator to grant it on the Who Sees What permission set.';
            return page;
        }

        Integer lim = clamp(rowLimit);
        List<PE_Inspection_Log__c> records;

        if (inspectorId != null && subjectId != null) {
            records = [
                SELECT Id, Action__c, Detail__c, Inspected_At__c,
                       Inspector_User__c, Inspector_User__r.Name,
                       Subject_User__c, Subject_User__r.Name
                FROM PE_Inspection_Log__c
                WHERE Inspector_User__c = :inspectorId AND Subject_User__c = :subjectId
                WITH USER_MODE
                ORDER BY Inspected_At__c DESC
                LIMIT :lim
            ];
        } else if (inspectorId != null) {
            records = [
                SELECT Id, Action__c, Detail__c, Inspected_At__c,
                       Inspector_User__c, Inspector_User__r.Name,
                       Subject_User__c, Subject_User__r.Name
                FROM PE_Inspection_Log__c
                WHERE Inspector_User__c = :inspectorId
                WITH USER_MODE
                ORDER BY Inspected_At__c DESC
                LIMIT :lim
            ];
        } else if (subjectId != null) {
            records = [
                SELECT Id, Action__c, Detail__c, Inspected_At__c,
                       Inspector_User__c, Inspector_User__r.Name,
                       Subject_User__c, Subject_User__r.Name
                FROM PE_Inspection_Log__c
                WHERE Subject_User__c = :subjectId
                WITH USER_MODE
                ORDER BY Inspected_At__c DESC
                LIMIT :lim
            ];
        } else {
            records = [
                SELECT Id, Action__c, Detail__c, Inspected_At__c,
                       Inspector_User__c, Inspector_User__r.Name,
                       Subject_User__c, Subject_User__r.Name
                FROM PE_Inspection_Log__c
                WITH USER_MODE
                ORDER BY Inspected_At__c DESC
                LIMIT :lim
            ];
        }

        for (PE_Inspection_Log__c rec : records) {
            page.rows.add(toRow(rec));
        }

        fillCounts(page);
        fillWindow(page);
        fillTopInspectors(page);

        if (page.rows.isEmpty() && String.isBlank(page.notice)) {
            page.notice = 'No inspections recorded yet.';
        }
        return page;
    }

    /**
     * Converts one logged inspection into its display row.
     *
     * @param rec Inspection log record read from the org.
     * @return Flattened row with lookup names resolved where FLS allows.
     */
    private static LogRow toRow(PE_Inspection_Log__c rec) {
        LogRow row = new LogRow();
        row.recordId    = rec.Id;
        row.action      = rec.Action__c;
        row.detail      = rec.Detail__c;
        row.inspectedAt = rec.Inspected_At__c;
        row.inspectorId = rec.Inspector_User__c;
        row.subjectId   = rec.Subject_User__c;

        // Null-safe on the relationship, not just the field: a lookup to a
        // deleted or unreadable user returns a null parent, and dereferencing
        // it is the classic way an audit panel dies on one bad row.
        row.inspectorName = rec.Inspector_User__r != null ? rec.Inspector_User__r.Name : null;
        row.subjectName   = rec.Subject_User__r != null ? rec.Subject_User__r.Name : null;
        return row;
    }

    /**
     * Adds the header counts, each independently optional.
     *
     * Same rule PEOrgStatsService learned: one count failing must not blank the
     * rows that already loaded successfully.
     *
     * @param page Page being populated, mutated in place.
     */
    // Suppressed: the totals intentionally span the whole object; a WHERE or
    // LIMIT would change the figure being reported.
    @SuppressWarnings('PMD.AvoidNonRestrictiveQueries')
    private static void fillCounts(LogPage page) {
        try {
            page.totalCount = [SELECT COUNT() FROM PE_Inspection_Log__c WITH USER_MODE];
        } catch (Exception e) {
            page.totalCount = null;
        }

        try {
            Datetime since = System.now().addDays(-7);
            page.last7Days = [
                SELECT COUNT() FROM PE_Inspection_Log__c
                WHERE Inspected_At__c >= :since
                WITH USER_MODE
            ];
        } catch (Exception e) {
            page.last7Days = null;
        }
    }

    /**
     * Everything the chart needs, bucketed from raw timestamps in one pass.
     *
     * Deliberately NOT a GROUP BY DAY_ONLY aggregate. That version returned a
     * flat zero chart in a live org: DAY_ONLY resolves the date in a timezone
     * that need not match the one Date.today() uses, so the aggregate keys and
     * the zero-fill keys described different days and never intersected. The
     * failure was silent - fourteen bars of zero above a table full of rows.
     *
     * Bucketing from `Datetime.date()` keeps one timezone for both sides of the
     * comparison, and a fortnight of audit rows is a small read. The cap exists
     * so a pathologically busy org degrades to a truncated chart rather than a
     * governor failure, and says so.
     *
     * @param page Page being populated, mutated in place.
     */
    private static void fillWindow(LogPage page) {
        try {
            Date startDay = Date.today().addDays(-(ACTIVITY_DAYS - 1));
            Datetime since = Datetime.newInstance(startDay, Time.newInstance(0, 0, 0, 0));

            Integer scanCap = ACTIVITY_SCAN_CAP;

            List<PE_Inspection_Log__c> window = [
                SELECT Inspected_At__c, Action__c,
                       Inspector_User__c, Subject_User__c
                FROM PE_Inspection_Log__c
                WHERE Inspected_At__c >= :since
                WITH USER_MODE
                ORDER BY Inspected_At__c DESC
                LIMIT :scanCap
            ];
            page.activityTruncated = window.size() == scanCap;

            Map<Date, Integer> byDay = new Map<Date, Integer>();
            Map<String, Integer> byAction = new Map<String, Integer>();

            // Counted from the same scan rather than two more aggregates. The
            // rows are already in memory; a COUNT_DISTINCT round trip for each
            // would double the query cost to learn something cheaper to tally.
            Set<Id> inspectors = new Set<Id>();
            Set<Id> subjects   = new Set<Id>();

            for (PE_Inspection_Log__c rec : window) {
                if (rec.Inspected_At__c == null) {
                    continue;
                }
                Date d = rec.Inspected_At__c.date();
                byDay.put(d, byDay.containsKey(d) ? byDay.get(d) + 1 : 1);

                String a = String.isBlank(rec.Action__c) ? 'UNKNOWN' : rec.Action__c;
                byAction.put(a, byAction.containsKey(a) ? byAction.get(a) + 1 : 1);

                if (rec.Inspector_User__c != null) {
                    inspectors.add(rec.Inspector_User__c);
                }
                // Null is normal here: license lookups and other org-wide
                // actions have no subject, and counting them would inflate the
                // figure with inspections that were never about a person.
                if (rec.Subject_User__c != null) {
                    subjects.add(rec.Subject_User__c);
                }
            }

            page.distinctInspectors = inspectors.size();
            page.distinctSubjects   = subjects.size();

            buildDays(page, startDay, byDay);
            buildActionMix(page, byAction);
            page.windowTotal = window.size();
        } catch (Exception e) {
            // The chart is the loudest thing on the page but not the load-bearing
            // one: empty lists hide it and leave the table intact.
            page.activity  = new List<DayCount>();
            page.actionMix = new List<ActionCount>();
        }

        fillPriorWindow(page);
    }

    /**
     * Expands the bucket map into one entry per day, zero-filled and labelled.
     *
     * Zero-filling matters: a chart that omits quiet days compresses the gaps
     * and makes sporadic use look continuous, which is the opposite of what an
     * audit view should show.
     *
     * @param page Page being populated, mutated in place.
     * @param startDay First day of the activity window.
     * @param byDay Inspection counts keyed by calendar day.
     */
    private static void buildDays(LogPage page, Date startDay, Map<Date, Integer> byDay) {
        Date today = Date.today();

        for (Integer i = 0; i < ACTIVITY_DAYS; i++) {
            Date d = startDay.addDays(i);

            DayCount dc  = new DayCount();
            dc.day       = d;
            dc.total     = byDay.containsKey(d) ? byDay.get(d) : 0;
            dc.isToday   = d == today;
            dc.label     = WEEKDAYS.get(dayOfWeek(d)) + ' ' + String.valueOf(d.day());
            dc.fullLabel = dc.label + ' ' + MONTHS.get(d.month());
            page.activity.add(dc);
        }
    }

    /**
     * Orders the action buckets by volume, descending.
     *
     * @param page Page being populated, mutated in place.
     * @param byAction Inspection counts keyed by action code.
     */
    private static void buildActionMix(LogPage page, Map<String, Integer> byAction) {
        // Insertion sort over a handful of action codes. A List<Comparable>
        // wrapper would be more machinery than seven entries deserve.
        List<ActionCount> ordered = new List<ActionCount>();
        for (String action : byAction.keySet()) {
            ActionCount ac = new ActionCount();
            ac.action = action;
            ac.total  = byAction.get(action);

            Integer at = 0;
            while (at < ordered.size() && ordered[at].total >= ac.total) {
                at++;
            }
            ordered.add(at, ac);
        }
        page.actionMix = ordered;
    }

    /**
     * The equivalent window immediately before this one, so the page can show a
     * direction rather than a bare number.
     *
     * @param page Page being populated, mutated in place.
     */
    private static void fillPriorWindow(LogPage page) {
        try {
            Date priorStart = Date.today().addDays(-(ACTIVITY_DAYS * 2 - 1));
            Date priorEnd   = Date.today().addDays(-(ACTIVITY_DAYS - 1));

            // `from` is a reserved word in Apex and cannot name a variable.
            Datetime windowOpen  = Datetime.newInstance(priorStart, Time.newInstance(0, 0, 0, 0));
            Datetime windowClose = Datetime.newInstance(priorEnd, Time.newInstance(0, 0, 0, 0));

            page.priorWindowTotal = [
                SELECT COUNT() FROM PE_Inspection_Log__c
                WHERE Inspected_At__c >= :windowOpen AND Inspected_At__c < :windowClose
                WITH USER_MODE
            ];
        } catch (Exception e) {
            page.priorWindowTotal = 0;
        }
    }

    /**
     * Busiest inspectors over the same window.
     *
     * Names come from a second query rather than a relationship field, because
     * a GROUP BY on a lookup cannot also select its parent's Name.
     *
     * @param page Page being populated, mutated in place.
     */
    private static void fillTopInspectors(LogPage page) {
        try {
            Date startDay = Date.today().addDays(-(ACTIVITY_DAYS - 1));
            Datetime since = Datetime.newInstance(startDay, Time.newInstance(0, 0, 0, 0));
            Integer topLimit = TOP_INSPECTORS;

            List<AggregateResult> rows = [
                SELECT Inspector_User__c insp, COUNT(Id) c
                FROM PE_Inspection_Log__c
                WHERE Inspected_At__c >= :since AND Inspector_User__c != null
                WITH USER_MODE
                GROUP BY Inspector_User__c
                ORDER BY COUNT(Id) DESC
                LIMIT :topLimit
            ];
            if (rows.isEmpty()) {
                return;
            }

            Set<Id> ids = new Set<Id>();
            for (AggregateResult ar : rows) {
                ids.add((Id) ar.get('insp'));
            }
            Map<Id, User> users = new Map<Id, User>([
                SELECT Id, Name FROM User WHERE Id IN :ids WITH USER_MODE
            ]);

            for (AggregateResult ar : rows) {
                Id inspectorId = (Id) ar.get('insp');
                InspectorCount ic = new InspectorCount();
                ic.inspectorId   = inspectorId;
                ic.total         = (Integer) ar.get('c');
                ic.inspectorName = users.containsKey(inspectorId)
                    ? users.get(inspectorId).Name
                    : null;
                page.topInspectors.add(ic);
            }
        } catch (Exception e) {
            page.topInspectors = new List<InspectorCount>();
        }
    }

    /**
     * Day of week as 0=Sunday, derived without formatting or timezone lookup.
     *
     * `Date.format()` would hand back a locale- and timezone-sensitive string,
     * which is exactly what this class is trying to avoid. Counting days from a
     * known Sunday is deterministic.
     *
     * @param d Date whose weekday index is needed.
     * @return 0 for Sunday through 6 for Saturday.
     */
    private static Integer dayOfWeek(Date d) {
        Date knownSunday = Date.newInstance(1900, 1, 7);
        Integer diff = Math.mod(knownSunday.daysBetween(d), 7);
        return diff < 0 ? diff + 7 : diff;
    }

    /**
     * Keeps the row limit inside a range the panel can actually render.
     *
     * @param requested Row limit asked for by the caller, possibly null or absurd.
     * @return Row limit between 1 and MAX_LIMIT.
     */
    private static Integer clamp(Integer requested) {
        if (requested == null || requested <= 0) {
            return DEFAULT_LIMIT;
        }
        return requested > MAX_LIMIT ? MAX_LIMIT : requested;
    }
}
