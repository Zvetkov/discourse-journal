import { getOwner } from "@ember/owner";
import { withPluginApi } from "discourse/lib/plugin-api";

// One topic route is active at a time, so a module-level flag is enough to keep
// pause/unpause balanced across topic-to-topic transitions.
let journalTopicActive = false;

function setJournalTopicActive(owner, active) {
  if (journalTopicActive === active) {
    return;
  }

  journalTopicActive = active;
  document.body.classList.toggle("topic-journal", active);

  const keyboardShortcuts = owner.lookup("service:keyboard-shortcuts");

  if (active) {
    keyboardShortcuts.pause(["c"]);
  } else {
    keyboardShortcuts.unpause(["c"]);
  }
}

export default {
  name: "journal-topic",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    if (!siteSettings.journal_enabled) {
      return;
    }

    withPluginApi((api) => {
      // Per-topic setup hangs off the route rather than a plugin outlet: every
      // outlet above the post stream is gated on the first post being loaded,
      // so deep links and last-read entry would skip it, and a timeline jump
      // would tear the connector down mid-read.
      //
      // setupController also covers topic-to-topic navigation, where Ember
      // reuses the route without calling deactivate.
      api.modifyClass(
        "route:topic",
        (Superclass) =>
          class extends Superclass {
            setupController(controller, model) {
              super.setupController(...arguments);

              const owner = getOwner(this);
              owner.lookup("service:journal").reset();
              setJournalTopicActive(owner, !!model?.journal);
            }

            deactivate() {
              super.deactivate(...arguments);

              const owner = getOwner(this);
              setJournalTopicActive(owner, false);
              owner.lookup("service:journal").reset();
            }
          }
      );

      api.modifyClass(
        "model:topic",
        (Superclass) =>
          class extends Superclass {
            get showJournalTip() {
              return this.journal && siteSettings.journal_show_topic_tip;
            }

            // Jump to the latest entry rather than the latest post.
            get lastPostUrl() {
              if (this.journal && this.last_entry_post_number) {
                return this.urlForPostNumber(this.last_entry_post_number);
              }

              return super.lastPostUrl;
            }
          }
      );

      // In a journal the reading position is driven by entries, so the
      // "back to last read" jump is meaningless.
      api.modifyClass(
        "component:topic-progress",
        (Superclass) =>
          class extends Superclass {
            get showBackButton() {
              if (this.topic?.journal) {
                return false;
              }

              return super.showBackButton;
            }
          }
      );
    });
  },
};
