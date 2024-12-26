#!/usr/bin/env ruby
# Utility for dumping data from AOE2 recorded games.

require_relative 'aoe2rec'

$stdout.sync = true

def dump_header(header)
  puts "File format version: #{header.fetch(:save_version)}"
  puts "Map: #{aoe2de_map_name(header.fetch(:resolved_map_id))}"
  puts "Players:"
  header[:players].each do |pi|
    puts "  %d %-30s ID %d, FID %d, T %d, PR %d" % [
      pi.fetch(:color_id) + 1, (pi.fetch(:name) + pi.fetch(:ai_name)).strip,
      pi.fetch(:player_id), pi.fetch(:force_id), pi.fetch(:type), pi.fetch(:profile_id),
    ]
  end
  puts "Recorded by FID #{header.fetch(:force_id)}"
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
    if op[:operation] == :sync
      time += op.fetch(:time_increment)
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
