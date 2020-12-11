#!/usr/bin/env ruby
# Command-line utility for merging recorded game files together so that
# you get the chat and viewlock for all players in one file.
#
# Usage:
# ./merge.rb OUTPUT INPUT1 INPUT2 ...

# TODO: merge chat
# TODO: merge flares (flare is an action!)
# TODO: merge view lock

require 'json'
require_relative 'aoe2rec'

$stdout.sync = true

def chat_should_be_merged?(json)
  # Skip all-chat, since that will show up fine in every file.
  return false if json.fetch('channel') == 1

  # Skip metadata messages from this program.
  return false if json.fetch('channel') == 100

  # Skip age advancement messages (and weird messages from other games,
  # where messageAGP is empty).
  return false if !json.fetch('messageAGP').include?(':')

  true
end

def format_merged_chat(info)
  to_color_numbers = info.fetch(:to).collect do |id|
    @player_info.fetch(id).fetch(:color_number)
  end.sort
  if to_color_numbers.size == 0
    to_label = ''
  elsif to_color_numbers.size == @player_info.size
    to_label = '<All>'
  else
    to_label = '<' + to_color_numbers.join(',') + '>'
  end

  from = info.fetch(:from)
  if from != 0
    color_code = '@#' + from.to_s
    from_info = @player_info.fetch(from)
    from_name = "#{from_info.fetch(:color_number)} #{from_info.fetch(:name)}: "
  end

  msg = info.fetch(:message)

  json = JSON.dump(
    'player' => info.fetch(:from),
    'channel' => info.fetch(:channel),
    'message' => msg,
    'messageAGP' => "#{color_code}#{to_label}#{from_name}#{msg}"
  ).b

  [4, -1, json.size].pack('LlL') + json
end

filenames = ARGV.dup

if filenames.size < 2
  puts "Usage: ./merge.rb OUTPUT INPUT1 INPUT2 ..."
  exit 1
end

output_filename = filenames.shift
input_filenames = filenames
inputs = filenames.collect do |filename|
  File.open(filename, 'rb')
end

# Parse the header of each input file.
io_to_player_id = {}
headers = []
inputs.each do |io|
  headers << header = aoe2rec_parse_header(io)
  io_to_player_id[io] = header.fetch(:player_id)
end

# Check the headers for consistency after masking out fields that we expect
# to be inconsistent.
consistent_headers = headers.collect do |header|
  header.merge(player_id: nil)
end
consistent_headers.each do |header|
  header[:dat_crc] = 0
  if header != consistent_headers[0]
    $stderr.puts "WARNING: These recorded games have inconsistent headers!"
    $stderr.puts "Are they really all from the same game?"
    header.keys.each do |key|
      if header[key] != headers[0][key]
        $stderr.puts "(Field #{key} is one field that is inconsistent.)"
        break
      end
    end
    break
  end
end

# Build a player info hash so we can get handy info from player IDs.
@player_info = {}
headers[0].fetch(:players).each do |pl|
  @player_info[pl.fetch(:player_id)] = {
    color_number: pl.fetch(:color_id) + 1,
    name: pl.fetch(:name)
  }
end
inputs.each do |io|
  @player_info[io_to_player_id[io]][:path] = io.path
end

puts "Players:"
@player_info.each do |id, pi|
  puts "ID %d: %d %-20s %s" % [
    id, pi.fetch(:color_number), pi.fetch(:name),
    pi.fetch(:path, 'No recorded game')
  ]
end

puts "Scanning for mergeable chat messages from input files..."

time = 0
chats = []
while true
  data_remaining = false
  time_increment = nil
  # Read each input up to the next synchronization point or EOF.
  inputs.each do |io|
    while true
      op = aoe2rec_parse_operation(io)
      #puts "PID#{io_to_player_id.fetch(io)}: #{op.inspect}"
      break if op.nil?  # Handle EOF
      data_remaining = true
      if op[:operation] == :sync
        #puts "PID#{io_to_player_id.fetch(io)}: sync #{op.fetch(:time_increment)}"
        time_increment ||= op.fetch(:time_increment)
        if time_increment != op.fetch(:time_increment)
          raise "Inconsistent time increments!  Are all files really from the same game?"
        end
        break
      end
      if op[:operation] == :chat
        json = JSON.parse(op.fetch(:json))
        if chat_should_be_merged?(json)
          chats << {
            time: time,
            from: json.fetch('player'),
            to: io_to_player_id.fetch(io),
            channel: json.fetch('channel'),
            message: json.fetch('message'),
          }
          # puts json
          # puts chats.last
        end
      end
    end
  end
  break if !data_remaining
  time += time_increment if time_increment
end

inputs.each(&:close)

# Merge the chat messages
players_included = []
@player_info.each do |id, pl|
  if pl[:path]
    players_included << "#{pl.fetch(:color_number)} #{pl.fetch(:name)}"
  end
end
if players_included.size == @player_info.size
  players_desc = "all players"
else
  players_desc = players_included.join(', ')
end
welcome = "Merged chat enabled for #{players_desc}"
merged_chats = [
  { time: 200, from: 0, to: [], channel: 1, message: welcome },
]
last_chat = {}
chats.each do |chat|
  from = chat.fetch(:from)
  last = last_chat[from]
  if !(last && last.fetch(:message) == chat.fetch(:message))
    last = chat.dup
    merged_chats << last
    last_chat[from] = last
    last[:to] = []
  end
  last_chat[from][:to] << chat.fetch(:to)
end
merged_chats.each do |chat|
  chat.fetch(:to).delete(chat.fetch(:from))
end

puts
puts "Merged chat messages:"
merged_chats.each do |chat|
  puts chat
end

input = File.open(input_filenames.first, 'rb')
input = InputWrapper.new(input)

output = File.open(output_filename, 'wb')

aoe2rec_parse_header(input)
output.write(input.flush_recently_read)

time = 0
while true
  op = aoe2rec_parse_operation(input)
  break if op.nil?

  if op[:operation] == :sync
    time += op.fetch(:time_increment)
  end

  while !merged_chats.empty? && merged_chats.first.fetch(:time) <= time
    output.write(format_merged_chat(merged_chats.shift))
  end

  if op[:operation] == :chat
    json = JSON.parse(op.fetch(:json))
    if chat_should_be_merged?(json)
      input.flush_recently_read
    end
  end

  # TODO: write merged chats if it's time to

  output.write(input.flush_recently_read)
end

