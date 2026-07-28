import DTooltip from "discourse/float-kit/components/d-tooltip";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const JournalTopicTip = <template>
  <div class="journal-topic-tip">
    <DTooltip @placement="right-start">
      <:trigger>
        <div class="btn btn-topic-tip">
          <span class="d-button-label">{{i18n @label}}</span>
          {{dIcon "circle-info"}}
        </div>
      </:trigger>
      <:content>
        <div class="tip-details">
          {{i18n @details}}
        </div>
      </:content>
    </DTooltip>
  </div>
</template>;

export default JournalTopicTip;
