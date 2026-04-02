#!/usr/bin/env ruby
# shard_domains.rb - Split a domain list into evenly sized shard files

require 'fileutils'
require 'time'
require_relative 'lib/prospecting/paths'

abort 'Usage: ruby shard_domains.rb domains.txt shard_count [output_dir]' unless ARGV[0] && File.exist?(ARGV[0]) && ARGV[1]

input_path = ARGV[0]
shard_count = ARGV[1].to_i
abort 'shard_count must be > 0' if shard_count <= 0

timestamp = Time.now.utc.strftime('%Y%m%d_%H%M%S')
output_dir = ARGV[2] || File.join(Prospecting::Paths::PROCESSED_DIR, "shards_#{timestamp}")
FileUtils.mkdir_p(output_dir)

domains = File.readlines(input_path, chomp: true).map(&:strip).reject(&:empty?).uniq
shards = Array.new(shard_count) { [] }

domains.each_with_index do |domain, idx|
  shards[idx % shard_count] << domain
end

manifest_path = File.join(output_dir, 'manifest.txt')

File.open(manifest_path, 'w') do |manifest|
  shards.each_with_index do |items, idx|
    path = File.join(output_dir, format('shard_%03d.txt', idx + 1))
    File.write(path, items.join("\n") + "\n")
    manifest.puts("#{path}\t#{items.size}")
    puts "Wrote #{items.size} domains -> #{path}"
  end
end

puts "Manifest: #{manifest_path}"
