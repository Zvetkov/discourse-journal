import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { removeValueFromArray } from "discourse/lib/array-tools";
import { withPluginApi } from "discourse/lib/plugin-api";
import PostStream from "discourse/models/post-stream";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import { i18n } from "discourse-i18n";
import JournalCommentButton from "../components/journal-comment-button";

// Index in `posts` where a new comment belongs - the position of the entry that
// follows its comment run. -1 means "append": the run reaches the end of the
// loaded stream, or the parent isn't loaded.
function commentInsertIndex(posts, post) {
  const parentIndex = posts.findIndex(
    (p) => p.post_number === post.reply_to_post_number
  );

  if (parentIndex === -1) {
    return -1;
  }

  for (let i = parentIndex + 1; i < posts.length; i++) {
    if (!posts[i].reply_to_post_number) {
      return i;
    }
  }

  return -1;
}

// Mirror a comment's placement in `posts` into the id stream, so scroll position
// and post navigation agree with what is rendered.
function repositionCommentInStream(postStream, post) {
  if (!postStream.topic?.journal || !post.reply_to_post_number) {
    return;
  }

  const { stream, posts } = postStream;
  const postId = post.id;

  if (!stream.includes(postId)) {
    return;
  }

  // `post` is already in `posts`, but carries a reply_to_post_number, so the
  // scan skips it.
  const index = commentInsertIndex(posts, post);
  const anchorId = index > 0 ? posts[index]?.id : undefined;

  if (anchorId === undefined || !stream.includes(anchorId)) {
    return;
  }

  removeValueFromArray(stream, postId);
  stream.splice(stream.indexOf(anchorId), 0, postId);
}

class ShowCommentsLink extends Component {
  // The first post is an entry, and with journal_comments_default at 0 the
  // toggle anchors on entries - so it must not be excluded here.
  static shouldRender(args) {
    return !!args.post?.journal;
  }

  @service journal;

  get post() {
    return this.args.post;
  }

  get shouldShow() {
    return this.journal.isToggleAnchor(this.post);
  }

  get label() {
    const count = this.journal.hiddenCount(this.post);
    // "show N comments" only when nothing else from the run is visible.
    const type = count === this.post.entry_comment_count ? "all" : "more";

    return i18n(`topic.comment.show_comments.${type}`, { count });
  }

  @action
  showComments() {
    this.journal.expand(this.post.entry_post_id);
  }

  <template>
    {{#if this.shouldShow}}
      <button
        type="button"
        class={{dConcatClass
          "show-comments"
          (if this.post.entry "--entry-anchored")
        }}
        {{on "click" this.showComments}}
      >
        {{this.label}}
      </button>
    {{/if}}
  </template>
}

export default {
  name: "journal-post",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    if (!siteSettings.journal_enabled) {
      return;
    }

    const journal = container.lookup("service:journal");

    // Expand the target entry when the composer opens, so the reply being
    // written lands somewhere visible. This has to cover replies to comments
    // too, not just to entries - otherwise a comment posted into a collapsed run
    // is hidden the moment it commits.
    container.lookup("service:app-events").on("composer:opened", () => {
      const post = container.lookup("service:composer").model?.post;

      if (post?.journal) {
        journal.expand(post.entry_post_id);
      }
    });

    withPluginApi((api) => {
      api.registerValueTransformer(
        "post-menu-buttons",
        ({
          value: dag,
          context: { post, buttonKeys, lastHiddenButtonKey },
        }) => {
          if (post.journal && post.topic?.details?.can_create_post) {
            dag.add("comment", JournalCommentButton, {
              after: lastHiddenButtonKey,
            });
            dag.delete(buttonKeys.REPLY);
          }
        }
      );

      // Collapsed comments get `comment` without `show`; the stylesheet hides
      // those.
      api.registerValueTransformer(
        "post-class",
        ({ value, context: { post } }) => {
          if (!post.journal || post.firstPost) {
            return value;
          }

          if (post.comment) {
            return journal.isCommentVisible(post)
              ? [...value, "comment", "show"]
              : [...value, "comment"];
          }

          // Small actions and whispers are neither; leave them alone.
          return post.entry ? [...value, "entry"] : value;
        }
      );

      api.registerValueTransformer(
        "post-avatar-size",
        ({ value, context: { post } }) => {
          if (!post?.journal) {
            return value;
          }

          return post.comment ? "small" : "large";
        }
      );

      // A journal post's parent is implied by its position, so the reply-to tab
      // is noise.
      api.registerValueTransformer(
        "post-meta-data-infos",
        ({ value: dag, context: { post, metaDataInfoKeys } }) => {
          if (post.journal && !post.firstPost) {
            dag.delete(metaDataInfoKeys.REPLY_TO_TAB);
          }
        }
      );

      api.renderAfterWrapperOutlet("post-article", ShowCommentsLink);

      // Keep newly created comments next to their entry rather than at the end
      // of the topic. The server reorders sort_order on post_created, so this
      // only covers the window before the stream reloads.
      //
      // addModelMethod shadows the core method on the prototype without
      // exposing `super`, so the originals are captured up front and called
      // explicitly. Only appendPost changes placement; stagePost and commitPost
      // go through it and then push the id onto the stream, which is mirrored
      // afterwards.
      const { stagePost, commitPost, appendPost } = PostStream.prototype;

      api.addModelMethod("post-stream", "appendPost", function (post) {
        const lengthBefore = this.posts.length;
        const result = appendPost.call(this, post);

        if (
          this.topic?.journal &&
          post.reply_to_post_number &&
          this.posts.length > lengthBefore
        ) {
          // Core pushed the stored post to the end; move it in front of the
          // entry that follows its parent, when that entry is loaded.
          const index = commentInsertIndex(this.posts, post);

          if (index !== -1) {
            this.posts.splice(index, 0, this.posts.pop());
          }
        }

        return result;
      });

      api.addModelMethod("post-stream", "stagePost", function (post, user) {
        const result = stagePost.call(this, post, user);
        repositionCommentInStream(this, post);
        return result;
      });

      api.addModelMethod("post-stream", "commitPost", function (post) {
        const result = commitPost.call(this, post);
        repositionCommentInStream(this, post);
        return result;
      });
    });
  },
};
