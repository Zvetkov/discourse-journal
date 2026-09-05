# frozen_string_literal: true

# name: discourse-journal
# about: Create journals in discourse
# version: 0.4.4
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
  # Prepended: Topic defines its own reload, which an included module can't override.
  ::Topic.prepend DiscourseJournal::TopicExtension
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
  add_to_class(:post, :journal_map_entry) { topic.journal_post_map[id] if journal? }
  # A post absent from the map (e.g. a dangling reply number) is neither an
  # entry nor a comment. Small actions, moderator posts and whispers hold a
  # slot for sort order but are topic chrome, not entries.
  add_to_class(:post, :entry?) {
    journal_map_entry.present? && journal_map_entry.second.blank? &&
      post_type == Post.types[:regular]
  }
  add_to_class(:post, :comment?) { journal_map_entry.present? && journal_map_entry.second.present? }
  add_to_class(:post, :entry_post_id) { entry? ? id : journal_map_entry&.second }
  add_to_class(:post, :comment_position) { journal_map_entry&.third }
  add_to_class(:post, :entry_comment_count) { journal_map_entry&.fourth }

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
  ) {
    scope&.user.present? && scope.can_create_entry_on_topic?(object.topic) &&
      scope.can_create_post_on_topic?(object.topic)
  }

  add_to_serializer(:topic_list_item, :journal) { object.journal? }
  add_to_serializer(
    :topic_list_item,
    :entry_count,
    include_condition: -> { SiteSetting.journal_enabled && object.journal? }
  ) { object.entry_count }

  # TopicView loads posts without their topic association, so each post would
  # lazily load its own Topic instance and rebuild journal_post_map from
  # scratch. Share the view's topic so the map is computed once per request.
  TopicView.on_preload do |topic_view|
    if topic_view.topic.journal?
      topic_view.posts.each { |post| post.topic = topic_view.topic }
    end
  end

  on(:post_created) do |post, opts, user|
    post.topic.journal_update_sort_order if post.topic&.journal?
  end
end
