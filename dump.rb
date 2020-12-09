#!/usr/bin/env ruby
# Utility for dumping data from AOE2 recorded games.

require_relative 'aoe2rec'

$stdout.sync = true

filenames = ARGV
filenames.each do |filename|
  File.open(filename, 'rb') do |io|
    puts "#{filename}:"
    p aoe2rec_parse_header(io)
    exit 0 # tmphax
    while (op = aoe2rec_parse_operation(io))
      if op.fetch(:operation) == :chat
        p op.fetch(:json)
      end
    end
  end
end
