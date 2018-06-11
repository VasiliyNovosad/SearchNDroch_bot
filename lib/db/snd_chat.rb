# frozen_string_literal: true

require 'db/snd_base'
require 'db/snd_game_player'

module SND
  # Chat class
  class Chat < SNDBase
    has_many :own_games, class_name: 'Game', after_add: :added_game
    has_many :bonuses
    has_many :game_players

    has_many :games, through: :game_players

    def send_message(options)
      raise ArgumentError, 'Parameter should be hash' unless options.is_a? Hash
      raise ArgumentError, 'Missing message text' unless options.key? :text
      SND.tlg.api.send_message(options.merge(chat_id: chat_id))
    rescue StandardError
      SND.log.error $ERROR_INFO.message
    end

    def games_print
      own_games.map { |g| "##{g.id}: [#{g.start}] #{g.name}" }
    end

    def task_print
      active_game.level.task
    end

    def info_print
      active_game.info_print
    end

    def send_code(ucode, time)
      code = active_game.level.check_code(ucode)
      return t.game.code.invalid(code: ucode) unless code

      code.bonuses << SND::Bonus.create(
        chat: self,
        code: code,
        time: time
      )
      t.game.code.valid(code: ucode)
    end

    def added_game(game)
      send_message(text: t.create.success(id: game.id))
    end

    def self.identify(message)
      chat = Chat.find_or_create_by(chat_id: message.chat.id)
      chat.update_attribute(
        :name,
        "#{message.from.first_name} #{message.from.last_name}"
      )
      chat
    end

    private

    def active_game
      game = games.where(status: 'Running').first
      raise SND::GameNotRunning if game.nil?
      game
    end
  end
end
