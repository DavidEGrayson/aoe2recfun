# Very basic library for parsing an AOE2DE recorded game.

# Reference for the AOE2 replay file format:
# https://github.com/happyleavesaoc/aoc-mgz

require 'stringio'
require 'zlib'
require 'digest/sha2'
require 'json'

class String
  # for debugging
  def hex_inspect
    '"' + each_byte.map { |b| '\x%02x' % b }.join + '"'
  end
end

def to_bool(num)
  return false if num == 0
  return true if num == 1
  raise "Expected boolean, got #{num.inspect}."
end

# for debugging
def dump_remainder(io)
  $remainder_id ||= 0
  remainder_offset = io.tell
  filename = "remainder%d.bin" % $remainder_id
  puts "Dumping from offset %x to #{filename} for inspection\n" % remainder_offset
  File.open(filename, 'wb') { |f| f.write(io.read) }
  io.seek(remainder_offset)
  $remainder_id += 1
end

AGES = {
  0 => 'Standard',
  2 => 'Dark Age',
  3 => 'Feudal Age',
  4 => 'Castle Age',
  5 => 'Imperial Age',
  6 => 'Post-Imperial Age',
}

VICTORY_TYPES = {
  0 => 'Standard',
  9 => 'Conquest',
  11 => 'Last Man Standing',
}

GAME_MODES = {
  0 => 'Random Map',
  1 => 'Regicide',
  2 => 'Death Match',
  3 => 'Custom Scenario',
  6 => 'King of the Hill',
  8 => 'Defend the Wonder',
  10 => 'Capture the Relic',
  11 => 'Sudden Death',
  12 => 'Battle Royale',
  13 => 'Empire Wars',
}

LEADERBOARD_NAMES = {
  3 => '1v1 RM',
  4 => 'Team RM',
}

STARTING_RESOURCES = {
  0 => 'Standard',
  1 => 'Low',
  2 => 'Medium',
  3 => 'High',
  4 => 'Ultra High',
  5 => 'Infinite',
  6 => 'Random',
}

AOE2DE_MAP_NAMES = {
  9 => 'Arabia',
  10 => 'Archipelago',
  11 => 'Baltic',
  12 => 'Black Forest',
  13 => 'Coastal',
  14 => 'Continental',
  15 => 'Crater Lake',
  16 => 'Fortress',
  17 => 'Gold Rush',
  18 => 'Highland',
  19 => 'Islands',
  20 => 'Mediterranean',
  21 => 'Migration',
  22 => 'Rivers',
  23 => 'Team Islands',
  24 => 'Full Random',
  25 => 'Scandinavia',
  26 => 'Mongolia',
  27 => 'Yucatan',
  28 => 'Salt Marsh',
  29 => 'Arena',
  30 => 'King of the Hill',
  31 => 'Oasis',
  32 => 'Ghost Lake',
  33 => 'Nomad',
  49 => 'Iberia',
  50 => 'Britain',
  51 => 'Mideast',
  52 => 'Texas',
  53 => 'Italy',
  54 => 'Central America',
  55 => 'France',
  56 => 'Norse Lands',
  57 => 'Sea of Japan (East Sea)',
  58 => 'Byzantium',
  59 => 'Custom',
  60 => 'Random Land Map',
  61 => 'Random Real World Map',
  63 => 'Blind Random',
  65 => 'Random Special Map',
  66 => 'Random Special Map',
  67 => 'Acropolis',
  68 => 'Budapest',
  69 => 'Cenotes',
  70 => 'City of Lakes',
  71 => 'Golden Pit',
  72 => 'Hideout',
  73 => 'Hill Fort',
  74 => 'Lombardia',
  75 => 'Steppe',
  76 => 'Valley',
  77 => 'MegaRandom',
  78 => 'Hamburger',
  79 => 'CtR Random',
  80 => 'CtR Monsoon',
  81 => 'CtR Pyramid Descent',
  82 => 'CtR Spiral',
  83 => 'Kilimanjaro',
  84 => 'Mountain Pass',
  85 => 'Nile Delta',
  86 => 'Serengeti',
  87 => 'Socotra',
  88 => 'Amazon',
  89 => 'China',
  90 => 'Horn of Africa',
  91 => 'India',
  92 => 'Madagascar',
  93 => 'West Africa',
  94 => 'Bohemia',
  95 => 'Earth',
  96 => 'Canyons',
  97 => 'Enemy Archipelago',
  98 => 'Enemy Islands',
  99 => 'Far Out',
  100 => 'Front Line',
  101 => 'Inner Circle',
  102 => 'Motherland',
  103 => 'Open Plains',
  104 => 'Ring of Water',
  105 => 'Snakepit',
  106 => 'The Eye',
  107 => 'Australia',
  108 => 'Indochina',
  109 => 'Indonesia',
  110 => 'Strait of Malacca',
  111 => 'Philippines',
  112 => 'Bog Islands',
  113 => 'Mangrove Jungle',
  114 => 'Pacific Islands',
  115 => 'Sandbank',
  116 => 'Water Nomad',
  117 => 'Jungle Islands',
  118 => 'Holy Line',
  119 => 'Border Stones',
  120 => 'Yin Yang',
  121 => 'Jungle Lanes',
  122 => 'Alpine Lakes',
  123 => 'Bogland',
  124 => 'Mountain Ridge',
  125 => 'Ravines',
  126 => 'Wolf Hill',
  132 => 'Antarctica',
  137 => 'Custom Map Pool',
  139 => 'Golden Swamp',
  140 => 'Four Lakes',
  141 => 'Land Nomad',
  142 => 'Battle on Ice',
  143 => 'El Dorado',
  144 => 'Fall of Axum',
  145 => 'Fall of Rome',
  146 => 'Majapahit Empire',
  147 => 'Amazon Tunnel',
  148 => 'Coastal Forest',
  149 => 'African Clearing',
  150 => 'Atacama',
  151 => 'Seize the Mountain',
  152 => 'Crater',
  153 => 'Crossroads',
  154 => 'Michi',
  155 => 'Team Moats',
  156 => 'Volcanic Island',
  158 => 'Eruption',
  159 => 'Frigid Lake',
  164 => 'Mountain Range',
  169 => 'Enclosed',
  170 => 'Haboob',
  172 => 'Land Madness',
  174 => 'Wade',
  175 => 'Morass',
  177 => 'Cliffbound',
  179 => 'Dunesprings',
  180 => 'Golden Stream',
  181 => 'Mountain Dunes',
  182 => 'River Divide',
  183 => 'Sandrift',
  184 => 'Shrubland',
  185 => 'The Passage',
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
  prefix = io.read(2)
  expected_prefix = "`\n".b
  if prefix != expected_prefix
    offset = io.tell - 1
    raise "Expected DE string at 0x%x, but got %s instead of %s." % \
      [offset, prefix.hex_inspect, expected_prefix.inspect]
  end
  length = io.read(2).unpack1('S')
  io.read(length)
end

def aoe2rec_parse_string_block(io)
  strings = []
  while true
    crc = io.read(4).unpack1('L')
    if crc > 0 && crc <= 255
      strings << [crc]
      break
    end
    strings << [crc, aoe2rec_parse_de_string(io)]
  end
  strings
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

  if save_version >= 61.5
    custom_civ_count = io.read(4).unpack1('L')
    custom_civ_ids = (0...custom_civ_count).map do
      io.read(4).unpack1('L')
    end
  end

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
  r = { unknown_de: [] }

  if save_version >= 25.22
    r[:build] = io.read(4).unpack1('L')
  end
  if save_version >= 26.16
    r[:timestamp] = io.read(4).unpack1('L')
  end

  r[:version], r[:interval_version], game_options_version, dlc_count =
    io.read(16).unpack('FLLL')

  raise if game_options_version != 1

  r[:dlc_ids] = io.read(dlc_count * 4).unpack('L*')

  meat = io.read(18*4).unpack('LLLLLLLLLLLLFLLLLL')
  r[:dataset_ref], r[:difficulty_id],
    r[:selected_map_id], r[:resolved_map_id],
    r[:reveal_map], r[:victory_type_id],
    r[:starting_resources_id], r[:starting_age_id],
    r[:ending_age_id], r[:game_mode],
    separator1, separator2,
    r[:speed], r[:treaty_length],
    r[:population_limit], r[:player_count],
    r[:unused_player_color], r[:victory_amount] = meat
  raise if separator1 != 155555
  raise if separator2 != 155555

  # reveal_map seems to be 6 for normal games a 1 for explored OR all visible

  r[:unknown_de] << io.read(1) if save_version >= 61.3

  separator3 = io.read(4).unpack1('L')
  raise if separator3 != 155555

  meat = io.read(15).unpack('C' * 15)
  r[:trade_enabled] = to_bool(meat[0])
  r[:team_bonus_disabled] = to_bool(meat[1])
  r[:random_positions] = to_bool(meat[2])
  r[:full_tech_tree] = to_bool(meat[3])
  r[:num_starting_units] = to_bool(meat[4])
  r[:lock_teams] = to_bool(meat[5])
  r[:lock_speed] = to_bool(meat[6])
  r[:multiplayer] = to_bool(meat[7])
  r[:cheats_enabled] = to_bool(meat[8])
  r[:record_game] = to_bool(meat[9])
  r[:animals_enabled] = to_bool(meat[10])
  r[:predators_enabled] = to_bool(meat[11])
  r[:turbo_enabled] = to_bool(meat[12])
  r[:shared_exploration] = to_bool(meat[13])
  r[:team_positions] = to_bool(meat[14])

  if save_version >= 13.34
    sub_game_mode = io.read(4).unpack1('L')
    if (sub_game_mode >> 3) != 0
      raise "Unexpected bit set in sub_game_mode: 0x%x.%" % sub_game_mode
    end
    r[:empire_wars_mode] = to_bool(sub_game_mode[0])   # checkbox
    r[:sudden_death_mode] = to_bool(sub_game_mode[1])  # checkbox
    r[:regicide_mode] = to_bool(sub_game_mode[2])      # checkbox
    r[:battle_royale_time] = io.read(4).unpack1('L')
  end

  if save_version >= 25.06
    r[:handicap_enabled] = io.read(1).ord
  end

  r[:unknown_de] << io.read(1) if save_version >= 50

  separator4 = io.read(4).unpack1('L')

  raise if separator4 != 155555

  player_array_count = save_version >= 37 ? r[:player_count] : 8
  raise if player_array_count > 8

  r[:players] = (1..player_array_count).collect do |id|
    aoe2rec_parse_player(io, id, save_version)
  end
  r[:players].reject! { |pl| pl[:force_id] == 0xFFFFFFFF }

  r[:unknown_de] << io.read(9)
  r[:reveal_map] = io.read(1).unpack1('C')
  r[:cheat_notifications] = to_bool(io.read(1).unpack1('C'))
  r[:colored_chat] = to_bool(io.read(1).unpack1('C'))

  if save_version >= 37
    empty_slot_count = 8 - r[:player_count]
    r[:empty_slots] = (0...empty_slot_count).map do
      slot = { unknown: [] }
      if save_version >= 61.5
        slot[:unknown] << io.read(4).unpack1('L')
      end
      slot[:unknown] << io.read(4).unpack1('L')
      slot[:unknown] << io.read(4).unpack1('L')
      slot[:unknown] << io.read(4).unpack1('L')
      slot[:unknown] << aoe2rec_parse_de_string(io)
      slot[:unknown] << io.read(1)
      slot[:unknown] << aoe2rec_parse_de_string(io)
      slot[:unknown] << aoe2rec_parse_de_string(io)
      slot[:unknown] << io.read(22)
      slot[:unknown] << io.read(4).unpack1('L')
      slot[:unknown] << io.read(4).unpack1('L')
      slot[:unknown] << io.read(8)
      slot
    end
  end

  separator5 = io.read(4).unpack1('L')
  raise if separator5 != 155555

  r[:ranked] = to_bool(io.read(1).unpack1('C'))
  r[:allow_specs] = to_bool(io.read(1).unpack1('C'))
  r[:lobby_visibility] = to_bool(io.read(4).unpack1('L'))
  r[:hidden_civs] = to_bool(io.read(1).unpack1('C'))
  r[:matchmaking] = to_bool(io.read(1).unpack1('C'))
  if save_version >= 13.13
    r[:spec_delay] = io.read(4).unpack1('L')
    r[:scenario_civ] = io.read(1).unpack1('C')
  end
  r[:rms_strings] = aoe2rec_parse_string_block(io)
  r[:unknown_de] << io.read(8)
  r[:other_strings] = 20.times.collect do
    aoe2rec_parse_string_block(io)
  end

  strategic_number_count = io.read(4).unpack1('L')
  if save_version >= 25.22
    strategic_number_read_size = strategic_number_count
  else
    strategic_number_read_size = 59
  end
  r[:strategic_numbers] = strategic_number_read_size.times.collect do
    io.read(4).unpack1('L')
  end[0, strategic_number_count]

  ai_files_count = io.read(8).unpack1('Q')
  r[:ai_files] = ai_files_count.times.collect do
    aif = [
      io.read(4),
      aoe2rec_parse_de_string(io),
      io.read(4),
    ]
    aif
  end

  if save_version >= 25.02
    r[:unknown_de] << io.read(8)
  end
  r[:guid] = io.read(16)
  r[:lobby_name] = aoe2rec_parse_de_string(io)

  if save_version >= 25.22
    r[:unknown_de] << io.read(8)
  end
  r[:modded_dataset] = aoe2rec_parse_de_string(io)
  r[:unknown_de] << io.read(5) if save_version >= 13.13
  r[:unknown_de] << io.read(19)
  if save_version >= 13.17
      r[:unknown_de] << io.read(3)
      r[:unknown_de] << aoe2rec_parse_de_string(io)
      r[:unknown_de] << io.read(2)
  end
  r[:unknown_de] << io.read(1) if save_version >= 20.06
  r[:unknown_de] << io.read(8) if save_version >= 20.16
  r[:unknown_de] << io.read(21) if save_version >= 25.06
  r[:unknown_de] << io.read(4) if save_version >= 25.22
  r[:unknown_de] << io.read(8) if save_version >= 26.16
  r[:unknown_de] << io.read(3) if save_version >= 37
  r[:unknown_de] << io.read(8) if save_version >= 50
  r[:unknown_de] << io.read(1) if save_version >= 61.5
  if save_version >= 63
    r[:unknown_de] << io.read(4)
    r[:antiquity_mode] = to_bool(io.read(1).ord)
  end
  r[:unknown_de] << aoe2rec_parse_de_string(io)
  r[:unknown_de] << io.read(5)
  r[:unknown_de] << io.read(1) if save_version >= 13.13
  if save_version >= 13.17
    r[:unknown_de] << io.read(2)
  else
    r[:unknown_de] << aoe2rec_parse_de_string(io)
    r[:unknown_de] << io.read(4)
    r[:unknown_de] << io.read(4)
  end
  if save_version >= 13.17
    r[:unknown_de] << io.read(4)
    r[:unknown_de] << io.read(4)
  end

  r
end

# aoc-mgz doesn't have a description of this stuff so I'm figuring it out
# myself.
def aoe2rec_parse_de_ai(io, save_version)
  r = { unknown_ai: [] }
  has_ai = io.read(4).unpack1('L')
  raise "has_ai = #{has_ai}" if has_ai > 1
  return r if has_ai == 0

  r[:unknown_ai] << io.read(2).unpack1('S')
  num_strings = io.read(2).unpack1('S')
  r[:unknown_ai] << io.read(4).unpack1('L')

  r[:ai_strings] = num_strings.times.collect do
    io.read(io.read(4).unpack1('L'))
  end

  r[:unknown_ai] << io.read(2).unpack1('S')
  r[:unknown_ai] << io.read(2).unpack1('S')
  r[:unknown_ai] << io.read(1).unpack1('C')
  ai_count = io.read(1).unpack1('C')
  r[:unknown_ai] << io.read(1).unpack1('C')

  raise "Unexpected ai_count (#{ai_count})" if ai_count != 8

  r[:ai_scripts] = []
  ai_count.times do |i|
    ai_header = io.read(16)
    ai_header_parts = ai_header.unpack('llssl')
    is_ai = ai_header_parts[0]

    if is_ai == 0
      if ai_header_parts != [0, -1, 0, 0, 0]
        raise "Unexpected pattern for empty AI slot: #{ai_header.hex_inspect}"
      end
      next
    end

    ai = { unknown: [ai_header_parts[2], ai_header_parts[4] ] }
    ai[:id] = ai_header_parts[1]
    if ai[:id] != i
      raise "Unexpected AI ID: #{r[:id]} != #{i}"
    end

    six_pack_clump_count = ai_header_parts[3]
    last_seq = -1
    ai[:six_pack_clumps] = six_pack_clump_count.times.collect do
      offset = io.tell
      six_pack_header = io.read(24)
      clump_parts = six_pack_header.unpack('llssCCsLL')
      if clump_parts[0] != 1 || clump_parts[1] != 1 || clump_parts[3] != -1
        raise "Six-pack clump pattern ended at 0x%x: %s" % [offset, six_pack_header.hex_inspect]
      end
      seq = clump_parts[2]
      if seq != last_seq + 1
        raise "Six-pack clump sequence pattern ended."
      end
      last_seq = seq
      clump = { unknown: [] }
      clump[:unknown] += [clump_parts[4], clump_parts[6], clump_parts[7], clump_parts[8]]
      six_pack_count = clump_parts[5]
      clump[:six_packs] = six_pack_count.times.collect do
        six_pack = io.read(6*4).unpack('LLLLLL')
        if ![1, 2, 3].include?(six_pack[0])
          raise "Unexpected six-pack at 0x%x: %s" % [io.tell, six_pack.inspect]
        end
        six_pack
      end
      clump
    end
    r[:ai_scripts] << ai
  end

  r[:unknown_ai] << io.read(4).unpack1('L')  # 0 or 100, thought it was a count
  r[:unknown_ai] << io.read(100)
  r[:unknown_ai] << io.read(4)

  expected_ff_byte_count = 2624
  ff = io.read(expected_ff_byte_count)
  if ff != "\xFF".b * expected_ff_byte_count
    raise "0xFF bytes are not as expected: #{ff.inspect} (#{ff.size})"
  end

  expected_zero_byte_count = 4096
  zero_bytes = io.read(expected_zero_byte_count)
  if zero_bytes != "\x00".b * expected_zero_byte_count
    raise "0x00 bytes are not as expected"
  end

  return r
end

# Parse a section of basic info from the header which comes after the AI
# info and is called "replay" by aoc-mgz
def aoe2rec_parse_replay(io, save_version)
  r = { unknown_replay: [] }

  parts = io.read(7*4 + 1 + 2*4 + 8 + 2 + 1 + 1 + 1 + 2 + 3*4 + 4 + 1 + 1 + 4).unpack(
    'LLLLLFFCllLLSCCCSLLLLCCL')

  old_time = parts[0]
  world_time = parts[1]
  old_world_time = parts[2]
  old_game_speed_id = parts[3]
  world_time_delta_seconds = parts[4]
  timer = parts[5]
  r[:game_speed_float] = parts[6]
  temp_pause = parts[7]
  r[:next_object_id] = parts[8]
  r[:next_reusable_object_id] = parts[9]
  r[:random_seed] = parts[10]
  r[:random_seed_2] = parts[11]  # usually the same as random_seed, not always
  r[:rec_player] = parts[12]
  r[:player_count_including_gaia] = parts[13]
  old_instant_build = parts[14]
  old_cheats_enabled = parts[15]
  r[:unknown_replay] << parts[16]  # dunno what this is; usually 0, sometimes 1
  r[:campaign] = parts[17]
  r[:campaign_player] = parts[18]
  r[:campain_scenario] = parts[19]
  r[:king_campaign] = parts[20]
  r[:king_campaign_player] = parts[21]
  r[:king_campaign_scenario] = parts[22]
  r[:player_turn] = parts[23]

  raise if old_time != 0
  raise if world_time != 0
  raise if old_world_time != 0
  raise if old_game_speed_id != 0
  raise if world_time_delta_seconds != 0
  raise if timer != 0
  raise if temp_pause != 0
  raise if old_instant_build != 0
  raise if old_cheats_enabled != 0

  count = save_version >= 61.5 ? r[:player_count_including_gaia] : 9
  r[:player_time_delta] = io.read(count * 4).unpack('L*')

  padding = io.read(8)
  raise if padding != "\xad\xde\xad\xde\x03\0\0\0".b

  r
end

def aoe2rec_parse_map(io, save_version)
  r = {}

  r[:size_x], r[:size_y], zone_count = io.read(12).unpack('LLL')

  if r[:size_x] == 0 || r[:size_x] != r[:size_y]
    raise "Unexpected map sizes: #{r[:size_x]} #{r[:size_y]}"
  end

  tile_count = r[:size_x] * r[:size_y]

  r[:map_zones] = zone_count.times.collect do
    zone = {}
    zone[:data] = io.read(2048 + tile_count * 2)
    float_count = io.read(4).unpack1('L')
    zone[:floats] = io.read(float_count * 4).unpack('F*')
    zone[:unknown] = io.read(4).unpack1('L')
    zone
  end

  old_all_visible, r[:fog_of_war] = io.read(2).unpack('CC')

  raise if old_all_visible != 0

  # TODO: this has got to be slow... parse the tiles if the user requests it
  r[:tiles] = tile_count.times.collect do |i|
    tile = { unknown: [] }
    tile[:terrain_type] = terrain_type = io.read(1).ord

    # Next byte is almost always -1, but I saw several instances of 45 on a
    # Cliffbound Regicide game.
    tile[:unknown] << io.read(1).unpack1('c')

    if save_version >= 62.0
      # Next byte is almost always equal to terrain_type.  Maybe for blending
      # two types of terrain.
      terrain_type2 = io.read(1).ord
      tile[:terrain_type2] = terrain_type2
    end

    tile[:elevation] = io.read(1).ord
    parts = io.read(4).unpack('ss')
    padding2 = parts[0]
    tile[:unknown] << parts[1]
    raise if padding2 != -1

    # TODO: also if "check.val" > 1000 we're supposed to run this part of the code,
    # according to aoc-mgz, but maybe we don't care about supporting DE recs
    # that are older than 13.03 properly.
    if save_version >= 13.03
      unknown2 = io.read(2).unpack1('s')
      tile[:unknown2] = unknown2 if unknown2 != tile[:unknown]
    end

    tile
  end

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
  if game_version != "VER 9.4"
    raise "Expected game_version to be 'VER 9.4', got #{game_version}."
  end

  save_version = io.read(4).unpack1('F').round(2)
  if save_version == -1.0
    save_version = io.read(4).unpack1('V')
    if save_version != 37
      save_version = (save_version.to_f / (1 << 16)).round(2)
    end
  end
  r[:save_version] = save_version

  if r[:save_version] < 12.97
    $stderr.puts "Warning: expected save_version to be at least 12.97, got #{r[:save_version]}."
  end

  r.merge! aoe2rec_parse_de_header(io, save_version)
  r.merge! aoe2rec_parse_de_ai(io, save_version)
  r.merge! aoe2rec_parse_replay(io, save_version)
  r.merge! aoe2rec_parse_map(io, save_version)

  # dump_remainder(io)
  # NOTE: There is other stuff in the header that we have not parsed.

  r
end

def aoe2rec_parse_header(io)
  header_length = io.read(4).unpack1('V')
  if header_length > 2_000_000
    raise "header_length: #{header_length}"
  end
  header = io.read(header_length - 4)

  r = aoe2rec_parse_compressed_header(header)

  parts = io.read(32).unpack('VVVVVVVV')
  log_version = parts[0]
  r[:rec_force_id] = parts[4]
  other_version = parts[7]
  r[:unknown] = [ parts[1], parts[2], parts[3], parts[5], parts[6] ]

  if log_version != 5
    raise "Expected log_version to be 5, got #{r[:log_version]}."
  end
  if other_version != 0
    raise "Expected other_version to be 0, got #{r[:other_version]}."
  end

  # Remove redundant header info

  if r[:player_count_including_gaia] != r[:player_count] + 1
    raise "Player count mismatch: #{r[:player_count]} != #{r[:player_count] + 1}."
  end
  r.delete(:player_count_including_gaia)

  if r[:rec_player] != r[:rec_force_id]
    raise "rec_player mismatch: #{r[:rec_player]} != #{r[:rec_force_id]}."
  end
  r.delete(:rec_player)

  if r[:game_speed_float] != r[:speed]
    raise "game_speed_float mismatch: #{r[:game_speed_float]} != #{r[:speed]}"
  end
  r.delete(:game_speed_float)

  r
end

def aoe2rec_encode_header(header)
  deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -15)
  # just set next_chapter to 0 since we don't know the right address yet
  compressed_header = "\x00\x00\x00\x00".b
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

# This is an insane data structure where you have to read it backwards.
# The end of it appears to be marked by an 8-byte constant.
def aoe2rec_parse_postgame(io)
  if false
    data = io.read
    if data.size < 1000
      puts ("Length 0x%x: " % data.size) + data.hex_inspect
    end
    return { operation: :postgame, data: data }
  end

  ending = "\xce\xa4\x59\xb1\x05\xdb\x7b\x43".b
  bytes = io.read(8)
  while bytes[-8,8] != ending
    chunk = io.read(1)
    if chunk.nil?
      raise "Reached EOF looking for postgame block ending: " \
        "last_8_bytes=#{bytes[-8,8].hex_inspect}, expected_ending=#{ending.hex_inspect}"
    end
    bytes += chunk
  end

  version = bytes[-12, 4].unpack1('L')
  raise "Unexpected postgame version: #{version}" if version != 1

  block_count = bytes[-16, 4].unpack1('L')
  raise "Postgame block_count unexpectedly large" if block_count > 8

  r = { operation: :postgame }

  offset = bytes.size - 16
  block_count.times do
    offset -= 8
    raise if offset < 0
    block_size, block_id = bytes[offset, 8].unpack('LL')
    offset -= block_size
    raise if offset < 0
    block = bytes[offset, block_size]

    if block_id == 1  # world time
      raise if block_size != 4
      r[:world_time] = block.unpack1('L')
    elsif block_id == 2  # leaderboards
      bio = StringIO.new(block)
      leaderboard_count = bio.read(4).unpack1('L')
      r[:leaderboards] = leaderboard_count.times.collect do
        lb = {}
        lb[:id], lb[:unknown] = bio.read(4+2).unpack('LS')
        lb_player_count = bio.read(4).unpack1('L')
        lb[:players] = lb_player_count.times.collect do
          player = {}
          id_minus_1, player[:rank], player[:rating] = \
            bio.read(3*4).unpack('lll')
          player[:id] = id_minus_1 + 1
          player
        end
        lb
      end
    else
      # Block we don't understand yet
      r[block_id] = block
    end
  end

  if offset != 0
    raise "Unaccounted-for data in postgame block (#{offset} bytes)."
  end

  r
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
  when 6 then aoe2rec_parse_postgame(io)
  else
    if operation_id > io.tell
      # I think when someone drops, the game inserts a new header in this
      # gap.  Possibly also when someone saves a chapter.
      io.seek(operation_id)
      { operation: :seek, offset: operation_id }
    else
      raise "Unknown operation 0x%x at offset %d." % [operation_id, io.tell]
    end
  end
end

def aoe2rec_encode_chat(chat)
  json = JSON.dump(
    player: chat.fetch(:player),
    channel: chat.fetch(:channel),
    message: chat.fetch(:message),
    messageAGP: chat.fetch(:messageAGP),
  ).b
  [4, -1, json.size].pack('LlL') + json
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
