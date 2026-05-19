import Service, { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { cached } from "@glimmer/tracking";

export default class JournalService extends Service {
  @service siteSettings;

  // The set of entry post IDs the user has manually expanded.
  // Replaced by value on each mutation so @cached dependents invalidate.
  @tracked shownEntries = [];

  // Set by the route:topic didTransition hook once a journal topic is entered,
  // cleared when the route transitions away. Gives the @cached visibilityMap
  // reactive access to postStream.posts without a container lookup at render time.
  @tracked postStream = null;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /**
   * Pre-expand the comments for a given entry post ID.
   * Called by the composer:opened listener when editing or replying to an entry.
   */
  showEntry(entryPostId) {
    if (!this.shownEntries.includes(entryPostId)) {
      this.shownEntries = [...this.shownEntries, entryPostId];
    }
  }

  /**
   * Expand hidden comments for a given entry post ID.
   * Called by ShowCommentsLink when the user clicks "show N more comments".
   */
  showComments(entryPostId) {
    if (!this.shownEntries.includes(entryPostId)) {
      this.shownEntries = [...this.shownEntries, entryPostId];
    }
  }

  /**
   * Reset all state. Called by the route:topic willTransition hook to prevent
   * shownEntries from one topic leaking into the next.
   */
  reset() {
    this.shownEntries = [];
    this.postStream = null;
  }

  // ---------------------------------------------------------------------------
  // Derived visibility map
  //
  // Returns a Map<postId, { visible, attachToggle, hiddenCount }>.
  //
  // @cached re-computes only when its tracked dependencies change:
  //   - this.postStream        (@tracked — replaced on topic entry/exit)
  //   - this.postStream.posts  (Ember tracked array — invalidates on any
  //                             append/prepend/insert from model:post-stream)
  //   - this.shownEntries      (@tracked — replaced by value on each mutation)
  // ---------------------------------------------------------------------------

  @cached
  get visibilityMap() {
    const map = new Map();

    if (!this.postStream) {
      return map;
    }

    // Access shownEntries here so @cached tracks it as a dependency.
    const shownEntries = this.shownEntries;
    const posts = this.postStream.posts;

    if (!posts || !posts.length) {
      return map;
    }

    // Guard: only compute for journal topics.
    const firstPost = posts[0];
    if (!firstPost?.journal) {
      return map;
    }

    const defaultComments = Number(this.siteSettings.journal_comments_default);
    let commentCount = 0;
    let lastVisibleId = null;

    posts.forEach((p, i) => {
      // Placeholder posts (not yet loaded) have no topic reference.
      if (!p.topic) {
        map.set(p.id, { visible: true, attachToggle: false, hiddenCount: 0 });
        return;
      }

      if (p.comment) {
        commentCount++;

        const expanded = shownEntries.includes(p.entry_post_id);
        const withinDefault = commentCount <= defaultComments;
        const visible = expanded || withinDefault;

        map.set(p.id, { visible, attachToggle: false, hiddenCount: 0 });

        if (visible) {
          lastVisibleId = p.id;
        }

        // End of a comment run: next post is an entry, or there is no next post.
        // If the run has hidden comments, mark the last visible post with the
        // toggle and the count so ShowCommentsLink knows where to render.
        const nextPost = posts[i + 1];
        const runEnds = !nextPost || nextPost.entry;

        if (runEnds && !visible && lastVisibleId !== null) {
          const entry = map.get(lastVisibleId);
          if (entry) {
            entry.attachToggle = true;
            entry.hiddenCount = commentCount - defaultComments;
          }
        }
      } else {
        // Entry post or first post: always visible, resets comment counter.
        map.set(p.id, { visible: true, attachToggle: false, hiddenCount: 0 });
        commentCount = 0;
        lastVisibleId = p.id;
      }
    });

    return map;
  }

  /**
   * Convenience accessor used by outlet components.
   * Returns the visibility record for a single post, with safe defaults.
   */
  visibilityFor(postId) {
    return (
      this.visibilityMap.get(postId) ?? {
        visible: true,
        attachToggle: false,
        hiddenCount: 0,
      }
    );
  }
}
