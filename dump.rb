#!/usr/bin/env ruby
# Utility for dumping data from AOE2 recorded games.

require_relative 'aoe2rec'
require 'json'
require 'stringio'

$stdout.sync = true

def dump_header(header)
  puts "Map: #{aoe2de_map_name(header.fetch(:resolved_map_id))}"
  puts "Players:"
  header[:players].each do |pl|
    puts "ID #{pl.fetch(:player_id)}, FID #{pl.fetch(:force_id)} = #{pl.fetch(:color_id)+1} #{pl.fetch(:name)}"
  end
  puts "Recorded by FID #{header.fetch(:force_id)}"
end

total_time = 0
filenames = ARGV
filenames.each do |filename|
  time = 0
  io = File.open(filename, 'rb') { |f| StringIO.new f.read }
  puts "#{filename}:"
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
  end
  puts "Replay ends at #{aoe2_pretty_time(time)}"
  puts
  puts
  total_time += time
end

if filenames.size > 1
  puts "Total time for all #{filenames.size} replays: #{aoe2_pretty_time(total_time)}"
end
