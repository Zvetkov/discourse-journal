import Component from "@glimmer/component";
import JournalTopicTip from "../../components/journal-topic-tip";

export default class JournalTipContainer extends Component {
  static shouldRender(args, context, owner) {
    return (
      !!args.topic?.journal &&
      !!owner.lookup("service:site-settings").journal_show_topic_tip
    );
  }

  <template>
    <JournalTopicTip
      @label="topic.tip.journal.title"
      @details="topic.tip.journal.details"
    />
  </template>
}
