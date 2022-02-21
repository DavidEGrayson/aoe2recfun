#!/usr/bin/env ruby
# Command-line utility for merging recorded game files together so that
# you get the chat and viewlock for all players in one file.
#
# Usage:
# ./merge.rb INPUT1 INPUT2 ... -o OUTPUT

# TODO: fix this so it doesn't destroy chapters
# TODO: (possibly related) Why does a merged replay with chapters stop
# playing?  Are the chapters essential for the replay to work?

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

def chat_should_be_merged?(json)
  # Skip all-chat, since that will show up fine in every file.
  return false if json.fetch(:channel) == 1

  # Skip metadata messages from this program.
  return false if json.fetch(:channel) == 100

  # Skip age advancement messages (and weird messages from other games,
  # where messageAGP is empty).
  return false if !json.fetch(:messageAGP).include?(':')

  true
end

def censor_chat(msg)
  msg = msg.sub(/\bsimp\b/, '****')
  msg
end

def update_chat_message_agp(chat, players)
  from = chat.fetch(:player)
  if from != 0
    color_code = '@#' + from.to_s
    from_info = players.fetch(from - 1)
    from_color_num = from_info.fetch(:color_id) + 1
    from_name = from_info.fetch(:name)
    from_label = "#{from_color_num} #{from_name}: "
  end

  to_color_numbers = chat.fetch(:to).collect do |id|
    players.fetch(id - 1).fetch(:color_id) + 1
  end.uniq.sort
  to_color_numbers.delete(from_color_num) if from_color_num

  # Note: I'm assuming that if one player controlling a force gets a message,
  # all of the players did.  If that's not the case, maybe we need some sort of
  # more complex notation to show who the messages are directed to.
  to_all = players.all? do |pl|
    to_color_num = pl.fetch(:color_id) + 1
    to_color_num == from_color_num || to_color_numbers.include?(to_color_num)
  end

  if to_all
    to_label = '<All>'
  elsif to_color_numbers.size == 0
    to_label = ''
  else
    to_label = '<' + to_color_numbers.join(',') + '>'
  end

  msg = censor_chat(chat.fetch(:message))

  chat[:messageAGP] = "#{color_code}#{to_label}#{from_label}#{msg}"

  chat[:message] = "#{to_label + ' ' unless to_all}#{msg}"
end

def format_chat(chat)
  json = JSON.dump(
    player: chat.fetch(:player),
    channel: chat.fetch(:channel),
    message: chat.fetch(:message),
    messageAGP: chat.fetch(:messageAGP),
  ).b
  [4, -1, json.size].pack('LlL') + json
end

# TODO: use pretty_chat
def colorize_chat(msg, player_info)
  msg.sub(/\A@#(\d)/) do
    player_id = $1.to_i
    color = player_info.fetch(player_id).fetch(:color_number) rescue 0
    AOE2_VT100_COLORS.fetch(color)
  end + AOE2_VT100_COLORS[0]
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
    force_id: header.fetch(:force_id),
    time: 0,
  }

  if header.fetch(:next_chapter) != 0
    raise "Merging games with chapters does not work yet; replay ends after 1st chapter."
  end
end

# Check the headers for consistency after masking out fields that we expect
# to be inconsistent.
consistent_headers = inputs.collect do |input|
  input[:header].merge(force_id: nil, inflated_header: nil, next_chapter: nil)
end
consistent_headers.each do |header|
  header[:dat_crc] = 0
  if header != consistent_headers[0]
    $stderr.puts "WARNING: These recorded games have inconsistent headers!"
    $stderr.puts "Are they really all from the same game?"
    header.keys.each do |key|
      if header[key] != consistent_headers[0][key]
        $stderr.puts "(Field #{key} is one field that is inconsistent.)"
        break
      end
    end
    break
  end
end
header = inputs[0][:header]

# Build a player info hash so we can get handy info from player IDs.
@player_info = {}
header[:players].each do |pl|
  @player_info[pl.fetch(:player_id)] = {
    player_id: pl.fetch(:player_id),
    force_id: pl.fetch(:force_id),
    color_number: pl.fetch(:color_id) + 1,
    name: pl.fetch(:name),
  }
end

# Match inputs to players.  This is made complicated by co-op games: I don't
# know where to find the actual player ID, all we have is the force ID.
# For each recording that has a force ID corresponding to a co-op team, I'll
# just assign it to one of the players of that force that doesn't have an
# input already.
inputs.each do |input|
  @player_info.each do |index, pl|
    if input.fetch(:force_id) == pl.fetch(:force_id) && !pl[:input]
      pl[:input] = input
      input[:player_id] = pl.fetch(:player_id)
      break
    end
  end
end


# Print a summary of the players
puts "Map: #{aoe2de_map_name(header.fetch(:resolved_map_id))}"
puts "Players:"
@player_info.each do |id, pi|
  puts "ID %d, FID %d: %d %-20s %s" % [
    id, pi.fetch(:force_id), pi.fetch(:color_number), pi.fetch(:name),
    pi[:input]&.fetch(:filename) || 'No recorded game',
  ]
end
puts

# Print a summary of the inputs
puts "Input replays:"
inputs.each do |input|
  puts "%s: FID=%d" % [input.fetch(:filename), input.fetch(:force_id)]
end
puts

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
        input[:time] += op.fetch(:time_increment)
        time_increment ||= op.fetch(:time_increment)
        if time_increment != op.fetch(:time_increment)
          raise "Inconsistent time increments!  Are all files really from the same game?"
        end
        break
      end
      if op[:operation] == :chat
        chat = JSON.parse(op.fetch(:json), symbolize_names: true)
        if chat_should_be_merged?(chat)
          chat.merge! time: time, to: [input.fetch(:player_id)]
          chats << chat
        end
      end
    end
  end
  break if !data_remaining
  time += time_increment if time_increment
end

inputs.each { |input| input.fetch(:io).close }

# Print the mergable chats for debugging.
#chats.each do |chat|
#  puts "#{chat.fetch(:time)} #{chat[:player]}->#{chat[:to]}: " + colorize_chat(chat.fetch(:messageAGP), @player_info)
#end

# Merge the chat messages
players_included = []
@player_info.each do |id, pl|
  if pl[:input]
    players_included << "#{pl.fetch(:color_number)} #{pl.fetch(:name)}"
  end
end
if players_included.size == @player_info.size
  welcome = "This replay contains all chats."
else
  welcome = "This replay contains any chats from/to " + players_included.join(', ') + "."
end
merged_chats = [
  { time: 200, player: 0, to: [], channel: 1, message: welcome },
]
merged_chats += merge_chats_core(chats)
merged_chats.each do |chat|
  update_chat_message_agp(chat, header.fetch(:players))
end

# Select the main input: the first full-length recording.
full_time = inputs.map { |input| input.fetch(:time) }.max
main_input = inputs.first { |inputs| input.fetch(:time) == full_time }
puts "Selected main input: #{main_input.fetch(:filename)}"
puts

# Copy from the main input to the output, while fixing the chat.
input = InputWrapper.new(open_input_file(main_input.fetch(:filename)))
output = StringIO.new
aoe2rec_parse_header(input)
binary_header = input.flush_recently_read

# Set the next chapter address to 0 since we don't have the code needed to
# actually copy the chapter data to the output or update this address.
binary_header[4, 4] = "\x00\x00\x00\x00".b

output.write(binary_header)
time = 0
while true
  op = aoe2rec_parse_operation(input)
  break if op.nil?

  if op[:operation] == :sync
    time += op.fetch(:time_increment)
  end

  while !merged_chats.empty? && merged_chats.first.fetch(:time) <= time
    chat = merged_chats.shift
    puts "%6d: %s" % [time/1000, colorize_chat(chat.fetch(:messageAGP), @player_info)]
    output.write(format_chat(chat))
  end

  if op[:operation] == :chat
    chat = JSON.parse(op.fetch(:json), symbolize_names: true)
    if chat_should_be_merged?(chat)
      input.flush_recently_read
    elsif chat[:messageAGP].empty?
    else
      puts "%6d: %s" % [time/1000, colorize_chat(chat.fetch(:messageAGP), @player_info)]
    end
  end

  output.write(input.flush_recently_read)
end

File.open(output_filename, 'wb') do |f|
  f.write output.string
end
