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

def anonymize_chat(chat, name_map)
  chat = chat.dup
  name_map.each do |old_name, new_name|
    chat[:message] = chat[:message].gsub(old_name, new_name)
    chat[:messageAGP] = chat[:messageAGP].gsub(old_name, new_name)
  end
  chat
end

def binary_string_pad(str, size)
  str.ljust(size, "\x00")[0, size]
end

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

def change_u32(header, offset, value)
  header.fetch(:inflated_header)[offset, 4] = [value].pack('L')
end

# TODO: don't go through so much effort to preserve the header size, because
# the size gets messed up when we compress it with zlib anyway.
def set_player_ai_name(header, player, ai_name)
  ai_name = ai_name.dup.force_encoding('BINARY')

  ih = header[:inflated_header]
  orig_inflated_header_size = ih.size
  orig_name = player[:name]
  orig_total_name_size = orig_name.size + player[:ai_name].size

  ai_name = ai_name[0, orig_total_name_size]
  name = "\x00" * (orig_total_name_size - ai_name.size)

  player[:name] = name
  change_de_string(header, player.fetch(:name_offset), name)
  player[:ai_name] = ai_name
  change_de_string(header, player.fetch(:ai_name_offset), ai_name)

  search = [orig_name.size + 1].pack('S') + orig_name + "\x00"
  index = ih.index(search)
  if !index
    raise "Cannot find second instance of player name in header."
  end
  ih[index + 2, orig_name.size] = binary_string_pad(ai_name, orig_name.size)
  if ih.include?(search)
    raise "Name found more than once in the header."
  end

  if orig_inflated_header_size != header[:inflated_header].size
    raise "Accidentally changed header size"
  end
end

def set_profile_id(header, player, id)
  player[:profile_id] = id
  change_u32(header, player.fetch(:profile_id_offset), id)
end

def set_player_type(header, player, id)
  player[:type] = id
  change_u32(header, player.fetch(:type_offset), id)
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
input = InputWrapper.new(open_input_file(input_filename))
header = aoe2rec_parse_header(input)

name_map = {}
header[:players].reverse_each do |pi|
  new_name = "P" + (pi.fetch(:color_id) + 1).to_s
  name_map[pi.fetch(:name)] = new_name

  #puts "%d %-20s profile=%d" % [
  #  pi.fetch(:color_id) + 1, pi.fetch(:name), pi.fetch(:profile_id)
  #]

  set_profile_id(header, pi, 0)
  set_player_type(header, pi, 4)  # change player type to computer
  set_player_ai_name(header, pi, new_name)
end
puts

output = StringIO.new
output.write(aoe2rec_encode_header(header))

time = 0
input.flush_recently_read
while true
  op = aoe2rec_parse_operation(input)
  break if op.nil?

  if op[:operation] == :sync
    time += op.fetch(:time_increment)
  end

  if op[:operation] == :chat
    input.flush_recently_read
    chat = JSON.parse(op.fetch(:json), symbolize_names: true)
    chat[:time] = time
    anon_chat = anonymize_chat(chat, name_map)
    output.write(aoe2rec_encode_chat(anon_chat))
  else
    output.write(input.flush_recently_read)
  end
end

File.open(output_filename, 'wb') do |f|
  f.write output.string
end
