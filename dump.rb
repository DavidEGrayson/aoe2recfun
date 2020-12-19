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
  puts "Recorded by FID #{header.fetch(:player_id)}"
end

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
  s = time / 1000
  m, s = s.divmod(60)
  h, m = m.divmod(60)
  puts "Replay ends at %d:%02d:%02d" % [ h, m, s ]
  puts
  puts
end
