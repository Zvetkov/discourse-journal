# frozen_string_literal: true

# name: discourse-journal
# about: Create journals in discourse
# version: 0.4.0
# authors: Angus McLeod
# url: https://github.com/Zvetkov/discourse-journal

enabled_site_setting :journal_enabled

register_asset "stylesheets/common/journal.scss"
register_asset "stylesheets/desktop/journal.scss", :desktop
register_asset "stylesheets/mobile/journal.scss", :mobile

after_initialize do
  %w(
    ../lib/journal/engine.rb
    ../app/controllers/discourse_journal/journal_controller.rb
    ../config/routes.rb
    ../extensions/category_custom_field.rb
    ../extensions/guardian.rb
    ../extensions/post_creator.rb
    ../extensions/topic.rb
    ../extensions/topic_nested.rb
    ../jobs/update_journal_category_sort_order.rb
  ).each do |path|
    load File.expand_path(path, __FILE__)
  end

  ::Guardian.prepend DiscourseJournal::GuardianExtension
  ::PostCreator.prepend DiscourseJournal::PostCreatorExtension
  ::Topic.include DiscourseJournal::TopicExtension
  ::Topic.prepend DiscourseJournal::TopicNestedExtension if ::Topic.method_defined?(:nested_view?)
  ::CategoryCustomField.include DiscourseJournal::CategoryCustomFieldExtension

  register_category_custom_field_type("journal", :boolean)
  register_category_custom_field_type("journal_author_groups", :string)
  add_to_class(:category, :journal?) { ActiveModel::Type::Boolean.new.cast(custom_fields["journal"]) }
  add_to_class(:category, :journal_author_groups) {
    if custom_fields["journal_author_groups"].present?
      custom_fields["journal_author_groups"].split("|")
    else
      []
    end
  }

  # topic can be nil outside a topic view, e.g. a post whose topic was deleted.
  add_to_class(:post, :journal?) { !!topic&.journal? }
  add_to_class(:post, :entry?) { journal? && topic.journal_post_map[id]&.second.blank? }
  add_to_class(:post, :comment?) { journal? && topic.journal_post_map[id]&.second.present? }
  add_to_class(:post, :entry_post_id) { entry? ? id : topic.journal_post_map[id]&.second }
  add_to_class(:post, :comment_position) { journal? ? topic.journal_post_map[id]&.third : nil }
  add_to_class(:post, :entry_comment_count) { journal? ? topic.journal_post_map[id]&.fourth : nil }

  # CategoryList reads Site.preloaded_category_custom_fields directly now.
  %w(journal journal_author_groups).each do |field|
    Site.preloaded_category_custom_fields << field if Site.respond_to? :preloaded_category_custom_fields
  end

  add_to_serializer(:basic_category, :journal) { object.journal? }
  add_to_serializer(
    :basic_category,
    :journal_author_groups,
    include_condition: -> { SiteSetting.journal_enabled && object.journal? }
  ) { object.journal_author_groups }

  add_to_serializer(:post, :journal) { object.journal? }
  add_to_serializer(
    :post,
    :entry,
    include_condition: -> { SiteSetting.journal_enabled && object.journal? }
  ) { object.entry? }
  add_to_serializer(
    :post,
    :comment,
    include_condition: -> { SiteSetting.journal_enabled && object.journal? }
  ) { object.comment? }
  add_to_serializer(
    :post,
    :entry_post_id,
    include_condition: -> { SiteSetting.journal_enabled && object.journal? }
  ) { object.entry_post_id }
  add_to_serializer(
    :post,
    :comment_position,
    include_condition: -> { SiteSetting.journal_enabled && object.journal? }
  ) { object.comment_position }
  add_to_serializer(
    :post,
    :entry_comment_count,
    include_condition: -> { SiteSetting.journal_enabled && object.journal? }
  ) { object.entry_comment_count }

  add_to_serializer(:topic_view, :journal) { object.topic.journal? }
  add_to_serializer(
    :topic_view,
    :journal_author,
    include_condition: -> {
      SiteSetting.journal_enabled && object.topic.journal? &&
        object.topic.journal_author.present?
    }
  ) { BasicUserSerializer.new(object.topic.journal_author, scope: scope, root: false) }
  add_to_serializer(
    :topic_view,
    :entry_count,
    include_condition: -> { SiteSetting.journal_enabled && object.topic.journal? }
  ) { object.topic.entry_count }
  add_to_serializer(
    :topic_view,
    :comment_count,
    include_condition: -> { SiteSetting.journal_enabled && object.topic.journal? }
  ) { object.topic.comment_count }
  add_to_serializer(
    :topic_view,
    :entry_post_ids,
    include_condition: -> { SiteSetting.journal_enabled && object.topic.journal? }
  ) { object.topic.entries.map(&:id) }
  add_to_serializer(
    :topic_view,
    :last_entry_post_number,
    include_condition: -> { SiteSetting.journal_enabled && object.topic.journal? }
  ) { object.topic.entries.last&.post_number }
  add_to_serializer(
    :topic_view,
    :can_create_entry,
    include_condition: -> { SiteSetting.journal_enabled && object.topic.journal? }
  ) { scope&.user && scope.can_create_entry_on_topic?(object.topic) }

  add_to_serializer(:topic_list_item, :journal) { object.journal? }
  add_to_serializer(
    :topic_list_item,
    :entry_count,
    include_condition: -> { SiteSetting.journal_enabled && object.journal? }
  ) { object.entry_count }

  on(:post_created) do |post, opts, user|
    post.topic.journal_update_sort_order if post.topic&.journal?
  end
end
