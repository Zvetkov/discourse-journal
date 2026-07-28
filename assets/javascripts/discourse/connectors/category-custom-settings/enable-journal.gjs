import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import GroupChooser from "discourse/select-kit/components/group-chooser";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const RESULT_ICON_TIMEOUT = 6000;

/**
 * Everything here goes through the FormKit form rather than mutating
 * `category.custom_fields` directly: the category form snapshots custom_fields
 * at init and writes its own copy back over the model on save, so direct
 * mutations are silently discarded.
 */
export default class EnableJournal extends Component {
  @service site;

  @tracked updatingSortOrder = false;
  @tracked syncResultIcon = null;

  #resultTimer = null;

  willDestroy() {
    super.willDestroy(...arguments);
    clearTimeout(this.#resultTimer);
  }

  get category() {
    return this.args.outletArgs.category;
  }

  // Stored as a single pipe-delimited string; the chooser works in arrays.
  get authorGroups() {
    const stored =
      this.args.outletArgs.transientData?.custom_fields?.journal_author_groups;

    return stored ? stored.split("|").filter(Boolean) : [];
  }

  @action
  async onChangeAuthorGroups(groupNames, { set, name }) {
    await set(name, (groupNames || []).join("|"));
  }

  @action
  async updateSortOrder() {
    clearTimeout(this.#resultTimer);
    this.updatingSortOrder = true;
    this.syncResultIcon = null;

    try {
      const result = await ajax("/journal/update-sort-order", {
        type: "POST",
        data: { category_id: this.category.id },
      });

      this.syncResultIcon = result.success ? "check" : "xmark";
    } catch (error) {
      this.syncResultIcon = "xmark";
      popupAjaxError(error);
    } finally {
      this.updatingSortOrder = false;

      this.#resultTimer = setTimeout(() => {
        if (!this.isDestroying && !this.isDestroyed) {
          this.syncResultIcon = null;
        }
      }, RESULT_ICON_TIMEOUT);
    }
  }

  <template>
    {{#let @outletArgs.form as |form|}}
      <form.Section
        @title={{i18n "category.journal_settings_label"}}
        class="category-custom-settings-outlet journal-category-settings"
      >
        <form.Object @name="custom_fields" as |customFields|>
          <customFields.Field
            @name="journal"
            @type="checkbox"
            @title={{i18n "category.enable_journal"}}
            as |field|
          >
            <field.Control />
          </customFields.Field>

          <customFields.Field
            @name="journal_author_groups"
            @title={{i18n "category.journal_authors"}}
            @onSet={{this.onChangeAuthorGroups}}
            @type="custom"
            @format="full"
            as |field|
          >
            <field.Control>
              <GroupChooser
                @content={{this.site.groups}}
                @value={{this.authorGroups}}
                @valueProperty="name"
                @labelProperty="name"
                @onChange={{field.set}}
              />
            </field.Control>
          </customFields.Field>
        </form.Object>

        {{#if this.category.id}}
          <form.Container
            @title={{i18n "category.update_sort_order.label"}}
            @subtitle={{i18n "category.update_sort_order.description"}}
          >
            <DButton
              @label="category.update_sort_order.button"
              @action={{this.updateSortOrder}}
              @disabled={{this.updatingSortOrder}}
              @isLoading={{this.updatingSortOrder}}
              @icon="arrows-rotate"
              class="btn-default journal-category-settings__sort-order-button"
            />

            {{#if this.syncResultIcon}}
              {{dIcon this.syncResultIcon}}
            {{/if}}
          </form.Container>
        {{/if}}
      </form.Section>
    {{/let}}
  </template>
}
