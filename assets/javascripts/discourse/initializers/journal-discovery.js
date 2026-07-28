import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "journal-discovery",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    if (!siteSettings.journal_enabled) {
      return;
    }

    withPluginApi((api) => {
      // Core resolves to "" on mobile and to a shared-draft key in shared-draft
      // categories; only relabel when it actually wanted the default label.
      api.registerValueTransformer(
        "create-topic-label",
        ({ value, context: { category, defaultKey } }) => {
          if (category?.journal && value === defaultKey) {
            return "topic.create_journal.label";
          }

          return value;
        }
      );
    });
  },
};
