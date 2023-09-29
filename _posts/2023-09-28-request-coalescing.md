---
layout: post
title: "Solving Thundering Herds with Request Coalescing in Go"
excerpt: "Using request coalescing, we can serve the 200,000 user strong thundering herd by making only one request to our DB, making every other identical request wait for the results from the first request to hit the cache before they resolve."
---

Caches are a wonderful way to make your most frequent operations cheaper.

If you've got a resource somewhere on disk (or a network hop away) that is accessed often, changes infrequently, and fits in memory, you've got an excellent candidate for a cache!

## Caching Celebrity Posts

For example, consider a social media post from a famous celebrity.

This celebrity has 100,000,000 followers, around 5% of which are active at any given time (that's 5,000,000 users).

Any of those users accessing a post from our celebrity would require us to go lookup the post in our database and then serve it to the user.

That's not a huge deal if that's all our database is doing, but if it's busy handling other operations as well, we might want to avoid asking for the same data from it over and over again.

The celebrity post never changes (or maybe very infrequently could be edited), it's got some metadata i.e. like counts, repost counts, and reply counts which we want to be relatively fresh but the number we show is truncated to the thousands so we've got a decent time window in which the number the user sees won't change.

Instead of hitting the database over the network for every request, what if we stored it in memory with some kind of TTL and then, once expired, we reload it.

That way we only need to get the post once every 5 minutes (or whatever TTL we set) and can serve all 5 million of those active users from memory instead! Nice and cheap and works great!

```go
type CacheItem struct {
    Post schema.Post
    ExpiresAt time.Time
}

type Server struct {
    db *schema.Database
    cache map[string]*CacheItem
    ttl time.Duration
}

func (s *Server) GetPost(ctx context.Context, postURI string) (*schema.Post, error) {
    cacheItem, ok := cache[postURI]
    if ok && cacheItem.ExpiresAt.After(time.Now()) {
        return &cacheItem.Post, nil
    }

    post, err := s.db.GetPost(ctx, postURI)
    if err != nil {
        return nil, fmt.Errorf("failed to get post from DB: %w", err)
    }

    cache[postURI] = &CacheItem{
        Post: post,
        ExpiresAt: time.Now().Add(s.ttl)
    }

    return &post, nil
}
```

In the above pseudoGo, we create an in-memory cache using the post URI as a key.
Every time we Get the post, we check if the cache entry is valid and if so, send that back.
If the cache entry doesn't exist yet or has expired, we'll refresh the cache with a fresh query to the Database.

I've omitted locking for brevity so the above code isn't threadsafe and in real code I'd use something like [Hashicorp's LRU package](https://github.com/hashicorp/golang-lru) for your cache.

### The Problem With Caching

So, what happens when a celebrity posts to their 100M followers in this case?

Well, 5% of those followers who are active suddenly get a notification, open up the app, and load the post.

The first 200,000 of these users load the post within the same 100ms of each other.

The first request misses the cache since there's no valid entry in there yet, so it makes a request to the DB which takes 150ms to respond and then populates the cache for subsequent requests.

The second through 200,000th requests also miss the cache since the first request hasn't gotten back from the DB yet to populate the cache.

Despite having our shiny new caching in place, we still slam the DB with 200,000 requests in under a second and the site grinds to a halt.

To resolve this spike in load due to identical requests (commonly referred to as a "stampeeding herd"), we can make use of another strategy called Request Coalescing.

## Coalescing Requests

Coalescing requests is the practice of grouping identical requests that happen in a short period of time and executing only one request to satisfy all callers.

In our celebrity example, imagine if every time a request came in, we checked if there was already a pending request to the DB for that exact resource, and then subscribed the new request to the results of that pending request instead.

Let's see what it looks like in some Go code.

```go
type CacheItem struct {
	Post schema.Post
}

type Server struct {
	db *schema.Database
	// An expirable LRU automatically expires stale entries for us
	postCache *expirable.LRU[string, CacheItem]
	ttl       time.Duration
	// A sync.Map is a threadsafe implementation of a Map in Go that works well in specific use cases
	postLookupChans sync.Map
}

func (s *Server) GetPost(ctx context.Context, postURI string) (*schema.Post, error) {
	entry, ok := s.postCache.Get(postURI)
	if ok {
		return &entry.Post, nil
	}

	res := make(chan struct{}, 1)
	// Check if there's a pending request, if not, mark this request as pending
	val, loaded := s.postLookupChans.LoadOrStore(postURI, res)
	if loaded {
		// Wait for the result from the pending request
		select {
		case <-val.(chan struct{}):
			// The result should now be in the cache
			entry, ok := s.postCache.Get(postURI)
			if ok {
				return &entry.Post, nil
			}
			return nil, fmt.Errorf("post not found in cache after coalesce returned")
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}

	// Get the post from the DB
	post, err := s.db.GetPost(ctx, postURI)
	// Cleanup the coalesce map and close the results channel
	s.postLookupChans.Delete(postURI)
	// Callers waiting will now get the result from the cache
	close(res)
	if err != nil {
		return nil, fmt.Errorf("failed to get post from DB: %w", err)
	}
	return &post, nil
}
```

This new code is a bit more complex than our simple cache but it works as follows:
- If we're the first caller to ask for this resource and there's no valid cache entry, we create a result channel and set it in the Coalesce Map so that it can be found by other callers.
- We hit the DB and then get a result, clean up our pending request in the Coalesce Map, and then close our result channel, broadcasting to all listeners that our request is complete and they can find a fresh entry in the cache.
- If we're a subsequent caller, we load the result channel from the Coalesce Map and then wait on it until our context expires or the pending request is resolved, then we fetch our result from the cache.

Using request coalescing, we can serve the 200,000 user strong thundering herd by making only one request to our DB, making every other identical request wait for the results from the first request to hit the cache before they resolve.

When serving lots of similar requests, request coalescing reduces the number of requests by a factor on top of your cache, for instance if your cache miss rate is 10% but your coalesce rate is 80%, only 2% of requests you serve actually fall through to the DB.

If you want to see Request Coalescing in action, I've implemented it as part of the ATProto Indigo library for Identity Lookups [here](https://github.com/bluesky-social/indigo/blob/0dbe63eeea7b42d90b49a514941c7d0caee5bc58/atproto/identity/cache_directory.go#L247).
