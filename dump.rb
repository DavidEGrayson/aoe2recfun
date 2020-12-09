#!/usr/bin/env ruby
# Utility for dumping data from AOE2 recorded games.

require_relative 'aoe2rec'

$stdout.sync = true

filenames = ARGV
filenames.each do |filename|
  File.open(filename, 'rb') do |file|
    puts "#{filename}:"
    aoe2rec_parse(file) do |x|
      if x[:operation] == :chat
        p x
      end
    end
  end
end
