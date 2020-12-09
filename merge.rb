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

  # Skip age advancement messages (and weird messages from other games,
  # where messageAGP is empty).
  return false if !json.fetch('messageAGP').include?(':')

  true
end

def format_merged_chat(info)
  color_code = '@#' + info.fetch(:from).to_s
  to_label = '<' + info.fetch(:to).join(',') + '>' # TODO: real player numbers
  from_name = "3 Elavid"  # TODO: real player number and name
  msg = info.fetch(:message)

  json = JSON.dump(
    'player' => info.fetch(:from),
    'channel' => info.fetch(:channel),
    'message' => msg,
    'messageAGP' => "#{color_code}#{to_label}#{from_name}: #{msg}"
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

puts "Scanning for mergeable chat messages from input files..."
player_ids = {}
inputs.each do |io|
  aoe2rec_parse_header(io)
  meta = aoe2rec_parse_meta(io)
  puts "#{io.path}: #{meta}"
  player_ids[io] = meta.fetch(:player_id)
end

time = 0
chats = []
while true
  data_remaining = false
  time_increment = nil
  # Read each input up to the next synchronization point or EOF.
  inputs.each do |io|
    while true
      op = aoe2rec_parse_operation(io)
      #puts "PID#{player_ids.fetch(io)}: #{op.inspect}"
      break if op.nil?  # Handle EOF
      data_remaining = true
      if op[:operation] == :sync
        #puts "PID#{player_ids.fetch(io)}: sync #{op.fetch(:time_increment)}"
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
            to: player_ids.fetch(io),
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

# tmphax
merged_chats = [
  { time: 10000, from: 2, to: [1,3], channel: 0, message: "hi1" },
  { time: 11000, from: 2, to: [1,3], channel: 0, message: "hi2 @#1 hi2" },
]

puts
puts "Merged chat messages:"
merged_chats.each do |chat|
  puts chat
end

input = File.open(input_filenames.first, 'rb')
input = InputWrapper.new(input)

output = File.open(output_filename, 'wb')

aoe2rec_parse_header(input)
aoe2rec_parse_meta(input)
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

