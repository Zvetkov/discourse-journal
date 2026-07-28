import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import Composer from "discourse/models/composer";
import DButton from "discourse/ui-kit/d-button";

export default class JournalCommentButton extends Component {
  // Never collapse into the "show more" menu: this replaces the reply button.
  static hidden() {
    return false;
  }

  @service composer;
  @service site;

  get post() {
    return this.args.post;
  }

  get i18nKey() {
    return this.post.reply_to_post_number ? "comment_reply" : "comment";
  }

  get icon() {
    return this.post.reply_to_post_number ? "reply" : "comment";
  }

  // Mirrors core's reply button, and stays overridable via the
  // post-menu-buttons transformer's buttonLabels helpers.
  get showLabel() {
    return (
      this.args.showLabel ??
      (this.site.desktopView && !this.post.reply_to_post_number)
    );
  }

  get label() {
    return this.showLabel ? `topic.${this.i18nKey}.title` : undefined;
  }

  get title() {
    return `topic.${this.i18nKey}.help`;
  }

  @action
  openCommentCompose() {
    const topic = this.post.topic;

    this.composer.open({
      action: Composer.REPLY,
      draftKey: topic.draft_key,
      draftSequence: topic.draft_sequence,
      post: this.post,
    });
  }

  <template>
    <DButton
      class="comment create fade-out"
      ...attributes
      @action={{this.openCommentCompose}}
      @icon={{this.icon}}
      @label={{this.label}}
      @title={{this.title}}
    />
  </template>
}
