#!/usr/bin/env ruby
# Utility for dumping data from AOE2 recorded games.

require_relative 'aoe2rec'

$stdout.sync = true

def dump_header(header)
  puts "Players:"
  header[:players].each do |pl|
    puts "ID #{pl.fetch(:player_id)} = #{pl.fetch(:color_id)+1} #{pl.fetch(:name)}"
  end
  puts "Recorded by player ID: #{header.fetch(:player_id)}"
end

filenames = ARGV
filenames.each do |filename|
  File.open(filename, 'rb') do |io|
    puts "#{filename}:"
    dump_header aoe2rec_parse_header(io)
    while (op = aoe2rec_parse_operation(io))
      if op.fetch(:operation) == :chat
        p op.fetch(:json)
      end
    end
  end
end
