# SQL Query Analysis

Slow or poorly performing queries are one of the biggest reasons for outages or poor user experience. While building new features or optimizing existing ones for scale, it becomes imperitive that we optimize how our data is stored and queried. To optimize our usage of databases, we need to understand how databases work and tune our queries.

## How does postgres decide a query plan?
When you execute a query, postgres can fetch the results in different ways (sequential scan, index scan, etc.). Postgres generates multiple plans and if feasible, examines each plan depending on postgres's [configuration parameters](https://www.postgresql.org/docs/current/runtime-config-query.html) and table's statistics which are gathered using ANALYZE. The plan which is expected to run the fastest is selected.

### Additional Resources
* [An Overview of the Various Scan Methods in PostgreSQL](https://severalnines.com/database-blog/overview-various-scan-methods-postgresql)
* [Planner Optimizer](https://www.postgresql.org/docs/devel/planner-optimizer.html)

## `EXPLAIN` vs `EXPLAIN ANALYZE`
`EXPLAIN` command can be used to see which plan has been decided by postgres to execute query. `EXPLAIN` just shows the plan but doesn't show how much time it actually takes. To know the time taken at each step of the plan, you can use `EXPLAIN ANALYZE`. `EXPLAIN ANALYZE` actually executes the query, so it should be used carefully.

> ⚠️ Using `EXPLAIN ANALYZE` with `INSERT`, `UPDATE` or `DELETE` will update your data. To safely try `EXPLAIN ANALYZE` with such queries, you can start a transaction (using `BEGIN`), use `EXPLAIN ANALYZE` and then `ROLLBACK` that transaction.

## Anatomy of an `EXPLAIN` plan
Running `EXPLAIN` on a query generates a query plan which is a tree of plan nodes. This is the query plan for a `SELECT` command on a table:

```sql
EXPLAIN SELECT * FROM tenk1;

                         QUERY PLAN
------------------------------------------------------------
 Seq Scan on tenk1  (cost=0.00..483.00 rows=7001 width=244)
```

In this output,
 * *cost*
   * *estimated startup cost* (0.00) - the time before that node of the plan can begin
   * *estimated total cost* (483.00) - total time taken assuming that plan node will be run to completion (actual cost might be low in case of `LIMIT`).
 * *rows* (7001) - estimated number of rows that will be returned by this plan node assuming that node will be run to completion (actual cost might be low in case of `LIMIT`).
 * *width* (244) - estimated average width of rows in bytes for this plan node

Cost and rows above are calculated based on postgres's [configuration parameters](https://www.postgresql.org/docs/current/runtime-config-query.html). You can tune these params (cpu_tuple_cost, random_page_cost, etc.) at runtime to test out changes before deploying them.

Since the generated plan is based on relatives costs so actual time taken might be quite different. You can run `ANALYZE` on a table to update postgresql's statistics for that table so that plans have better estimates.

Since the costs are relative, you can compare costs between different nodes to identify the areas for optimization.

I generally try to follow these rules to speed up queries:
 * No plan node is doing a Seq Scan. And in case its happening, you can create an index to speed that up. Sometimes if the table is small, postgres would do a sequential scan even if an index is present.
 * If your queries have multiple conditions, you might see bitmap scans or an index scan with a filter. In cases like these, it might be useful to have a multi-column index.

 ```sql
 EXPLAIN SELECT * FROM tenk1 WHERE unique1 < 100 AND unique2 > 9000 LIMIT 2;

                                     QUERY PLAN
-------------------------------------------------------------------​------------------
 Limit  (cost=0.29..14.48 rows=2 width=244)
   ->  Index Scan using tenk1_unique2 on tenk1  (cost=0.29..71.27 rows=10 width=244)
         Index Cond: (unique2 > 9000)
         Filter: (unique1 < 100)
```

Sometimes, the query plan can get really complicated to understand. In cases like this, you can use [pev2](https://explain.dalibo.com/).

### Additional Resources
* [Using Explain](https://www.postgresql.org/docs/current/using-explain.html)

## Index Types
There are different types of indexes avaialble and some might give good performance gains depending on the use-case. By default, postgres uses a btree index.

While creating an index, I try to follow these rules:
 * Don't create an index if you know its not going be used. Unnecessary indexes will slow down your writes.
 * `Multi-column indexes`: If your queries have multiple conditions, a [multi-column index](https://www.postgresql.org/docs/current/indexes-multicolumn.html) might be useful. The order of columns is really important here. Let's assume you have a table with the below structure with a btree index on (col1, col2).
 ```sql
                           Table "public.tbl1"
 Column |  Type   | Collation | Nullable |             Default              
--------+---------+-----------+----------+----------------------------------
 id     | integer |           | not null | nextval('tbl1_id_seq'::regclass)
 col1   | integer |           |          | 
 col2   | integer |           |          | 
Indexes:
    "tbl1_col1_col2_idx" btree (col1, col2)
```
If you make a query like:
   * `SELECT * FROM tbl1 WHERE col1 = 10 AND col2 = 20` - Index scan
   * `SELECT * FROM tbl1 WHERE col1 = 10` - Index scan
   * `SELECT * FROM tbl1 WHERE col2 = 20` - Sequential scan. Depends on the data distribution and the `WHERE` clause.
 * `Partial indexes`: If you know that a part of the `WHERE` clause would have a fixed condition. e.g. `WHERE active = TRUE AND col1 = ?` where `active = TRUE` is the only condition on `active` column in your queries, you can create a [partial index](https://www.postgresql.org/docs/current/indexes-partial.html). Partial indexes are smaller in size and are more performant as well.
 * Indexes on expressions: You can create an index on an expression as well (e.g. `lower(textcol1)`). If queries on a table has some expressions, it it's a good idea to create an index on that expression.

### Additional Resources
* [Index Types](https://www.postgresql.org/docs/current/indexes-types.html)
* [Get rid of your unused indexes!](https://www.cybertec-postgresql.com/en/get-rid-of-your-unused-indexes/)
* PostgresOpen 2019 Explain Plans And You: [Talk](https://www.youtube.com/watch?v=OO-CHEXAX4o) | [Slides](https://postgresql.us/events/pgopen2019/sessions/session/695/slides/31/ExplainPlansAndYouPostgresOpen2019.pdf)
* Explaining the Postgres Query Optimizer - Bruce Momjian: [Talk](https://www.youtube.com/watch?v=svqQzYFBPIo) | [Slides](https://momjian.us/main/writings/pgsql/optimizer.pdf)
