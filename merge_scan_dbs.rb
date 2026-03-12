#!/usr/bin/env ruby
# merge_scan_dbs.rb - Merge shard SQLite databases into a single database

require 'fileutils'
require 'sqlite3'

abort 'Usage: ruby merge_scan_dbs.rb target.db shard1.db [shard2.db ...]' unless ARGV[0] && ARGV[1]

target_path = File.expand_path(ARGV.shift)
source_paths = ARGV.map { |path| File.expand_path(path) }.select { |path| File.exist?(path) }

abort 'No shard DBs found to merge' if source_paths.empty?

target = SQLite3::Database.new(target_path)
target.results_as_hash = true
target.busy_timeout = 5_000

tables = {
  'scan_runs' => %w[run_id started_at finished_at source_file sample_size input_domains scheduled_domains scanned_domains api_domains mcp_domains prospect_domains excluded_mcp_domains status log_path jsonl_path notes],
  'scans' => %w[domain scanned_at run_id source_file has_api has_mcp mcp_init_success mcp_auth_type mcp_sdk mcp_transport mcp_stateful mcp_protocol_version tools_count tools_list tools_read_count tools_write_count tools_unknown_count no_auth wide_open_cors ip_restricted rate_limited tools_leaked cap_tools cap_resources cap_prompts cap_logging outreach_priority outreach_reason security_issues error]
}.freeze

source_paths.each do |source_path|
  puts "Merging #{source_path}"
  source = SQLite3::Database.new(source_path)
  source.results_as_hash = true

  tables.each do |table, columns|
    placeholders = (['?'] * columns.size).join(', ')
    insert_sql = "INSERT OR IGNORE INTO #{table} (#{columns.join(', ')}) VALUES (#{placeholders})"

    source.execute("SELECT #{columns.join(', ')} FROM #{table}") do |row|
      values = columns.map { |column| row[column] }
      target.execute(insert_sql, values)
    end
  end

  source.close
end

target.close
puts "Merge complete -> #{target_path}"
