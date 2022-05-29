# Very basic library for parsing an AOE2DE recorded game.

# Reference for the AOE2 replay file format:
# https://github.com/happyleavesaoc/aoc-mgz

require 'stringio'
require 'zlib'
require 'digest/sha2'

AOE2DE_MAP_NAMES = {
  9 => 'Arabia',
  29 => 'Arena',
  68 => 'Budapest',
  78 => 'Hamburger',
  87 => 'Socotra',
  # TODO: complete this list
}

def aoe2de_map_name(id)
  AOE2DE_MAP_NAMES.fetch(id, id.to_s)
end

AOE2_VT100_COLORS = [
  "\e[0m",  # 0 = normal
  "\e[94m", # 1 = blue
  "\e[91m", # 2 = red
  "\e[92m", # 3 = green
  "\e[93m", # 4 = yellow
  "\e[96m", # 5 = cyan
  "\e[95m", # 6 = magenta
  "\e[37m", # 7 = gray
  "\e[33m", # 8 = orange (well, dark yellow)
]

def aoe2_pretty_time(time_ms)
  s = time_ms / 1000
  m, s = s.divmod(60)
  h, m = m.divmod(60)
  "%d:%02d:%02d" % [ h, m, s ]
end

def aoe2_pretty_chat(chat, players)
  msg = chat.fetch(:messageAGP)
  if msg.empty?
    text = "[hidden] id%d: %s" % [chat.fetch(:player), chat.fetch(:message).force_encoding('UTF-8')]
  else
    text = msg.sub(/\A@#(\d)/) do
      player_id = $1.to_i
      player_info = players[player_id - 1]
      if player_info
        color = player_info.fetch(:color_id) + 1
        color = 0 if color > AOE2_VT100_COLORS.size
        AOE2_VT100_COLORS.fetch(color)
      else
        "[id#{player_id}] "
      end
    end + AOE2_VT100_COLORS[0]
  end
  "%7s: %s" % [aoe2_pretty_time(chat.fetch(:time)), text]
end

def aoe2rec_parse_de_string(io)
  raise if io.read(2) != "`\n"
  length = io.read(2).unpack1('S')
  io.read(length)
end

# In the returned hash:
# player_id is the 1-based index of this player in the array.
# force_id tells us which set of units the player controls.
#   For non-coop games, force_id seems to equal player_id.
#   For co-op games, you can have two players controlling the same force.
def aoe2rec_parse_player(io, player_id, save_version)
  r = { offset: io.tell, player_id: player_id }

  r[:dlc_id], r[:color_id],
    r[:selected_color], r[:selected_team_id],
    r[:resolved_team_id], r[:dat_crc],
    r[:mp_game_version], r[:civ_id] =
    io.read(2*4 + 3 + 8 + 5).unpack('LlCCCa8CL')

  r[:ai_type] = aoe2rec_parse_de_string(io)
  r[:ai_civ_name_index] = io.read(1).unpack1('C')

  r[:ai_name_offset] = io.tell
  r[:ai_name] = aoe2rec_parse_de_string(io)

  r[:name_offset] = io.tell
  r[:name] = aoe2rec_parse_de_string(io).force_encoding('UTF-8')

  r[:type_offset] = io.tell
  r[:type] = io.read(4).unpack1('L')

  r[:profile_id_offset] = io.tell
  r[:profile_id] = io.read(4).unpack1('L')
  r[:unknown8] = io.read(4).unpack1('L')
  r[:force_id] = io.read(4).unpack1('L')

  if save_version < 25.22
    r[:hd_rm_elo] = io.read(4).unpack1('L')
    r[:hd_dm_elo] = io.read(4).unpack1('L')
  end

  r[:prefer_random] = io.read(1).unpack1('C')
  r[:custom_ai] = io.read(1).unpack1('C')

  if save_version >= 25.06
    r[:handicap] = io.read(8)
  end

  r
end

def aoe2rec_parse_de_header(io, save_version)
  r = {}

  if save_version >= 25.22
    r[:build] = io.read(4).unpack('L')
  end
  if save_version >= 26.16
    r[:timestamp] = io.read(4).unpack('L')
  end

  r[:version], r[:interval_version], r[:game_options_version], dlc_count =
    io.read(16).unpack('FLLL')

  r[:dlc_ids] = io.read(dlc_count * 4).unpack('L*')

  meat = io.read(19*4).unpack('LLLLLLLLLLLLFLLLLLL')
  r[:dataset_ref], r[:difficulty_id],
    r[:selected_map_id], r[:resolved_map_id],
    r[:reveal_map], r[:victory_type_id],
    r[:starting_resources_id], r[:starting_age_id],
    r[:ending_age_id], r[:game_type],
    separator1, separator2,
    r[:speed], r[:treaty_length],
    r[:population_limit], r[:num_players],
    r[:unused_player_color], r[:victory_amount],
    separator3 = meat
  raise if separator1 != 155555
  raise if separator2 != 155555
  raise if separator3 != 155555

  meat = io.read(15).unpack('C' * 15)
  r[:trade_enabled],
    r[:team_bonus_disabled], r[:random_positions],
    r[:all_techs], r[:num_starting_units],
    r[:lock_teams], r[:lock_speed],
    r[:multiplayer], r[:cheats],
    r[:record_game], r[:animals_enabled],
    r[:predators_enabled], r[:turbo_enabled],
    r[:shared_exploration], r[:team_positions] =
    meat

  if save_version >= 13.34
    r[:sub_game_mode], r[:battle_royale_time] = io.read(8).unpack('LL')
  end

  if save_version >= 25.06
    r[:handicap] = io.read(1)
  end

  separator4 = io.read(4).unpack1('L')

  raise if separator4 != 155555

  r[:players] = (1..8).collect { |id| aoe2rec_parse_player(io, id, save_version) }
  r[:players].reject! { |pl| pl[:force_id] == 0xFFFFFFFF }

  io.read(9)
  r[:fog_of_war] = io.read(1).unpack1('C')
  r[:cheat_notifications] = io.read(1).unpack1('C')
  r[:colored_chat] = io.read(1).unpack1('C')

  separator5 = io.read(4).unpack1('L')
  raise if separator5 != 155555

  r[:ranked] = io.read(1).unpack1('C')
  r[:allow_specs] = io.read(1).unpack1('C')
  r[:lobby_visibility] = io.read(4).unpack1('L')
  r[:hidden_civs] = io.read(1).unpack1('C')
  r[:matchmacking] = io.read(1).unpack1('C')
  r[:spec_delay] = io.read(4).unpack1('L')

  if save_version >= 13.13
    r[:scenario_civ] = io.read(1).unpack1('C')
    r[:rms_crc] = io.read(4).unpack('L')
  end

  r[:unknown_strings] = 23.times.collect do
    string = aoe2rec_parse_de_string(io)
    nums = []
    while true
      n = io.read(4).unpack1('L')
      break if ![3, 21, 23, 42, 44, 45, 46, 47].include?(n)
      nums << n
    end
  end

  r[:unknown7] = io.read(16)  # all zeroes
  r[:guid] = io.read(16)
  r[:lobby_name] = aoe2rec_parse_de_string(io)

  if save_version >= 25.22
    r[:unknown10] = io.read(8)
  end
  r[:modded_dataset] = aoe2rec_parse_de_string(io)
  r[:unknown11] = io.read(19)
  r[:unknown12] = io.read(5) if save_version >= 13.13
  r[:unknown13] = io.read(9) if save_version >= 13.17
  r[:unknown14] = io.read(1) if save_version >= 20.06
  r[:unknown15] = io.read(8) if save_version >= 20.16
  r[:unknown16] = io.read(21) if save_version >= 25.06
  r[:unknown17] = io.read(4) if save_version >= 25.22
  r[:unknown18] = io.read(8) if save_version >= 26.16
  r[:unknown19] = aoe2rec_parse_de_string(io)
  r[:unknown20] = io.read(5)
  r[:unknown21] = io.read(1) if save_version >= 13.13
  if save_version >= 13.17
    r[:unknown22] = io.read(2)
  else
    r[:unknown23] = aoe2rec_parse_de_string(io)
    r[:unknown24] = io.read(4)
    r[:unknown25] = io.read(4)
  end

  # remainder = io.read
  # puts "#{remainder.size} bytes remaining"
  # index = remainder.index('Elavid')
  # if index
  #   puts "Remainder includes Elavid at index #{index}"
  #   exit(1)
  # end

  r
end

def aoe2rec_parse_compressed_header(header)
  r = { }
  io = StringIO.new(header)
  r[:next_chapter] = io.read(4).unpack1('V')
  inflater = Zlib::Inflate.new(-15)
  inflated_header = inflater.inflate(io.read)
  r[:inflated_header] = inflated_header
  io = StringIO.new(inflated_header)

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

  r.merge! aoe2rec_parse_de_header(io, r[:save_version])

  # NOTE: There is other stuff in the header that we have not parsed.

  r
end

def aoe2rec_parse_header(io)
  header_length = io.read(4).unpack1('V')
  if header_length > 1_000_000
    raise "header_length: #{header_length}"
  end
  header = io.read(header_length - 4)

  r = aoe2rec_parse_compressed_header(header)

  parts = io.read(32).unpack('VVVVVVVV')
  r[:log_version] = parts[0]
  r[:unknown1] = parts[1]
  r[:unknown2] = parts[2]
  r[:unknown3] = parts[3]
  r[:force_id] = parts[4]
  r[:unknown5] = parts[5]
  r[:unknown6] = parts[6]
  r[:other_version] = parts[7]

  if r[:log_version] != 5
    raise "Expected log_version to be 5, got #{r[:log_version]}."
  end
  if r[:other_version] != 0
    raise "Expected other_version to be 0, got #{r[:other_version]}."
  end

  r
end

def aoe2rec_encode_header(header)
  deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -15)
  compressed_header = [header.fetch(:next_chapter)].pack('V')
  compressed_header << deflater.deflate(header.fetch(:inflated_header))
  compressed_header << deflater.deflate(nil)
  deflater.close

  parts = [
    header.fetch(:log_version),
    header.fetch(:unknown1),
    header.fetch(:unknown2),
    header.fetch(:unknown3),
    header.fetch(:force_id),
    header.fetch(:unknown5),
    header.fetch(:unknown6),
    header.fetch(:other_version),
  ]

  [compressed_header.bytesize + 4].pack('V') + compressed_header + parts.pack('VVVVVVVV')
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
    force_id: parts[2],
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
    if operation_id > io.tell
      # I think when someone drops, the game inserts a new header in this
      # gap.  Possibly also when someone saves a chapter.
      io.seek(operation_id)
      { operation: :seek, offset: operation_id }
    else
      raise "Unknown operation: 0x%x" % operation_id
    end
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

  def tell
    @io.tell
  end

  def seek(n)
    @io.seek(n)
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

# 'chats' should be an array of hashes that have at least the following keys:
# :time - Game time in milliseconds
# :player - the player ID of the person who sent the chat
# :to - an array with just one element: the ID of the person who received
#       the chat (possibly the same as the player)
# :message - the message that was sent
#
# The array should already be sorted by time.
def merge_chats_core(chats)
  merged_chats = []
  chats.each do |chat|
    player = chat.fetch(:player)
    time = chat.fetch(:time)
    raise ArgumentError if chat.fetch(:to).size != 1
    to = chat.fetch(:to).fetch(0)

    # Look backwards through our merged chats to see if this chat can be
    # merged with one of them.
    same_chat = nil
    merged_chats.reverse_each do |candidate|

      if candidate.fetch(:to).include?(to)
        # We found another chat message from the same recording, so we should
        # stop: or else we would be reordering the messages from that recording.
        break
      end

      if candidate.fetch(:time) < time - 20_000
        # We have gone more than 10 seconds back into the past and found
        # nothing.  Stop now so we don't radically alter the timing of
        # chat messages by accident.
        break
      end

      if candidate.fetch(:player) == player &&
        candidate.fetch(:message) == chat.fetch(:message)
        same_chat = candidate
        break
      end
    end

    if same_chat
      same_chat[:to] << to
    else
      chat = chat.dup
      chat[:to] = chat.fetch(:to).dup
      merged_chats << chat
    end
  end
  merged_chats
end
