/**
 * Batches `ParentId IN :ids` filters. An org with 200 permission sets will
 * blow SOQL and heap limits on a single unbounded IN clause, and the failure
 * only shows up in exactly the large orgs the tool is for.
 */
public with sharing class PESoqlChunker {

    /**
     * Splits effective parent Ids into the product's standard SOQL batch size.
     *
     * @param ids Parent Ids collected by the permission resolver.
     * @return Ordered batches suitable for repeated permission metadata queries.
     */
    public static List<List<Id>> chunk(Set<Id> ids) {
        return chunk(new List<Id>(ids), PEConstants.PARENT_ID_CHUNK);
    }

    /**
     * Splits parent Ids into caller-sized batches for permission metadata queries.
     *
     * @param ids Parent Ids to bind into repeated SOQL IN clauses.
     * @param size Maximum number of Ids per batch.
     * @return Batches that keep large-org inspections under SOQL and heap limits.
     */
    public static List<List<Id>> chunk(List<Id> ids, Integer size) {
        List<List<Id>> out = new List<List<Id>>();
        if (ids == null || ids.isEmpty()) {
            return out;
        }
        List<Id> current = new List<Id>();
        for (Id i : ids) {
            current.add(i);
            if (current.size() == size) {
                out.add(current);
                current = new List<Id>();
            }
        }
        if (!current.isEmpty()) {
            out.add(current);
        }
        return out;
    }

    /**
     * Guard before a large loop of queries. Fails loudly, not mysteriously.
     *
     * @param plannedQueries Number of permission metadata queries the caller is about to run.
     */
    public static void assertQueryBudget(Integer plannedQueries) {
        Integer remaining = Limits.getLimitQueries() - Limits.getQueries();
        if (plannedQueries > remaining - 5) {
            throw PermissionExplorerException.build(
                PermissionExplorerException.LIMIT_EXCEEDED,
                'This org has too many permission sets to analyse in one request. ' +
                'Narrow the scope and try again.',
                false
            );
        }
    }
}
