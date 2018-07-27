# frozen_string_literal: true

require 'English'

require 'telegram/bot'
require 'active_record'
require 'net/http'
require 'yaml'
require 'uri'
require 'unicode'
require 'r18n-core'
require 'r18n-rails-api'

# SearchNDroch Bot namespace
module SND
  # Configuration class
  class Config
    include Singleton

    attr_reader :options

    CONFIG_PATH = "#{__FILE__}.yml"

    def initialize
      @options = YAML.load_file CONFIG_PATH
    end
  end

  def self.cfg
    SND::Config.instance
  end

  def self.libdir
    "#{File.dirname(__FILE__)}/#{SND.cfg.options['libdir']}"
  end
end

$LOAD_PATH.unshift(SND.libdir)

require 'log/snd_logger'
Dir["#{SND.libdir}/errors/*.rb"].each { |f| require f }
require 'parser/snd_spreadsheet_parser'
require 'telegram/snd_telegram'
require 'db/snd_game'
require 'db/snd_chat'

R18n::Filters.on(:named_variables)
R18n.default_places = "#{SND.libdir}/../i18n/"
R18n.set('ru')

# Main class for Search'N'Droch bot
class SearchndrochBot
  include R18n::Helpers
  attr_reader :token, :client, :chat

  def initialize
    @token = SND.cfg.options['tg_token']
    @client = Telegram::Bot::Client.new(@token)
  end

  def update(data)
    update = Telegram::Bot::Types::Update.new(data)
    message = update.message
    @time = Time.at(message.date)

    process_message(message) unless message.nil?
  rescue SND::ErrorBase
    $ERROR_INFO.process
  rescue StandardError
    SND.log.error "#{$ERROR_INFO.message}\n#{$ERROR_INFO.backtrace.join("\n")}"
  end

  def process_message(message)
    @chat = SND::Chat.identify(message)

    if message.text
      meth = method_from_message(message.text)
      send(meth, message.text) if respond_to? meth.to_sym, true
      cmd_code(message.text)
    elsif message.document
      process_file(message.document)
    end
  end

  # Start/stop games by cron
  def process
    SND::Game.start_games
    SND::Game.finish_games
  end

  private

  def method_from_message(text)
    meth = (text || '').downcase
    [%r{\@.*$}, %r{\s.*$}, %r{^/}].each { |x| meth.gsub!(x, '') }

    SND.log.info "#{meth} command from #{chat.chat_id}"
    SND.log.debug "Full command is #{text}"

    "cmd_#{meth}"
  end

  def cmd_delete(msg)
    game_id = msg.sub(%r{/delete\s*}, '').to_i

    SND::Game.load_own_game(chat, game_id).destroy

    chat.send_message(text: t.delete.success(id: game_id))
  end

  def cmd_list(_msg)
    games = chat.games_print
    message = t.list.games(list: games.join("\n"))
    message = t.list.nogames if games.size.zero?
    chat.send_message(text: message)
  end

  def cmd_join(msg)
    args = parse_args(%r{^\/join\s}, msg)

    game = SND::Game.load_game(chat, args.shift)
    game.players << chat
    chat.send_message text: t.join.success(id: game.id)
  end

  def cmd_status(_msg)
    chat.send_message text: chat.status_print
  end

  def cmd_move_start(msg)
    args = parse_args(%r{^\/move_start\s}, msg)

    game = SND::Game.load_own_game(chat, args.shift)
    game.update_start(args.join(' '))

    chat.send_message(
      text: t.move_start.success(
        id: game.id,
        start: l(game.start, '%F %T %z')
      )
    )
  end

  def cmd_task(_msg)
    chat.send_message(text: chat.task_print)
  end

  def cmd_info(_msg)
    chat.send_message(text: chat.info_print)
  end

  def cmd_code(msg)
    return unless msg =~ %r{^#}
    chat.send_message(text: chat.send_code(Unicode.downcase(msg[1..-1]), @time))
  end

  def cmd_stat(msg)
    args = parse_args(%r{^\/stat\s}, msg)

    return chat.send_message(text: chat.stat_print) if args.empty?

    game = SND::Game.load_game(chat, args.shift)
    chat.send_message(text: chat.stat_print(game))
  end

  def process_file(document)
    file = SND::Tlg.instance.download_file(document)
    ext = File.extname(file.path).delete('.')
    raise 'Invalid file format' unless %w[ods xls xlsx].include? ext

    game = parse_spreadsheet(file, ext.to_sym)
    file.unlink

    chat.own_games << SND::Game.create_game(game)
  end

  def parse_spreadsheet(file, ext)
    @sp = SND::SpreadsheetParser.new(file, extension: ext)
    @sp.valid? ? @sp.to_hash : nil
    # TODO: raise exception
  end

  def parse_args(preg, msg)
    msg.gsub(preg, '').gsub(%r{\s+}m, ' ').strip.split(' ')
  end
end
