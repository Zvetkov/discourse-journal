# frozen_string_literal: true

module DiscourseJournal
  module PostCreatorExtension
    # Entries (posts with no reply_to_post_number) may only be created by the
    # journal's authors; comments are open to anyone who can post on the topic.
    #
    # `valid?` nils out @topic/@post before doing its work, so @topic is only
    # available after super and @post never is - hence reading the opts directly.
    def valid?
      return false unless super
      return true unless journal_entry_restricted?
      return true if guardian.can_create_entry_on_topic?(@topic)

      errors.add(:base, I18n.t("journal.errors.cannot_create_entry"))
      false
    end

    private

    def journal_entry_restricted?
      return false if !@topic&.journal?

      # Moderator actions, small actions and whispers are topic chrome rather
      # than journal entries. Core sets @topic before its own skip_validations
      # early-exit, so without this the gate would block Topic#add_moderator_post
      # (close, pin, split notices) for anyone outside the author groups.
      return false if skip_validations?
      return false if @opts[:post_type].present? && @opts[:post_type] != Post.types[:regular]

      @opts[:reply_to_post_number].blank?
    end
  end
end
