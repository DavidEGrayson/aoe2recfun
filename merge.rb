#!/usr/bin/env ruby
# Command-line utility for merging recorded game files together so that
# you get the chat and viewlock for all players in one file.
#
# Usage:
# ./merge.rb INPUT1 INPUT2 ... -o OUTPUT

# TODO: merge chat
# TODO: merge flares (flare is an action!)
# TODO: merge view lock

require 'json'
require_relative 'aoe2rec'

$stdout.sync = true

# AOE2 recorded games are small enough that we should just read them in all at
# once, and this makes the program about 15x faster.
def open_input_file(filename)
  File.open(filename, 'rb') { |f| StringIO.new f.read }
end

def open_output_file(filename)
  File.open(filename, 'wb')
end

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

# Parse the arguments
input_filenames = []
output_filename = nil
arg_enum = ARGV.each
loop do
  arg = arg_enum.next
  if arg.start_with?('-')
    if arg == '-o'
      output_filename = arg_enum.next
    else
      raise "Unknown option: #{arg}"
    end
  else
    input_filenames << arg
  end
end
if output_filename.nil? || input_filenames.size < 2
  puts "Usage: ./merge.rb INPUT1 INPUT2 ... -o OUTPUT"
  exit 1
end

# Open each file and parse its header.
inputs = []
input_filenames.each do |filename|
  io = open_input_file(filename)
  header = aoe2rec_parse_header(io)
  inputs << {
    filename: filename,
    io: io,
    header: header,
    player_id: header.fetch(:player_id)
  }
end

# Check the headers for consistency after masking out fields that we expect
# to be inconsistent.
consistent_headers = inputs.collect do |input|
  input[:header].merge(player_id: nil)
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
inputs[0][:header][:players].each do |pl|
  @player_info[pl.fetch(:player_id)] = {
    color_number: pl.fetch(:color_id) + 1,
    name: pl.fetch(:name),
    input: inputs.find { |input| input[:player_id] == pl.fetch(:player_id) }
  }
end

# Print a summary of the players
puts "Players:"
@player_info.each do |id, pi|
  puts "ID %d: %d %-20s %s" % [
    id, pi.fetch(:color_number), pi.fetch(:name),
    pi[:input]&.fetch(:filename) || 'No recorded game',
  ]
end

puts "Scanning for mergeable chat messages from input files..."
time = 0
chats = []
while true
  data_remaining = false
  time_increment = nil
  # Read each input up to the next synchronization point or EOF.
  inputs.each do |input|
    while true
      op = aoe2rec_parse_operation(input[:io])
      break if op.nil?  # Handle EOF
      data_remaining = true
      if op[:operation] == :sync
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
            to: input.fetch(:player_id),
            channel: json.fetch('channel'),
            message: json.fetch('message'),
          }
        end
      end
    end
  end
  break if !data_remaining
  time += time_increment if time_increment
end

inputs.each { |input| input.fetch(:io).close }

# Merge the chat messages
players_included = []
@player_info.each do |id, pl|
  if pl[:filename]
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

input = InputWrapper.new(open_input_file(input_filenames.first))
output = open_output_file(output_filename)

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
    chat = merged_chats.shift
    puts chat
    output.write(format_merged_chat(chat))
  end

  if op[:operation] == :chat
    json = JSON.parse(op.fetch(:json))
    puts json
    if chat_should_be_merged?(json)
      input.flush_recently_read
    end
  end

  output.write(input.flush_recently_read)
end

