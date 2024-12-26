#!/usr/bin/env ruby
# Utility for dumping data from AOE2 recorded games.

require_relative 'aoe2rec'

$stdout.sync = true

def dump_header(header)
  puts "File format version: #{header.fetch(:save_version)}"
  puts "Build: ##{header.fetch(:build)}"
  puts "Date: " + Time.at(header.fetch(:timestamp)).strftime("%Y-%m-%d %H:%M:%S")
  puts "Lobby name: " + header.fetch(:lobby_name).to_s
  map = aoe2de_map_name(header.fetch(:resolved_map_id))
  if header[:selected_map_id] != header[:resolved_map_id]
    map += ", from " + aoe2de_map_name(header.fetch(:selected_map_id))
  end
  puts "Map: " + map
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

  if true
    # Dump more potentially useful stuff from the header
    header = header.dup
    info_printed = %i{inflated_header players empty_slots resolved_map_id selected_map_id
      build lobby_name save_version timestamp ai_strings ai_scripts map_zones tiles}
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
