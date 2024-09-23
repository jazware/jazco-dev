---
layout: post
title: "Jetstream: Turning ~2.85 TB/mo into ~25.5 GB/mo on AT Proto"
excerpt: "Jetstream allows us to live tail all posts on Bluesky as they're posted for as little as ~850 MB/day"
---

[Bluesky](https://bsky.app) recently saw a [massive spike](https://bsky.app/profile/did:plc:q6gjnaw2blty4crticxkmujt/post/3l2zpatdkjx2f) in activity in response to Brazil's ban of Twitter.

As a result, the AT Proto event firehose provided by Bluesky's Relay at `bsky.network` has increased in volume by a huge amount.

Before this new surge in activity, the firehose would produce around 24 GB/day of traffic. After the surge, this volume jumped to over 232 GB/day!

![Graph of firehose traffic vs a week prior](/public/images/2024-09-23/firehose_traffic.png)

Keeping up with the firehose quickly became impractical on cheap cloud infrastructure with metered bandwidth.

To help reduce the burden of operating bots, feed generators, labelers, and other AT Proto services, I built [Jetstream](https://github.com/bluesky-social/jetstream) as an alternative, lightweight, filterable JSON firehose for AT Proto.

## How the Firehose Works

The AT Proto firehose is a mechanism used to keep fully synced copies of the [repos](https://atproto.com/guides/data-repos) of all users.

Since repos are represented as Merkle Search Trees, each firehose event contains an update to the user's MST which includes all the changed blocks (nodes in the path from the root to the modified leaf) to ensure that a consumer gets the same end result after applying the diff in the event to their own copy of the repo.

For a more in-depth explanation of how Merkle Trees are constructed, check out [this explainer](https://web.archive.org/web/20240901220955/https://www.baeldung.com/cs/merkle-trees).

In reality, this means that for every small JSON record added to a repo, we also send along some number of MST blocks (which are content-addressed hashes and thus very information-dense) that are only useful for consumers attempting to keep a fully synced, valid copy of the repo.

This is the "Authenticated" part of the Authenticated Transfer (AT) Protocol and is crucial to the correct functioning of the network.

That being said, of the hundreds of consumers of Bluesky's production Relay, >90% of them are building feeds, bots, and other tools that don't keep full copies of the entire network and don't check the validity of MST operations for every event they see.

For these consumers, all they actually process is the JSON records created, updated, and deleted in each event.

## How Jetstream Works

[Jetstream](https://github.com/bluesky-social/jetstream) is a streaming service that consumes an ATProto `com.atproto.sync.subscribeRepos` [stream](https://docs.bsky.app/docs/advanced-guides/firehose) and converts it into lightweight, friendly JSON.

If you want to try it out yourself, you can connect to my public Jetstream instance and view all posts on Bluesky in realtime:

```shell
$ websocat "wss://jetstream.atproto.tools/subscribe?wantedCollections=app.bsky.feed.post"
```

_Note: the above instance runs on a $5/mo VPS and is just run by me personally, official public Jetstream instances are coming soon_

Jetstream converts the CBOR-encoded MST blocks produced by the ATProto firehose and translates them into JSON objects that are easier to interface with using standard tooling available in programming languages.

Since Repo MSTs only contain records in their leaf nodes, this means Jetstream can drop all of the blocks in an event except for those of the leaf nodes (usually only one per event).

In reality, this means that Jetstream's JSON firehose is nearly 1/10 the size of the full protocol firehose for the same events.

Jetstream events end up looking something like:

```json
{
  "did": "did:plc:eygmaihciaxprqvxpfvl6flk",
  "time_us": 1725911162329308,
  "type": "com",
  "commit": {
    "rev": "3l3qo2vutsw2b",
    "type": "c",
    "collection": "app.bsky.feed.like",
    "rkey": "3l3qo2vuowo2b",
    "record": {
      "$type": "app.bsky.feed.like",
      "createdAt": "2024-09-09T19:46:02.102Z",
      "subject": {
        "cid": "bafyreidc6sydkkbchcyg62v77wbhzvb2mvytlmsychqgwf2xojjtirmzj4",
        "uri": "at://did:plc:wa7b35aakoll7hugkrjtf3xf/app.bsky.feed.post/3l3pte3p2e325"
      }
    },
    "cid": "bafyreidwaivazkwu67xztlmuobx35hs2lnfh3kolmgfmucldvhd3sgzcqi"
  }
}
```

Each event lets you know the DID of the repo it applies to, when it was seen by Jetstream (the cursor), and if it's a commit of changes to the repo, it provides any new record as JSON.

Check out the CPU profile of Jetstream serving 200k evt/sec to a local consumer:
![pprof of Jetstream showing CPU without compression](/public/images/2024-09-23/no_comp_cpu.png)

By dropping the MST overhead, we've reduced the size of a firehose of all events on the network from 232 GB/day to ~41GB/day, but we can do better.

### Jetstream and `zstd`

I recently read a [great engineering blog](https://web.archive.org/web/20240921070907/https://discord.com/blog/how-discord-reduced-websocket-traffic-by-40-percent) from Discord about their use of `zstd` to compress websocket traffic to/from their Gateway service and client applications.

Since Jetstream is emitting marshalled JSON through the websocket for developer-friendliness, I figured it might be a neat idea to see if we could get further bandwidth reduction by employing `zstd` to compress events we send to consumers.

`zstd` has two basic operating modes, ["simple"](https://facebook.github.io/zstd/zstd_manual.html#Chapter3) mode and ["streaming"](https://facebook.github.io/zstd/zstd_manual.html#Chapter7) mode.

#### Streaming Compression

At first glance, streaming mode seems like it'd be a great fit. We've got a websocket connection with a consumer and streaming mode allows the compression to get more efficient over the lifetime of the connection.

I went and implemented a streaming compression version of Jetstream where a consumer can request compression when connecting and will get `zstd` compressed JSON sent as binary messages over the socket instead of plaintext.

Unfortunately, this had a massive impact on Jetstream's server-side CPU utilization. We were effectively compressing every message once per consumer as part of their streaming session. This was not a scalable approach to offering compression on Jetstream.

Additionally, Jetstream stores a buffer of the past 24 hours (configurable) of events on disk in [PebbleDB](https://github.com/cockroachdb/pebble) to allow consumers to replay events before getting transitioned into live-tailing mode.

Jetstream stores serialized JSON in the DB, so playback is just shuffling the bytes into the websocket without having to round-trip the data into a Go struct.

When we layer in streaming compression, playback becomes significantly more expensive because we have to compress outgoing events on-the-fly for a consumer that's catching up.

In real numbers, this increased CPU usage of Jetstream by 23% while lowering the throughput of playback from ~200k evt/sec to ~28k evt/sec for a single local consumer.

When in streaming mode, we can't leverage the bytes we compress for one consumer and reuse them for another consumer because `zstd`'s streaming context window may not be in sync between the two consumers. They haven't received exactly the same data in the session so the clients on the other end don't have their state machines in the same state.

Since streaming mode's primary advantage is giving us eventually better efficiency as the encoder learns about the data, what if we just taught the encoder about the data at the start and compress each message statelessly?

#### Dictionary Mode

`zstd` offers a mechanism for initializing an encoder/decoder with pre-optimized settings by providing a [dictionary](https://facebook.github.io/zstd/#small-data) trained on a sample of the data you'll be encoding/decoding.

Using this dictionary, `zstd` essentially uses it's smallest encoded representations for the most frequently seen patterns in the sample data. In our case, where we're compressing serialized JSON with a common event shape and lots of common property names, training a dictionary on a large number of real events should allow us to represent the common elements among messages in the smallest number of bytes.

For take two of Jetstream with `zstd`, I decided to use a single encoder for the whole service that utilizes a custom dictionary trained on 100,000 real events.

We can use this encoder to compress _every_ event as we see it, before persisting and emitting it to consumers. Now we end up with two copies of every event, one that's just serialized JSON, and one that's statelessly compressed to `zstd` using our dictionary.

Any consumers that want compression can have a copy of the dictionary on their end to initialize a decoder, then when we broadcast the shared compressed event, all consumers can read it without any state or context issues.

That leaves the problem of event playback for clients that want compression.

An easy solution here is to just store the compressed events as well! Since we're only sticking the JSON records into our PebbleDB, the actual size of the 24 hour playback window is <8GB with sstable compression. If we store a copy of the JSON serialized event _and_ a copy of the `zstd` compressed event, we only end up doubling our storage requirements at most.

Then during playback, if the consumer requests compression, we can just shuffle bytes out of the compressed version of the DB into their socket instead of having to move it through a `zstd` encoder.

## Savings

Running with a custom dictionary, I was able to get the average Jetstream event down from 482 bytes to just 211 bytes (~0.44 compression ratio).

Jetstream allows us to live tail all posts on Bluesky as they're posted for as little as ~850 MB/day, and we could keep up with all events moving through the firehose during the Brazil Twitter Exodus weekend for 18GB/day (down from 232GB/day).

With this scheme, Jetstream is required to compress each event only once before persisting it to disk and emitting it to connected consumers.

The CPU impact of these changes is significant in proportion to Jetstream's incredibly light load but it's a flat cost we pay once no matter how many consumers we have.

![Jetstream CPU pprof with compression](/public/images/2024-09-23/after_cpu.png)

_(CPU profile from a 30 second pprof sample)_

Additionally, with Jetstream's shared buffer broadcast architecture, we keep memory allocations incredibly low and the cost per consumer on CPU and RAM is trivial.

![Jetstream allocation pprof with compression](/public/images/2024-09-23/after_allocations.png)

The total resident memory of Jetstream remains below 31MB, most of which is actually consumed by the new `zstd` dictionary.

![Jetstream in-use memory pprof with compression](/public/images/2024-09-23/after_ram.png)

To bring it all home, here's a screenshot from the dashboard of my public Jetstream instance serving 12 consumers all with various filters and compression settings, running on a $5/mo OVH VPS.

![jetstream dash](/public/images/2024-09-23/jetstream_dash.png)

At our new baseline firehose activity, a consumer of the protocol-level firehose would require downloading ~2.85TB/mo to keep up.

A Jetstream consumer that only cares about posts and has `zstd` compression enabled can get by on as little as ~25.5GB/mo.

Feel free to join the conversation about Jetstream and `zstd` [on Bluesky](https://bsky.app/profile/did:plc:q6gjnaw2blty4crticxkmujt/post/3l4rlbynavw2y).
