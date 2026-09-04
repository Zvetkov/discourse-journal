# frozen_string_literal: true

module DiscourseJournal
  module GuardianExtension
    # Only the category-permission check is relaxed for authors. Core's
    # can_create_post_on_topic? keeps its closed/archived/trashed checks and
    # delegates here, so authors can't post into a closed journal.
    def can_create_post?(parent)
      can_create_entry_on_topic?(parent) || super
    end

    def can_create_entry_on_topic?(topic)
      return false if !topic&.journal?
      return false if !authenticated?

      user_in_author_groups(topic) || user_created_topic(topic)
    end

    def user_created_topic(topic)
      @user.present? && @user.id == topic&.user_id
    end

    def can_wiki?(post)
      !post&.topic&.journal? && super
    end

    def user_in_author_groups(topic)
      author_groups = topic&.category&.journal_author_groups || []
      return false if author_groups.blank?
      return true if author_groups.include?("everyone")

      @user.present? && (author_groups & @user.groups.pluck(:name)).any?
    end
  end
end
