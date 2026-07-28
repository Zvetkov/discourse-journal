# Discourse Journal Plugin [Glimmer post stream fork]

Port of abandoned Journal plugin from Pavilion to Glimmer post stream.
Compatible with Discourse 2026.7.0
See `Fork's compatibility` and `Fork's porting notes` below.

This is a [Discourse](https://meta.discourse.org) plugin built by [Pavilion](https://thepavilion.io).

Pavilion is a freelancer cooperative with three goals
- Deliver high quality work to our clients
- Empower our members financially, professionally and personally
- Support our open source work and those who use it

[Read more about Pavilion and the work we do](https://thepavilion.io).

## Fork's compatibility

Targets current Discourse (2026.7.0 at the time of commit), where the widget rendering
system has been removed. 
Older versions are pinned via `.discourse-compatibility` (and `d-compat/<YYYY>.<M>`
branches, which take precedence) to the last commit that still supported widgets.

## Fork's porting notes

- **Comment visibility is server-derived.** `Topic#journal_post_map` assigns each comment a `comment_position` and each entry an `entry_comment_count`, both serialized onto the post. The client decides what to collapse from those alone - it never walks the post stream. `comment_position` is 1-based because `Post#updateFromPost` coerces falsy values to `null` when refreshing a post.
- **Collapsing is CSS instead of filtering.** The `post-class` transformer adds `comment` and, when visible, `show`, stylesheet hides the rest. The "show N more" toggle therefore has to anchor on a visible post, since it renders inside the post wrapper.
- **Function form of `api.modifyClass` is used.** The object form is de-duplicated per `pluginId` + resolver name, so a second registration against the same class is silently dropped, and it gives no `super` access on native classes.
- **Not patching routes through an `actions` hash.** `route:topic` and `route:discovery` are native classes with `@action` methods. An `actions` hash shadows core's handlers instead of extending them. Per-route setup belongs in a plugin-outlet connector, where teardown comes for free.
- **Arrays are not Ember arrays.** `EXTEND_PROTOTYPES` is off and `PostStream`'s `posts`/`stream` are tracked arrays: use native `push`/`splice`, and `removeValueFromArray` from `discourse/lib/array-tools`.
- **Nested (threaded) replies are disabled for journal topics.** That view renders its own post components and bypasses the `post-class` transformer entirely. 
- Post-menu buttons come from the `post-menu-buttons` DAG transformer. `addPostMenuButton` and friends are decommissioned no-ops.

## Features and Bugs

If you'd like to request a feature, please do so through our [feature request wizard](https://thepavilion.io/w/feature-request).

If you've found a bug, please report it through our [bug report wizard](https://thepavilion.io/w/bug-report).

An account on https://thepavilion.io is required to request features and report bugs. We do this to ensure that all relevant information about the feature or bug is captured so we can deal with it as efficiently and effectively as possible.

## Contributing

Pull requests are welcome from anyone.

## Licence

[GNU General Public Licence, Version 2](./LICENSE.txt)