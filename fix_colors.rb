#!/usr/bin/env ruby
#
# This script does not work yet, but it attempts to fix player colors
# in a game where two players are shown as the same color.
# Again, it doesn't work.
#
# Usage:
# ./fix.rb INPUT -o OUTPUT

require 'json'
require_relative 'aoe2rec'

$stdout.sync = true

def open_input_file(filename)
  File.open(filename, 'rb') { |f| StringIO.new f.read }
end

def set_player_color_id(header, player_index, color_id)
  offset = header[:players][player_index].fetch(:offset) + 4
  ch = header.fetch(:inflated_header)
  ch[offset...(offset+4)] = [color_id].pack('l')
end

def set_player_selected_color(header, player_index, selected_color)
  offset = header[:players][player_index].fetch(:offset) + 8
  ch = header.fetch(:inflated_header)
  ch[offset] = [selected_color].pack('C')
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
if output_filename.nil? || input_filenames.size != 1
  puts "Usage: ./merge.rb INPUT1 INPUT2 ... -o OUTPUT"
  exit 1
end

input_filename = input_filenames.fetch(0)

# Open input and parse its header.
io = open_input_file(input_filename)
header = aoe2rec_parse_header(io)
input = {
  io: io,
  header: header,
  player_id: header.fetch(:player_id),
  time: 0,
}

# Print a summary of the players
puts "Map: #{aoe2de_map_name(header.fetch(:resolved_map_id))}"
puts "Players:"
header[:players].each do |pi|
  puts "ID %d: %d %-20s (sc=%d)" % [
    pi.fetch(:player_id), pi.fetch(:color_id) + 1, pi.fetch(:name),
    pi.fetch(:selected_color)
  ]
end
puts

# Copy from the input to the output, while fixing things.
input = open_input_file(input_filename)
output = StringIO.new
header = aoe2rec_parse_header(input)
header[:players].size.times do |i|
  # This doesn't seem to have any effect.
  set_player_selected_color(header, i, 255)
end

# This does change the number for the player: it will be 1 plus the ID given.
set_player_color_id(header, 2, 3)

output.write(aoe2rec_encode_header(header))
output.write(input.read)

File.open(output_filename, 'wb') do |f|
  f.write output.string
end
