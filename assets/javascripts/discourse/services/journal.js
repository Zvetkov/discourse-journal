import { tracked } from "@glimmer/tracking";
import Service, { service } from "@ember/service";

/**
 * Comment visibility for journal topics.
 *
 * Every predicate here is a pure function of per-post data the server
 * serializes (`comment_position` is 1-based - see extensions/topic.rb) plus the
 * set of expanded entries. Deliberately no post stream traversal: the previous
 * implementation walked `postStream.posts` in a cached getter, which does not
 * reliably invalidate when the stream array mutates.
 */
export default class JournalService extends Service {
  @service siteSettings;

  // Replaced by value on each mutation so consumers re-render.
  @tracked expandedEntries = new Set();

  /** Comments shown per entry before collapsing. */
  get defaultCount() {
    return Number(this.siteSettings.journal_comments_default);
  }

  expand(entryPostId) {
    if (!this.expandedEntries.has(entryPostId)) {
      this.expandedEntries = new Set(this.expandedEntries).add(entryPostId);
    }
  }

  /** Called when leaving a journal topic, so state doesn't leak into the next. */
  reset() {
    this.expandedEntries = new Set();
  }

  isExpanded(post) {
    return this.expandedEntries.has(post.entry_post_id);
  }

  isCommentVisible(post) {
    // The user asked for a specific subset of posts; don't collapse any of it.
    if (this.isFiltered(post)) {
      return true;
    }

    // Staged comments, and deleted ones shown to staff, carry no position.
    if (!post.comment_position) {
      return true;
    }

    return post.comment_position <= this.defaultCount || this.isExpanded(post);
  }

  isFiltered(post) {
    const postStream = post.topic?.postStream;

    return !!(
      postStream?.filter ||
      postStream?.filterRepliesToPostNumber ||
      postStream?.filterUpwardsPostID
    );
  }

  hiddenCount(post) {
    return Math.max(0, (post.entry_comment_count ?? 0) - this.defaultCount);
  }

  /** Whether the "show N more comments" toggle renders after this post. */
  isToggleAnchor(post) {
    if (
      this.isFiltered(post) ||
      this.isExpanded(post) ||
      this.hiddenCount(post) === 0
    ) {
      return false;
    }

    // The toggle must hang off a *visible* post - it renders inside the post
    // wrapper, which is display:none for collapsed comments. That's the last
    // visible comment, or the entry itself when nothing is shown by default.
    if (this.defaultCount > 0) {
      return !!post.comment && post.comment_position === this.defaultCount;
    }

    return !!post.entry;
  }
}
