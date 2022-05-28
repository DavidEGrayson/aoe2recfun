#!/usr/bin/env ruby
#
# This script DOES NOT WORK YET, but it attempts to anonymize the players in
# in a recording by changing their names to P1, P2, etc.
#
# Usage:
# ./anonymize.rb INPUT -o OUTPUT

require 'json'
require_relative 'aoe2rec'

$stdout.sync = true

def open_input_file(filename)
  File.open(filename, 'rb') { |f| StringIO.new f.read }
end

def change_de_string(header, offset, value)
  h = header.fetch(:inflated_header)
  value = value.dup.force_encoding('BINARY')

  separator, length = h[offset, 4].unpack('SS') + [value]
  raise if separator != 2656

  h[offset, 4 + length] = [separator, value.size].pack('SS') + value
end

def set_player_name(header, player, name)
  player[:name] = name
  change_de_string(header, player.fetch(:name_offset), name)
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
  puts "Usage: ./merge.rb INPUT ... -o OUTPUT"
  exit 1
end

input_filename = input_filenames.fetch(0)

# Open input and parse its header.
input = open_input_file(input_filename)
header = aoe2rec_parse_header(input)

header[:players].reverse_each do |pi|
  #puts "ID %d: %d %-20s" % [
  #  pi.fetch(:player_id), pi.fetch(:color_id) + 1, pi.fetch(:name),
  #]

  set_player_name(header, pi, "P" + (pi.fetch(:color_id) + 1).to_s)
end
puts

output = StringIO.new
output.write(aoe2rec_encode_header(header))
output.write(input.read)

File.open(output_filename, 'wb') do |f|
  f.write output.string
end
