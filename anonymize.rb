#!/usr/bin/env ruby
#
# This script DOES NOT WORK YET, but it attempts to anonymize the players in
# in a recording by changing their names to P1, P2, etc.
#
# Usage:
# ./anonymize.rb INPUT1 INPUT2 INPUT3... -o OUTPUT

require_relative 'aoe2rec'

$stdout.sync = true

def change_de_string(header, offset, value)
  h = header.fetch(:inflated_header)
  value = value.dup.force_encoding('BINARY')

  separator, length = h[offset, 4].unpack('SS') + [value]
  raise if separator != 2656

  header[:inflated_header_patches] << [
    offset, 4 + length, [separator, value.size].pack('SS') + value
  ]
end

def change_u32(header, offset, value)
  header.fetch(:inflated_header)[offset, 4] = [value].pack('L')
end

def set_player_name(header, player, name)
  name = name.dup.force_encoding('BINARY')
  orig_name = player.fetch(:name)

  # Set the profile ID in the DE header to 0 so DE doesn't have any way to
  # look up the player's name.
  player[:profile_id] = 0
  change_u32(header, player.fetch(:profile_id_offset), 0)

  # Set the player type to computer (4) in the DE header so it shows the
  # "ai name" in the replay header.  (This is how I get it to print any name
  # at all.)
  player[:type] = 4
  change_u32(header, player.fetch(:type_offset), 4)

  # Set the "name" field in the DE header to empty.  It doesn't seem to be used
  # for anything.
  player[:name] = ""
  change_de_string(header, player.fetch(:name_offset), "")

  # Set the "ai_name" to the desired name.  It is shown in the Replays tab.
  player[:ai_name] = name
  change_de_string(header, player.fetch(:ai_name_offset), name)

  # Change the other copy of the name in the header, which is shown while the
  # replay is playing.  It's hard to know where it appears so we will just
  # search for it and make sure we find it exactly once.
  search = [orig_name.size + 1].pack('S') + orig_name + "\x00"
  index = header[:inflated_header].index(search)
  if !index
    raise "Cannot find second instance of player name in header."
  end
  if header[:inflated_header].index(search, index + 1)
    raise "Name found more than once in the header."
  end
  header[:inflated_header_patches] << [
    index, search.size,
    [name.size + 1].pack('S') + name + "\x00"
  ]
end

def change_names_in_chat!(chat, name_map)
  name_map.each do |old_name, new_name|
    chat[:message] = chat[:message].gsub(old_name, new_name)
    chat[:messageAGP] = chat[:messageAGP].gsub(old_name, new_name)
  end
end

def apply_patches(str, patches)
  str = str.dup
  patches = patches.sort_by { |pt| pt[0] }
  patches.reverse_each do |index, offset, replacement|
    str[index, offset] = replacement
  end
  str
end

def anonymize(input_filename, output_filename)
  # Open input and parse its header.
  input = File.open(input_filename, 'rb') { |f| InputWrapper.new StringIO.new f.read }
  header = aoe2rec_parse_header(input)

  header[:inflated_header_patches] = []
  name_map = {}
  header[:players].each do |pi|
    new_name = "P" + (pi.fetch(:color_id) + 1).to_s
    name_map[pi.fetch(:name)] = new_name

    #puts "%d %-20s profile=%d" % [
    #  pi.fetch(:color_id) + 1, pi.fetch(:name), pi.fetch(:profile_id)
    #]
    set_player_name(header, pi, new_name)
  end
  apply_patches(header[:inflated_header], header.delete(:inflated_header_patches))

  output = StringIO.new
  output.write(aoe2rec_encode_header(header))

  input.flush_recently_read

  while true
    op = aoe2rec_parse_operation(input)
    break if op.nil?

    if op[:operation] == :chat
      chat = JSON.parse(op.fetch(:json), symbolize_names: true)
      change_names_in_chat!(chat, name_map)
      output.write(aoe2rec_encode_chat(chat))
      input.flush_recently_read
    else
      output.write(input.flush_recently_read)
    end
  end

  File.open(output_filename, 'wb') do |f|
    f.write output.string
  end
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

anonymize(input_filename, output_filename)
