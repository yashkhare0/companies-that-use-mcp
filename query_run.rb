#!/usr/bin/env ruby
# query_run.rb - Print scan results for a specific run from SQLite

require 'sqlite3'

db_path = ENV['DB_PATH'] || File.join(__dir__, 'mcp_scans.db')
run_id = ARGV[0]

abort 'Usage: ruby query_run.rb RUN_ID' unless run_id

db = SQLite3::Database.new(db_path)
db.results_as_hash = true

rows = db.execute(
  'SELECT domain, outreach_priority, has_api, has_mcp, outreach_reason FROM scans WHERE run_id = ? ORDER BY outreach_priority, domain',
  [run_id]
)

rows.each do |row|
  puts [row['domain'], row['outreach_priority'], row['has_api'], row['has_mcp'], row['outreach_reason']].join("\t")
end

db.close
