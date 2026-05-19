import Component from "@glimmer/component";
import { service } from "@ember/service";
import { action } from "@ember/object";
import { alias } from "@ember/object/computed";
import { on } from "@ember/modifier";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import JournalCommentButton from "../components/journal-comment-button";

const PLUGIN_ID = "discourse-journal";

// ---------------------------------------------------------------------------
// ShowCommentsLink
//
// Rendered after each post-article via renderAfterWrapperOutlet("post-article").
// Replaces decorateWidget("post:after", ...) + the widget link attachment.
//
// The migration guide confirms that components registered with
// renderAfterWrapperOutlet receive @post as an arg and may implement a static
// shouldRender(args) method. We use shouldRender to skip rendering entirely on
// posts that don't need the toggle, avoiding unnecessary service lookups.
// ---------------------------------------------------------------------------

class ShowCommentsLink extends Component {
  @service journal;

  static shouldRender(args) {
    // Only bother instantiating for journal comment posts that are visible
    // and have been marked as the toggle anchor by the service.
    return args.post?.journal && args.post?.comment;
  }

  get visibility() {
    return this.journal.visibilityFor(this.args.post.id);
  }

  get shouldShow() {
    const { attachToggle, hiddenCount } = this.visibility;
    return attachToggle && hiddenCount > 0;
  }

  get label() {
    const type =
      Number(this.journal.siteSettings.journal_comments_default) > 0
        ? "more"
        : "all";
    return i18n(`topic.comment.show_comments.${type}`, {
      count: this.visibility.hiddenCount,
    });
  }

  @action
  showComments() {
    this.journal.showComments(this.args.post.entry_post_id);
  }

  <template>
    {{#if this.shouldShow}}
      <button
        type="button"
        class="show-comments"
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

    const journalService = container.lookup("service:journal");
    const appEvents = container.lookup("service:app-events");

    // -------------------------------------------------------------------------
    // composer:opened
    //
    // Pre-expands the comment thread for the entry being replied to, mirroring
    // the old scrolling-post-stream didInsertElement listener.
    // -------------------------------------------------------------------------

    appEvents.on("composer:opened", () => {
      const composer = container.lookup("service:composer");
      const post = composer.get("model.post");

      if (post?.entry) {
        journalService.showEntry(post.id);
      }
    });

    // -------------------------------------------------------------------------
    // Glimmer post-stream API
    // -------------------------------------------------------------------------

    withPluginApi("1.34.0", (api) => {
      // -- post-menu-buttons (unchanged — already correct) -------------------

      api.registerValueTransformer(
        "post-menu-buttons",
        ({
          value: dag,
          context: { post, buttonKeys, lastHiddenButtonKey },
        }) => {
          if (post.topic.details.can_create_post && post.journal) {
            dag.add("comment", JournalCommentButton, {
              after: lastHiddenButtonKey,
            });
            dag.delete(buttonKeys.REPLY);
          }
        }
      );

      // -- post-class --------------------------------------------------------
      //
      // Replaces addPostClassesCallback.
      //
      // Adds "entry" or "comment"/"comment show" classes. The "show" class is
      // preserved for SCSS compatibility even though the original stylesheet
      // did not gate visibility on it — third-party CSS may depend on it.
      //
      // Comment visibility (hiding collapsed comments) is handled here via the
      // "journal-comment-hidden" class, which maps to display:none in journal.scss.
      // This replaces the old postArray filtering in reopenWidget("post-stream").

      api.registerValueTransformer(
        "post-class",
        ({ value, context: { post } }) => {
          if (!post.journal || post.firstPost) {
            return value;
          }

          if (post.comment) {
            const { visible } = journalService.visibilityFor(post.id);
            const classes = [...value, "comment"];

            if (visible) {
              classes.push("show");
            } else {
              classes.push("journal-comment-hidden");
            }

            return classes;
          }

          return [...value, "entry"];
        }
      );

      // -- post-avatar-size --------------------------------------------------
      //
      // Replaces reopenWidget("post-avatar", { html(attrs) { ... } }).
      // Confirmed in the migration thread (post #9): the transformer name is
      // "post-avatar-size" and it is registered in the avatar component itself,
      // not in plugin-api.gjs.

      api.registerValueTransformer(
        "post-avatar-size",
        ({ value, context: { post } }) => {
          if (!post?.journal) {
            return value;
          }
          return post.comment ? "small" : "large";
        }
      );

      // -- post-meta-data-infos ----------------------------------------------
      //
      // Replaces the two behaviours from reopenWidget("post"):
      //   1. entry posts: replyToUsername was nulled → remove the reply-to tab
      //   2. comment posts: replyCount was nulled → remove the reply-to tab
      //      (comments don't link back to their parent in journal context)
      //
      // Also replaces reopenWidget("reply-to-tab", { click() { return false } })
      // — removing the tab entirely is cleaner than suppressing its click.
      //
      // The transformer receives the DAG as `value` and metaDataInfoKeys as
      // context. We call dag.delete(metaDataInfoKeys.REPLY_TO_TAB) to remove
      // the reply-to tab component from the metadata row for journal posts.

      api.registerValueTransformer(
        "post-meta-data-infos",
        ({ value: dag, context: { post, metaDataInfoKeys } }) => {
          if (!post.journal || post.firstPost) {
            return;
          }

          // Both entries (suppress replyToUsername) and comments (suppress
          // replyCount) lose the reply-to tab in journal context.
          dag.delete(metaDataInfoKeys.REPLY_TO_TAB);
        }
      );

      // -- post-article outlet: show-comments link ---------------------------
      //
      // Replaces decorateWidget("post:after", ...) + widget link.
      // "post-article" is confirmed as a valid wrapper outlet name in the
      // migration guide (examples 3 & 4).

      api.renderAfterWrapperOutlet("post-article", ShowCommentsLink);
    });

    // -------------------------------------------------------------------------
    // Legacy-compatible API (no Glimmer-specific equivalent required)
    // -------------------------------------------------------------------------

    withPluginApi("0.8.12", (api) => {
      // -- addTrackedPostProperties ------------------------------------------
      //
      // Replaces includePostAttributes. showComment, attachCommentToggle, and
      // hiddenComments are intentionally omitted — they are now derived
      // reactively from JournalService.visibilityMap rather than being mutated
      // onto post objects directly.

      api.addTrackedPostProperties(
        "journal",
        "reply_to_post_number",
        "comment",
        "entry",
        "entry_post_id",
        "entry_post_ids"
      );

      // -- model:post-stream -------------------------------------------------
      //
      // No migration needed. modifyClass on models is unaffected by the Glimmer
      // post stream change. The posts array manipulated here (stagePost,
      // commitPost, appendPost, prependPost) is the same tracked array that
      // JournalService.visibilityMap reads from, so insertions automatically
      // invalidate the @cached getter in the service.

      api.modifyClass("model:post-stream", {
        pluginId: PLUGIN_ID,

        journal: alias("topic.journal"),

        getCommentIndex(post) {
          const posts = this.get("posts");
          let passed = false;
          let commentIndex = null;

          posts.some((p, i) => {
            if (passed && !p.reply_to_post_number) {
              commentIndex = i;
              return true;
            }
            if (
              p.post_number === post.reply_to_post_number &&
              i < posts.length - 1
            ) {
              passed = true;
            }
          });

          return commentIndex;
        },

        insertCommentInStream(post) {
          const stream = this.stream;
          const postId = post.get("id");
          const commentIndex = this.getCommentIndex(post) - 1;

          if (
            stream.indexOf(postId) > -1 &&
            commentIndex &&
            commentIndex > 0
          ) {
            stream.removeObject(postId);
            stream.insertAt(commentIndex, postId);
          }
        },

        stagePost(post) {
          let result = this._super(...arguments);
          if (!this.journal) {
            return result;
          }

          if (post.get("reply_to_post_number")) {
            this.insertCommentInStream(post);
          }

          return result;
        },

        commitPost(post) {
          let result = this._super(...arguments);
          if (!this.journal) {
            return result;
          }

          if (post.get("reply_to_post_number")) {
            this.insertCommentInStream(post);
          }

          return result;
        },

        prependPost(post) {
          if (!this.journal) {
            return this._super(...arguments);
          }

          const stored = this.storePost(post);
          if (stored) {
            const posts = this.get("posts");

            if (post.post_number === 2 && posts[0].post_number === 1) {
              posts.insertAt(1, stored);
            } else {
              posts.unshiftObject(stored);
            }
          }

          return post;
        },

        appendPost(post) {
          if (!this.journal) {
            return this._super(...arguments);
          }

          const stored = this.storePost(post);
          if (stored) {
            const posts = this.get("posts");

            if (!posts.includes(stored)) {
              let insertPost = () => posts.pushObject(stored);

              if (post.get("reply_to_post_number")) {
                const commentIndex = this.getCommentIndex(post);

                if (commentIndex && commentIndex > 0) {
                  insertPost = () => posts.insertAt(commentIndex, stored);
                }
              }

              if (!this.get("loadingBelow")) {
                this.get("postsWithPlaceholders").appendPost(insertPost);
              } else {
                insertPost();
              }
            }

            if (stored.get("id") !== -1) {
              this.set("lastAppended", stored);
            }
          }

          return post;
        },
      });

      // -- route:topic -------------------------------------------------------
      //
      // Wires JournalService.postStream on topic entry and clears it on exit.
      // This is what makes the @cached visibilityMap reactive — it reads
      // postStream.posts, which is a tracked Ember array, so any insertions
      // from the model extension above automatically invalidate the map.
      //
      // We extend route:topic rather than modifying the existing journal-topic.js
      // extension to keep the postStream wiring co-located with the service.
      // The two modifyClass calls with the same pluginId are safe because
      // Discourse deduplicates by pluginId + resolverName key.

      api.modifyClass("route:topic", {
        pluginId: PLUGIN_ID,

        actions: {
          didTransition() {
            const result = this._super(...arguments);
            const controller = this.controllerFor("topic");
            const topic = controller.get("model");

            if (topic?.journal) {
              journalService.postStream = topic.postStream;
            }

            return result;
          },

          willTransition() {
            const controller = this.controllerFor("topic");
            const topic = controller.get("model");

            if (topic?.journal) {
              journalService.reset();
            }

            return this._super(...arguments);
          },
        },
      });
    });
  },
};
