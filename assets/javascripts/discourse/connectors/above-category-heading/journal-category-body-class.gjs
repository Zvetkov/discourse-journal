import Component from "@glimmer/component";
import bodyClass from "discourse/helpers/body-class";

// Exposes the `journal-category` body class to site CSS. Previously applied
// from a `route:discovery` `actions` hash, which no longer reaches core.
export default class JournalCategoryBodyClass extends Component {
  static shouldRender(args) {
    return !!args.category?.journal;
  }

  <template>{{bodyClass "journal-category"}}</template>
}
