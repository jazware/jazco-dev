---
layout: post
title: "Visualizing the Burgeoning BlueSky Social Network with Graph Theory"
subtitle: "And accidentally becoming an Influencer in the process"
excerpt: ""
---
![Graph of the BlueSky Social Network](/public/images/2023-05-15/full_graph.png)

Over the past few weeks I've been developing a suite of web-based tools (like the interactive [Atlas](https://bsky.jazco.dev/) seen above) for visualizing and interacting with [BlueSky](https://staging.bsky.app/), a federated social network built on the [ATProto](https://atproto.com/) protocol with a swiftly growing user base [currently numbering](https://bsky.jazco.dev/stats) around 80,000 members.

Tracking the growth of a social network and the relationships and interactions between users is an ambitious goal, but this all started out as a simple little project to poke around with ATProto.

## Who is Paul?

When I joined BlueSky, my feed was quite bare and the "What's Hot" tab was showing every post with at least 5 likes, a solid achievement back then. My experience of the network was through the lens of posts from the most popular users on the platform.

While browsing the feed, I noticed one [Paul Frazee](https://staging.bsky.app/profile/pfrazee.com) showed up in the What's Hot feed nearly constantly. As it turned out, Paul was a developer on the BlueSky team who focused mostly on the mobile applications and website frontend, and he was acting as the support team for the entire network. My feed was so full of people mentioning `@pfrazee.com` and Paul replying to them that I was convinced Paul wasn't a real person but was instead a LLM-powered support bot with infinite time on its hands and a good sense of humor.

To quantify the Ubiquity of Paul, and to determine whether or not he was feasibly a human, I endeavoured to count the number of times he was @-Mentioned on the website.

## The Firehose

[ATProto](https://atproto.com/) is a federation protocol designed to allow multiple Big Graph Services (BGS) to sync and replicate user-generated events (commits) that are then consumed by App Views which enrich them and filter them to suit different applications and users.

I won't dig too deeply into the philosophy and current state of the protocol here, but it's important to note that every user action on the network is a Commit to their Personal Data Repo which is like a git repository tracking the actions (likes/reposts/etc.) and posts of a user. In order to federate events between BGSs, a BGS needs to sync these repos and keep them up to date. To facilitate this, ATProto provides endpoints to [Get a Repo](https://atproto.com/lexicons/com-atproto-sync#comatprotosyncgetrepo), [Get the Data Blocks in a Commit](https://atproto.com/lexicons/com-atproto-sync#comatprotosyncgetblocks), and, most importantly for our purposes, [Subscribe to Repo Updates](https://atproto.com/lexicons/com-atproto-sync#comatprotosyncsubscriberepos) via a Websocket. 

This last endpoint, the `SyncSubscribeRepos` endpoint, looks a lot like the now-defunct [Twitter Firehose](https://www.pubnub.com/learn/glossary/firehose-api/), giving a consumer access to a feed of EVERY event on the network in real-time.

For my purposes, this was a wonderful way to track a running count of the number of times different users were mentioned and how many posts they responded to.

## Mention Counter

The first rendition of the [`graph-builder`](https://github.com/ericvolp12/bsky-experiments/blob/main/cmd/graph-builder/main.go) which now powers the [Atlas](https://bsky.jazco.dev/) was a Mention Counter.

The basic concept of this service was to attach to the Firehose websocket, look for all Repo Commits that were `Posts`, extract the rich-text `Facets` where @-mentions and hyperlinks are stored, and count the number of occurrences of different BSky Handles, syncing the state to a file every so often.

A little snippet of this [initial code](https://github.com/ericvolp12/bsky-experiments/tree/7c04d440167703a2cf2f8e83b95dd0ea8581d8d8) looks like:

```go
// DecodeFacets decodes the facets of a richtext record into mentions and links
func (bsky *BSky) DecodeFacets(ctx context.Context, facets []*appbsky.RichtextFacet) ([]string, []string, error) {
  mentions := []string{}
  links := []string{}
  for _, facet := range facets {
    if facet.Features != nil {
      for _, feature := range facet.Features {
        if feature != nil {
          if feature.RichtextFacet_Link != nil {
            links = append(links, feature.RichtextFacet_Link.Uri)
          } else if feature.RichtextFacet_Mention != nil {
            mentionedUser, err := appbsky.ActorGetProfile(ctx, bsky.Client, feature.RichtextFacet_Mention.Did)
            if err != nil {
              fmt.Printf("error getting profile for %s: %s", feature.RichtextFacet_Mention.Did, err)
              mentions = append(mentions, fmt.Sprintf("[failed-lookup]@%s", feature.RichtextFacet_Mention.Did))
              continue
            }
            mentions = append(mentions, fmt.Sprintf("@%s", mentionedUser.Handle))
            bsky.MentionCounters[mentionedUser.Handle]++
          }
        }
      }
    }
  }
  return mentions, links, nil
}
```

ATProto tracks users using an abstraction called a `DID` or Distributed Identifier that is stable and unchanging for the lifetime of the user's data repo. Users also have the ability to be identified by a `Handle` (a DNS name that's been verified) which can change over time. `Commits` and `Repos` speak in terms of `DIDs` instead of `Handles` to ensure relationships between users and posts remain stable over time.

In the above code, `Mention` contain a `Did` reference to the user being mentioned. If we want to provide a more easily human-identifiable string, we'll need to look up the `Handle` of each `Mention.Did` by resolving the profile against the BlueSky API.

## Tracking Relationships

After running the `mention-counter` for ~6 or so hours I checked the `mention-counts.txt` to see that `@pfrazee.com` had received somewhere in the neighborhood of 100 mentions while the next most popular user was only a quarter of the way there at 25 mentions.

To expand on this data, I wanted to track Replies and Quote-Reposts as well in case folks were using more than just @-Mentions to send Paul notifications.

This quickly grew to the point where I realized I could be tracking a real Graph data structure with weighted, directed edges that measure the number of interactions between any two users on the platform.

I leaned on GPT-4 to help me write a [Graph implementation](https://github.com/ericvolp12/bsky-experiments/blob/main/pkg/graph/graph.go), a lightweight binary encoding scheme to store and resume the graph, and a text-based adjacency list encoding scheme that's human-readable and easily portable for parsing in other systems.

With these tools, the `mention-counter` started its transition into the `graph-builder` and began tracking links between users on the network.

## How Hard could Visualizing an Entire Social Network be?

When I started this project, BlueSky had around 25,000 users and a post rate of around 0.8/sec.

Visualizing data in an interactive way is a huge design challenge. Libraries like [`D3.js`](https://d3js.org/), [`vis.js`](https://visjs.org/), and [`luma-gl`](https://luma.gl/) provide incredibly powerful tools to turn data into interactive and compelling visualizations in your browser, but they've all got limitations and specializations.

My personal experience was most thorough with D3 and so I grabbed it first as a tool for visualizing this graph.

Visualizing a graph data structure requires you to consider the data you have before choosing how you'll present it.

A few questions I had to ask before getting started were:

- How many nodes are there?
- How many edges are there?
- Are edges directed or undirected?
- Are edges weighted?
- How densely connected is the graph?

### Laying out a Graph
