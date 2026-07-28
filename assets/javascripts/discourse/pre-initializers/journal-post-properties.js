import { withPluginApi } from "discourse/lib/plugin-api";

/**
 * Tracked properties only affect model instances created after registration, so
 * this must run before any Post is constructed.
 *
 * Not gated on `journal_enabled`: service lookups this early are fragile, and a
 * few unused tracked properties are harmless.
 */
export default {
  name: "journal-post-properties",

  after: "discourse-bootstrap",
  before: "inject-discourse-objects",

  initialize() {
    withPluginApi((api) => {
      api.addTrackedPostProperties(
        "journal",
        "entry",
        "comment",
        "entry_post_id",
        "comment_position",
        "entry_comment_count",
        "reply_to_post_number"
      );

      api.addTrackedTopicProperties(
        "journal",
        "last_entry_post_number",
        "can_create_entry",
        "entry_count",
        "comment_count"
      );
    });
  },
};
