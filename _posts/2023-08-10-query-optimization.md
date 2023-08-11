---
layout: post
title: "Speeding Up Massive PostgreSQL Joins with Common Table Expressions"
excerpt: "Instead, let's structure the query as a Common Table Expression and leverage the power of doing significantly less work to make things go faster. Using a CTE instead of a naive full table join cuts down our query time from 12 seconds to ~0.12 seconds!"
---

I've been continuing to work on a growing [series of services](https://github.com/ericvolp12/bsky-experiments) that archive, analyze, and represent data from a social network.

This network creates text-based posts at a rate of around 400,000 posts per day, and I've been feeding the posts through different ML models to try and gauge the broad sentiment of the network and help find posters that spread good vibes.

### Sentiment Analysis

Sentiment Analysis using newer Transformer models like [BERT](https://arxiv.org/abs/1810.04805) has improved in accuracy significantly in recent years.

On an individual post level, especially for brief text, BERT-based models don't have a great degree of accuracy. However on a large scale these models can provide a broad measure of general sentiment on a social network.

I've been making use of the [RoBERTa](https://huggingface.co/cardiffnlp/twitter-roberta-base-sentiment) model trained on a dataset of ~58 Million Tweets to gauge the disposition of users on [Bluesky](https://bsky.app/) over the past few months.

### Backfilling Blues

This week I pivoted my data schema for my [ATProto](https://atproto.com/) indexing tools and needed to backfill the entire history of posts.

I altered my schema to keep sentiment analysis results in a separate table from general post metadata, which seemed like a good time to go back and re-run sentiment analysis on the entire network of around 22 million posts.

I now have a `posts` table and a `post_sentiments` table, both with > 22,000,000 posts. To process sentiment, I need to walk the `post_sentiments` table to find unprocessed posts and join with the `posts` table to get the `post.content` for analysis.

## The Simple Approach

To join these two tables, a standard approach to SQL would encourage you to write a query as follows:

```sql
SELECT s.*,
    p.content
FROM post_sentiments s
    JOIN posts p 
    ON p.actor_did = s.actor_did
    AND p.rkey = s.rkey
WHERE s.processed_at IS NULL
ORDER BY s.created_at ASC
LIMIT 2000;
```

In this case both tables have a compound primary key of (`actor_did`, `rkey`), meaning we get an automatic index on both tables that should make our join index-only.

On our `post_sentiments` table, we have a conditional index as follows to make it cheaper to find un-indexed posts:

```sql
CREATE INDEX post_sentiments_unindexed_idx 
    ON post_sentiments (created_at ASC) 
    WHERE processed_at IS NULL;
```

When we run this query against our two tables with >22 million rows, it takes more than 12 seconds:
```json
"fetch_time":12.824282852
```

What's going on here? We're using all indexes and it _should_ be pretty easy to perform this query.

Well, what we're effectively doing here is joining two absolutely gigantic tables, then trying to sort the results of the join, and then grabbing the first 2,000 results.

Since only one of our tables has an index on `created_at`, we can't do an index-only join between the two tables and end up having to sequentially scan tables at massive cost.

## Limit First, Then Join

What we can do instead to make this query more efficient is try to limit the scope of the join so that sorting becomes cheap and we can do everything with indexes.

Let's structure the query as a Common Table Expression and leverage the power of doing significantly less work to make things go faster.

```sql
SELECT s.actor_did,
    s.rkey
FROM post_sentiments s
WHERE s.processed_at IS NULL
ORDER BY s.created_at
LIMIT 2000
```

In this query, since we keep a copy of the `created_at` column in `post_sentiments`, we can first grab 2,000 rows from the `post_sentiments` table leveraging our conditional index to its fullest.

This query executes in around ~40ms making a great candidate for a Common Table Expression.

We'll use it to pick the rows we want to join against the full `posts` table, which should allow us to join exclusively on the primary key indexes as follows:

```sql
WITH unprocessed_posts AS (
    SELECT s.actor_did,
        s.rkey
    FROM post_sentiments s
    WHERE s.processed_at IS NULL
    ORDER BY s.created_at
    LIMIT 2000
)
SELECT p.*
FROM posts p
    JOIN unprocessed_posts s 
    ON p.actor_did = s.actor_did
    AND p.rkey = s.rkey
ORDER BY p.created_at;
```

Now our join only requires joining the `posts_pkey` index against the 2,000 row CTE, meaning our sorting can be done in-memory and we don't need to perform any sequential scans on these huge tables.

Using a CTE instead of a naive full table join cuts down our query time from 12 seconds to ~0.12 seconds!

```json
"fetch_time":0.120976785
```

The next time you're troubleshooting slow queries that involve joining large tables, try making use of a CTE to filter at least one of the tables in the join and limit as early as possible!
