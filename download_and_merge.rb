#!/usr/bin/env ruby

# This script downloads replays from the internet and merges them together
# to make a replay where you can see the chat from all players.

require 'fileutils'
require 'json'
require 'net/http'
require 'pathname'
require_relative 'aoe2rec'

prog_name = File.basename($0)
Usage = <<END
Usage: #{prog_name} NAME MATCH_ID

NAME is a name to use for the resulting game files, like 'Alice_vs_Bob_G1_Arabia'.

MATCH_ID should be the numeric match ID, or a URL that matches one of the
following examples:
  54920941
  aoe2de://0/54920941
  https://aoe2.net/api/match?match_id=54920941
  'https://aoe.ms/replay/?gameId=54920941&profileId=1885522'

MATCH_ID can also be the word "fake", in which case this script generates
fake output files for the sake of avoiding spoilers for multi-game sets.

The AOE2RECFUN_OUTPUT_DIR environment variable to a directory to put the outputs.

export AOE2RECFUN_OUTPUT_DIR=/path/to/some/dir/
END

def determine_match_id(str)
  case str
  when /\A(\d+)\Z/ then $1.to_i
  when /\Aaoe2de:\/\/\d\/(\d+)/ then $1.to_i
  when /match_id=(\d+)/ then $1.to_i
  when /gameId=(\d+)/ then $1.to_i
  else
    $stderr.puts "Unrecognized match ID: #{str.inspect}"
    exit 1
  end
end

arg_enum = ARGV.each
match_name = nil
match_id_str = nil
too_many_args = false
loop do
  arg = arg_enum.next
  if match_name.nil?
    match_name = arg.gsub(' ', '_')
  elsif match_id_str.nil?
    match_id_str = arg
  else
    too_many_args = true
  end
end

if match_name.nil? || match_id_str.nil? || too_many_args
  puts Usage
  exit 1
end

output_dir = Pathname(ENV.fetch('AOE2RECFUN_OUTPUT_DIR'))
output_file_relative = match_name + '.aoe2record'
output_file = output_dir + output_file_relative

# Make sure we are not overriding the final output.
if output_file.exist?
  $stderr.puts "The main output file already exists."
  $stderr.puts "Please choose a different name or delete it by running:"
  $stderr.puts "  rm #{output_file}"
  exit 1
end

match_id = determine_match_id(match_id_str)

puts "Name: #{match_name}"
puts "Match ID: #{match_id}"
puts

match_url = "https://aoe2.net/api/match?match_id=#{match_id}"

puts "Fetching #{match_url} ..."
match =  JSON.parse(Net::HTTP.get(URI(match_url)), symbolize_names: true)
match[:match_id] = match[:match_id].to_i

if match[:match_id] != match_id
  raise "Match ID does not match: expected #{match_id}, got #{match[:match_id]}."
end

puts "Lobby name: " + match.fetch(:name)
puts "Players:"
match[:players].each do |pl|
  puts "  #{pl.fetch(:profile_id)} - #{pl.fetch(:name)}"
end
puts "Map: " + aoe2de_map_name(match.fetch(:map_type))
puts

working_dir = output_dir + ('_' + match_name)

# Make a clean working directory.
puts "Games will be downloaded to #{working_dir}"
if File.exist?(working_dir)
  puts "Deleting #{working_dir} because it already exists."
  FileUtils.rm_r(working_dir)
end
puts
FileUtils.mkdir(working_dir)
Dir.chdir(working_dir)

input_filenames = []

match[:players].each do |pl|
  slug = "g#{match_id}_p#{pl.fetch(:profile_id)}"
  input_filenames << "#{slug}.aoe2record"
  replay_url = "https://aoe.ms/replay/?gameId=#{match_id}&profileId=#{pl.fetch(:profile_id)}"

  curl_command = "curl --output #{slug}.zip '#{replay_url}'"
  puts "Running: #{curl_command}"
  system(curl_command)
  if !$?.success?
    $stderr.puts "Download failed."
    exit 1
  end

  unzip_command = "unzip #{slug}.zip && mv AgeIIDE_Replay_*.aoe2record #{slug}.aoe2record"
  puts "Running: #{unzip_command}"
  system(unzip_command)
  if !$?.success?
    $stderr.puts "Unzip or rename failed."
    exit 1
  end
end

puts

puts "Merging games..."
code_dir = File.dirname(File.realpath(__FILE__))
merge_command = "#{code_dir}/merge.rb -o #{output_file} " + input_filenames.join(' ')
puts merge_command
system(merge_command)
if !$?.success?
  $stderr.puts "Merge failed."
  exit 1
end 
puts

www = ENV['AOE2RECFUN_OUTPUT_WWW']
if www
  puts "Merged game available here:"
  puts '  ' + (www + output_file_relative).to_s
end
