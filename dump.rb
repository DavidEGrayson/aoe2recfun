#!/usr/bin/env ruby
# Utility for dumping data from AOE2 recorded games.

require_relative 'aoe2rec'

$stdout.sync = true

def dump_header(header)
  puts "File format version: #{header.fetch(:save_version)}"
  puts "Build: ##{header.fetch(:build)}"
  puts "Date: " + Time.at(header.fetch(:timestamp)).strftime("%Y-%m-%d %H:%M:%S")
  if !header.fetch(:lobby_name).empty?
    puts "Lobby name: " + header.fetch(:lobby_name)
  end

  if header.fetch(:game_mode) != 0
    mode = header[:game_mode]
    puts "Game mode: " + GAME_MODES.fetch(mode, mode.to_s)
  end

  map = aoe2de_map_name(header.fetch(:resolved_map_id))
  if header[:selected_map_id] != header[:resolved_map_id]
    map += ", from " + aoe2de_map_name(header.fetch(:selected_map_id))
  end
  puts "Map: " + map

  puts "Map size: %dx%d" % [header.fetch(:size_x), header.fetch(:size_y)]

  if header.fetch(:starting_resources_id) != 0
    id = header.fetch(:starting_resources_id)
    puts "Resources: " + STARTING_RESOURCES.fetch(id, id.to_s)
  end

  if header.fetch(:population_limit) != 200
    puts "Population: %d" % header.fetch(:population_limit)
  end
  if (header.fetch(:speed) - 1.69).abs > 0.001
    puts "Speed: %0.2f" % header[:speed]
  end
  if header.fetch(:starting_age_id) != 0
    id = header[:starting_age_id]
    puts "Starting age: " + AGES.fetch(id, id.to_s)
  end
  if header.fetch(:ending_age_id) != 0
    id = header[:ending_age_id]
    puts "Ending age: " + AGES.fetch(id, id.to_s)
  end
  if header.fetch(:victory_type_id) != 0
    id = header.fetch(:victory_type_id)
    puts "Victory: " + VICTORY_TYPES.fetch(id, id.to_s)
  end
  if header.fetch(:battle_royale_time) != 30
    puts "Battle Royale Time: #{header.fetch(:battle_royale_time)}"
  end
  if header.fetch(:treaty_length) != 0
    puts "Treaty Length: #{header.fetch(:treaty_length)}"
  end

  # "Team Settings"
  if header.fetch(:lock_teams) != true
    puts "Lock Teams: #{header.fetch(:lock_teams)}"
  end
  if header.fetch(:random_positions)
    puts "Team Together: #{!header.fetch(:random_positions)}"
  end
  if header.fetch(:team_positions)
    puts "Team Positions: #{header.fetch(:team_positions)}"
  end
  if header.fetch(:shared_exploration) != true
    puts "Shared Exploration: #{header.fetch(:shared_exploration)}"
  end
  # TODO: handicap

  # "Advanced Settings"
  if header.fetch(:lock_speed)
    puts "Lock Speed"
  end
  if header[:cheats_enabled]
    puts "Allow cheats"
  end
  if header[:full_tech_tree]
    puts "Full tech tree"
  end
  if header[:turbo_enabled]
    puts "Turbo mode"
  end
  if header[:regicide_mode]
    puts "Regicide mode (checkbox)"
  end
  if header[:sudden_death_mode]
    puts "Sudden Death mode (checkbox)"
  end
  if header[:empire_wars_mode]
    puts "Empire Wars mode (checkbox)"
  end
  if header[:antiquity_mode]
    puts "Antiquity Mode"
  end

  puts "Players:"
  header[:players].each do |pi|
    puts "  %d %-30s ID %d, FID %d, T %d, PR %d" % [
      pi.fetch(:color_id) + 1, (pi.fetch(:name) + pi.fetch(:ai_name)).strip,
      pi.fetch(:player_id), pi.fetch(:force_id), pi.fetch(:type), pi.fetch(:profile_id),
    ]
  end
  puts "Recorded by FID #{header.fetch(:rec_force_id)}"

  if false
    # Dump more potentially useful stuff from the header
    header = header.dup
    info_printed = %i{inflated_header players empty_slots resolved_map_id selected_map_id
      build lobby_name save_version timestamp ai_strings ai_scripts map_zones tile_data tiles game_mode
      regicide_mode empire_wars_mode sudden_death_mode antiquity_mode full_tech_tree
      starting_age_id ending_age_id size_x size_y population_limit lock_speed
      turbo_enabled starting_resources_id lock_teams team_positions random_positions
      battle_royale_time cheats_enabled shared_exploration treaty_length visibility_data}
    info_printed.each do |sym|
      header.delete(sym)
    end
    puts "Maybe interesting header data: " + header.inspect
  end
end

def dump_file(filename)
  time = 0
  contents = File.open(filename, 'rb') { |f| f.read }
  io = StringIO.new(contents)
  puts "#{filename}:"
  puts "Size: #{contents.size}"
  header = aoe2rec_parse_header(io)
  dump_header header
  while true
    op = aoe2rec_parse_operation(io)
    break if !op
    if op.fetch(:operation) == :sync
      time += op.fetch(:time_increment)
    end
    if op.fetch(:operation) == :seek
      puts "%s: seek to %d" % [aoe2_pretty_time(time), op.fetch(:offset)]
    end
    if op.fetch(:operation) == :chat
      chat = JSON.parse(op.fetch(:json), symbolize_names: true)
      chat[:time] = time
      puts aoe2_pretty_chat(chat, header.fetch(:players))
    end
    if op.fetch(:operation) == :postgame
      game_finish_time = time
      puts "#{aoe2_pretty_time(time)}: [game finished]"
      if op.key?(:world_time)
        world_time = op.fetch(:world_time)
        if world_time != time
          puts "World time mismatch: " \
            "expected #{aoe2_pretty_time(time)} (#{time}), " \
            "got #{aoe2_pretty_time(world_time)} (#{world_time})"
        end
      end
      if op.key?(:leaderboards)
        op[:leaderboards].each do |board|
          id = board.fetch(:id)
          name = LEADERBOARD_NAMES.fetch(id, "Leaderboard #{id}")
          players = board.fetch(:players)
          next if players.empty?
          puts "#{name}"
          players.each do |player|
            puts "  %d #%-6d %5d" % [
              player.fetch(:id), player.fetch(:rank), player.fetch(:rating)
            ]
          end
        end
      end
    end
  end
  if time != game_finish_time
    puts "#{aoe2_pretty_time(time)}: [replay finished]"
  end
  puts
  puts
  $total_time += time
end

$total_time = 0
filenames = ARGV

if filenames.size == 0
  puts "Usage: ./dump.rb file1.aoe2record file2.aoe2record ..."
  exit 1
end

filenames.each do |filename|
  begin
    dump_file(filename)
  rescue StandardError => e
    puts "Error while dumping #{filename}:"
    puts "#{e}"
    puts e.backtrace
    puts
    puts
    exit 1
  end
end

if filenames.size > 1
  puts "Total time for all #{filenames.size} replays: #{aoe2_pretty_time($total_time)}"
end
