# frozen_string_literal: true

module DiscourseJournal
  # Nested replies are a competing model to journals, and the nested view renders
  # its own post components without the post-class transformer the journal needs
  # for entry/comment styling and collapsing. Keep journals on the flat stream.
  #
  # Must be prepended: nested_view? is defined directly on ::Topic.
  module TopicNestedExtension
    def nested_view?
      return false if journal?
      super
    end
  end
end
