# frozen_string_literal: true

module DiscourseJournal
  module TopicExtension
    def self.prepended(base)
      base.extend(ClassMethods)
    end

    def reload(options = nil)
      @entries = nil
      @comments = nil
      @journal_author = nil
      @journal_post_map = nil
      super(options)
    end

    def entries
      @entries ||= regular_posts.where(reply_to_post_number: nil).order('created_at ASC')
    end

    def comments
      @comments ||= regular_posts.where.not(reply_to_post_number: nil).order('created_at ASC')
    end

    # Small actions, moderator posts and whispers are topic chrome. They are
    # not entries or counted comments, and non-staff never receive whispers, so
    # numbering them would leave gaps in what those readers see.
    def regular_posts
      posts.where(post_type: Post.types[:regular])
    end

    def entry_count
      entries.count
    end

    def comment_count
      comments.count
    end

    def journal_author
      return if entries.empty?
      @journal_author ||= User.find_by(id: entries.last[:user_id])
    end

    def journal?
      return false unless SiteSetting.journal_enabled
      return false if is_category_topic?
      category.present? && category.journal?
    end

    # Maps each post in a journal topic to its position in the journal.
    #
    # Entries:  [sort_order, nil,      nil,              comment_count]
    # Comments: [sort_order, entry_id, comment_position, comment_count]
    #
    # comment_position and comment_count are serialized onto the post so the
    # client can decide comment visibility without walking the post stream.
    # Entries carry comment_count too, so the "show comments" toggle can attach
    # to the entry when journal_comments_default is 0.
    #
    # comment_position is 1-based on purpose: Post#updateFromPost coerces falsy
    # values to null when refreshing a post, so a 0 would silently disappear on
    # the next message-bus update.
    #
    # Deleted and non-regular posts keep their sort_order slot (staff can see
    # them) but are skipped when numbering comments, so they don't eat a slot
    # that other readers can't see.
    #
    # Only append to the tuple - journal_update_sort_order reads .first and
    # Post#entry_post_id reads .second.
    def journal_post_map
      @journal_post_map ||= begin
        map = {}
        post_number = 1

        top_level = posts.with_deleted.where(reply_to_post_number: nil).order('created_at ASC')

        top_level.each do |entry|
          replies = self.class.gather_replies(entry).sort_by(&:created_at)
          comment_count = replies.count { |reply| counted_comment?(reply) }
          position = 0

          map[entry.id] = [post_number, nil, nil, comment_count]

          replies.each do |reply|
            post_number += 1
            position += 1 if counted_comment?(reply)
            map[reply.id] = [post_number, entry.id, (counted_comment?(reply) ? position : nil), comment_count]
          end

          post_number += 1
        end

        map
      end
    end

    def counted_comment?(post)
      !post.trashed? && post.post_type == Post.types[:regular]
    end

    def journal_update_sort_order
      return unless SiteSetting.journal_enabled
      # An empty map would render `VALUES ` and take the whole batch job down.
      return if journal_post_map.empty?

      post_map_values = journal_post_map.map do |post_id, attrs|
        "(#{post_id}::int,#{attrs.first}::int)"
      end.join(",")

      Post.transaction do
        DB.exec <<~SQL
          WITH ordered_posts (id, new_sort_order) AS (
            VALUES #{post_map_values}
          )
          UPDATE
            posts as p
          SET
            sort_order = o.new_sort_order
          FROM
            ordered_posts AS o
          WHERE
            p.id = o.id AND
            p.topic_id = #{self.id}
        SQL
      end
    end

    module ClassMethods
      def gather_replies(post, replies = [])
        post_replies = Post.with_deleted.where(
          topic_id: post.topic_id,
          reply_to_post_number: post.post_number
        )

        return [] if post_replies.empty?

        post_replies.each do |reply|
          replies << reply
          replies_to_reply = gather_replies(reply)
          replies += replies_to_reply if replies_to_reply.any?
        end

        return replies
      end
    end
  end
end
