# Very basic library for parsing an AOE2DE recorded game.
# References:
# https://github.com/happyleavesaoc/aoc-mgz/blob/master/mgz/body/__init__.py
# https://github.com/happyleavesaoc/aoc-mgz/blob/master/mgz/enums.py

def aoe2rec_parse_header(io)
  header_length = io.read(4).unpack1('V')
  header = io.read(header_length - 4)
end

def aoe2rec_parse_meta(io)
  parts = io.read(32).unpack('VVVVVVVV')
  meta = {
    log_version: parts[0],
    player_id: parts[4], # TODO: is this name accurate?
    other_version: parts[7],
  }
  if meta[:log_version] != 5
    raise NotSupportedError, "log_version is not 5."
  end
  if meta[:other_version] != 0
    raise NotSupportedError, "other_version is not 0."
  end
  meta
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

def aoe2rec_parse(io)
  aoe2rec_parse_header(io)
  yield aoe2rec_parse_meta(io)
  while (op = aoe2rec_parse_operation(io))
    yield op
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
