# frozen_string_literal: true

require 'db/snd_base'
require 'db/snd_code'

module SND
  # Level class
  class Level < SNDBase
    belongs_to :game
    has_many :codes, dependent: :destroy

    def self.create_level(hash)
      level = Level.create(
        name: hash[:name],
        task: hash[:task],
        duration: hash[:duration],
        to_pass: hash[:to_pass]
      )

      hash[:codes].each do |c|
        level.codes << Code.create(value_hash: c[:code], bonus: c[:bonus])
      end

      level
    end

    def check_code(code)
      codes.where(value_hash: Digest::MD5.hexdigest(code)).first
    end

    def status_print(chat)
      result = chat_stat_hash(chat.id)
      return t.game.code.alldone if result[:left].empty?
      t.game.status result
    end

    def task_print(chat)
      {
        text: t.level.task(
          name: name,
          task: task,
          time: time_left(chat.id)
        ),
        parse_mode: 'HTML'
      }
    end

    def time_left_sec(_chat_id = nil)
      # length of all previous levels in minutes
      prev = game.minutes_until(self).minutes

      duration.minutes - (Time.now.to_i - game.start.to_i - prev)
    end

    def time_left(chat_id = nil)
      Time.at(time_left_sec(chat_id)).utc.strftime('%H:%M:%S')
    end

    private

    # If array contains less than 3 elements, all of them are listed
    # else only first and last elements are displayed
    def compact_list(list)
      return list.join(',') if list.size < 3
      "#{list.min}-#{list.max}"
    end

    def closed_codes(chat_id)
      codes.joins(:bonuses).where(bonuses: { chat: chat_id })
    end

    # Return list of unclosed codes ID for given chat
    def chat_unclosed_indexes(chat_id)
      closed = closed_codes(chat_id).order(:id).ids
      codes.each_with_index.map do |code, index|
        index + 1 unless closed.include?(code.id)
      end
    end

    def chat_stat_hash(chat_id)
      closed = closed_codes(chat_id)
      {
        left: group_indexes(chat_unclosed_indexes(chat_id)).join(','),
        left_count: to_pass - closed.size,
        codes: closed.size,
        points: closed.map(&:bonus).inject(0, &:+),
        time: time_left(chat_id)
      }
    end

    # Remove empty subarrays and compact lists
    def group_indexes(data)
      result = [c = []]
      data.each do |ind|
        ind.nil? ? (result << c = []) : (c << ind)
      end
      result = result.reject(&:empty?).map { |x| compact_list(x) }
    end
  end
end
