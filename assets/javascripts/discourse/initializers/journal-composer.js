import { withPluginApi } from "discourse/lib/plugin-api";
import { CREATE_TOPIC, EDIT, REPLY } from "discourse/models/composer";
import { i18n } from "discourse-i18n";

function isJournal(composerModel) {
  return !!(composerModel?.category?.journal || composerModel?.topic?.journal);
}

function journalComposerKey(action, composerModel) {
  const post = composerModel?.post;

  if (action === CREATE_TOPIC) {
    return "create_journal";
  }

  if (action === REPLY && post) {
    return post.comment ? "reply_to_comment" : "create_comment";
  }

  if (action === EDIT && post) {
    return post.comment ? "edit_comment" : "edit_entry";
  }

  return "create_entry";
}

function journalComposerText(key) {
  let icon = "reply";

  if (key === "create_comment") {
    icon = "comment";
  } else if (key === "create_journal") {
    icon = "plus";
  } else if (key === "edit_entry" || key === "edit_comment") {
    icon = "pencil";
  }

  return {
    icon,
    name: `composer.composer_actions.${key}.name`,
    description: `composer.composer_actions.${key}.description`,
  };
}

function textFor(composerModel) {
  return journalComposerText(
    journalComposerKey(composerModel?.action, composerModel)
  );
}

export default {
  name: "journal-composer",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    if (!siteSettings.journal_enabled) {
      return;
    }

    withPluginApi((api) => {
      // Note the asymmetry: actionTitle returns a translated string, the other
      // two return keys.
      api.customizeComposerText({
        actionTitle(model) {
          if (isJournal(model)) {
            return i18n(textFor(model).name);
          }
        },

        saveLabel(model) {
          if (isJournal(model)) {
            return textFor(model).name;
          }
        },

        saveIcon(model) {
          if (isJournal(model)) {
            return textFor(model).icon;
          }
        },
      });

      // A journal composer can only ever switch to reply-to-post, so narrow the
      // dropdown to that and relabel it. Core's own item is reused rather than
      // fabricated, so selecting it still runs core's handler; staff toggles are
      // left alone since they render separately.
      api.registerValueTransformer(
        "composer-actions-content",
        ({ value, context: { topic, composerModel } }) => {
          if (!topic?.journal) {
            return value;
          }

          const text = textFor(composerModel);

          return value
            .filter((item) => item.isToggle || item.id === "reply_to_post")
            .map((item) => {
              if (item.isToggle) {
                return item;
              }

              return {
                ...item,
                icon: text.icon,
                name: i18n(text.name),
                description: i18n(text.description),
              };
            });
        }
      );

      // Quoting inside a journal must reply to a post, never to the topic -
      // a topic-level reply would be created as a new entry.
      api.modifyClass(
        "service:composer",
        (Superclass) =>
          class extends Superclass {
            async open(opts) {
              if (opts.topic?.journal && opts.quote && !opts.post) {
                opts.post = opts.topic.postStream.posts[0];
              }

              return super.open(opts);
            }
          }
      );
    });
  },
};
