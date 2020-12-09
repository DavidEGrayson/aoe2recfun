# Very basic library for parsing an AOE2DE recorded game.
# References:
# https://github.com/happyleavesaoc/aoc-mgz/blob/master/mgz/body/__init__.py
# https://github.com/happyleavesaoc/aoc-mgz/blob/master/mgz/enums.py

require 'stringio'
require 'zlib'

def aoe2rec_parse_de_header(io)
  r = {}
  r[:version], r[:interval_version], r[:game_options_version], dlc_count =
    io.read(16).unpack('FLLL')

  r[:dlc_ids] = io.read(dlc_count * 4).unpack('L*')

  # TODO: finish parsing

  r
end

def aoe2rec_parse_compressed_header(header)
  r = {}
  io = StringIO.new(header)
  r[:check] = io.read(4).unpack1('V')
  inflater = Zlib::Inflate.new(-15)
  io = StringIO.new(inflater.inflate(io.read))
  game_version = ''.b
  while true
    c = io.read(1)
    break if c == "\0"
    game_version << c
  end
  r[:game_version] = game_version
  if r[:game_version] != "VER 9.4"
    raise "Expected game_version to be 'VER 9.4', got #{r[:game_version]}."
  end

  r[:save_version] = io.read(4).unpack1('F').round(2)
  if r[:save_version] < 12.97
    raise "Expected save_version to be at least 12.97, got #{r[:save_version]}."
  end

  r.merge! aoe2rec_parse_de_header(io)

  # NOTE: There is other stuff in the header that we have not parsed.

  r
end

def aoe2rec_parse_header(io)
  r = {}
  header_length = io.read(4).unpack1('V')
  header = io.read(header_length - 4)

  r = aoe2rec_parse_compressed_header(header)

  parts = io.read(32).unpack('VVVVVVVV')
  r[:log_version] = parts[0]
  r[:player_id] = parts[4]
  r[:other_version] = parts[7]

  if r[:log_version] != 5
    raise "Expected log_version to be 5, got #{r[:log_version]}."
  end
  if r[:other_version] != 0
    raise "Expected other_version to be 0, got #{r[:other_version]}."
  end

  r
end

def aoe2rec_parse_action(io)
  action_length = io.read(4).unpack1('L')
  action_data = io.read(action_length + 4)
  { operation: :action, data: action_data }
end

def aoe2rec_parse_chat(io)
  unknown, length = io.read(8).unpack('lL')
  json = io.read(length)
  raise "Expected the unknown chat field to be -1" if unknown != -1
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


# Acts as a normal file object except it intercepts calls to read and stores
# the results in a buffer.  This makes it possible to duplicate a file as we
# are reading it without complicating the parser.
class InputWrapper
  def initialize(io)
    @io = io
    @recently_read = ''.b
  end

  def read(n)
    r = @io.read(n)
    @recently_read << r if r
    r
  end

  def flush_recently_read
    rr = @recently_read
    @recently_read = ''.b
    rr
  end
end
