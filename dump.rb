#!/usr/bin/env ruby

# References:
# https://github.com/happyleavesaoc/aoc-mgz/blob/master/mgz/body/__init__.py#L140
# https://github.com/happyleavesaoc/aoc-mgz/blob/master/mgz/enums.py

def aoe2rec_parse_meta(io)
  parts = io.read(32).unpack('VVVVVVVV')
  meta = {
    log_version: parts[0],
    checksum_interval: parts[1],
    multiplayer: parts[2],
    rec_owner: parts[3],
    reveal_map: parts[4],
    use_sequence_numbers: parts[5],
    number_of_chapters: parts[6],
    aok_or_de: parts[7]  # Note: This field must be misnamed
  }
  if meta[:log_version] != 5
    raise NotSupportedError, "log_version is not 5."
  end
  if meta[:aok_or_de] != 0
    raise NotSupportedError, "aok_or_de is not 0."
  end
  meta
end

def aoe2rec_parse_action(io)
  action_length = io.read(4).unpack1('V')
  action_data = io.read(action_length + 4)
  { operation: :action, data: action_data }
end

def aoe2rec_parse_chat(io)
  unknown, length = io.read(8).unpack('VV')
  json = io.read(length)
  json.chomp!("\0")
  { operation: :chat, json: json }
end

def aoe2rec_parse_sync(io)
  time_increment = io.read(4).unpack1('L')
  { operation: :sync, time_increment: time_increment, }
end

def aoe2rec_parse_checksum(io)
  data = io.read(356)  # tmphax
  { operation: :checksum, data: data }
end

def aoe2rec_parse_viewlock(io)
  parts = io.read(12).unpack('FFL')
  {
    operation: :viewlock,
    x: parts[0],
    y: parts[1],
    player_id: parts[2],
  }
end

def aoe2rec_parse_operation(io)
  r = io.read(4)
  return if r.nil?  # end of file
  operation_id = r.unpack1('L')
  case operation_id
  when 0 then aoe2rec_parse_checksum(io)
  when 1 then aoe2rec_parse_action(io)
  when 2 then aoe2rec_parse_sync(io)
  when 3 then aoe2rec_parse_viewlock(io)
  when 4 then aoe2rec_parse_chat(io)
  else
    raise "Unknown operation: 0x%x" % operation_id
  end
end

def aoe2rec_parse(io)
  header_length = io.read(4).unpack1('V')
  header = io.read(header_length - 4)
  yield aoe2rec_parse_meta(io)
  while (op = aoe2rec_parse_operation(io))
    yield op
  end
end

$stdout.sync = true

filenames = ARGV
filenames.each do |filename|
  File.open(filename, 'rb') do |file|
    puts "#{filename}:"
    aoe2rec_parse(file) do |x|
      if x[:operation] == :chat
        p x
      end
    end
  end
end
