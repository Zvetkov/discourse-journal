import Component from "@glimmer/component";
import { action } from "@ember/object";
import { getOwner } from "@ember/owner";
import DButton from "discourse/ui-kit/d-button";

// "New Entry" button for journal authors. Replying to the topic (rather than to
// a post) is what creates an entry, so core's reply button is hidden by the
// stylesheet in journal topics.
export default class EntryButtonWrapper extends Component {
  static shouldRender(args) {
    return !!args.topic?.can_create_entry;
  }

  @action
  createEntry() {
    getOwner(this).lookup("controller:topic").send("replyToPost");
  }

  <template>
    <DButton
      class="btn-primary create entry"
      @icon="reply"
      @action={{this.createEntry}}
      @label="topic.entry.title"
      @title="topic.entry.title"
    />
  </template>
}
