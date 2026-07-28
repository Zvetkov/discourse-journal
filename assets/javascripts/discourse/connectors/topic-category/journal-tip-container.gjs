import Component from "@glimmer/component";
import JournalTopicTip from "../../components/journal-topic-tip";

export default class JournalTipContainer extends Component {
  static shouldRender(args) {
    return !!args.topic?.showJournalTip;
  }

  <template>
    <JournalTopicTip
      @label="topic.tip.journal.title"
      @details="topic.tip.journal.details"
    />
  </template>
}
