#!/usr/bin/env ruby
# export_run_report.rb - Join scan results with candidate metadata for a specific run

require 'csv'
require 'sqlite3'
require_relative 'lib/prospecting/paths'

db_path = Prospecting::Paths::DEFAULT_DB_PATH
run_id = ARGV[0]
metadata_csv = ARGV[1]
output_csv = ARGV[2]
filter = ARGV[3] || 'all'

abort 'Usage: ruby export_run_report.rb RUN_ID metadata.csv output.csv [all|high|excluded|low]' unless run_id && metadata_csv && output_csv

metadata = {}
CSV.foreach(metadata_csv, headers: true) do |row|
  metadata[row['domain']] = row.to_h
end

db = SQLite3::Database.new(db_path)
db.results_as_hash = true

where_clause =
  case filter
  when 'high' then "AND outreach_priority = 'high'"
  when 'excluded' then "AND outreach_priority = 'excluded'"
  when 'low' then "AND outreach_priority = 'low'"
  else ''
  end

rows = db.execute(
  "SELECT domain, outreach_priority, has_api, has_mcp, outreach_reason FROM scans WHERE run_id = ? #{where_clause} ORDER BY outreach_priority, domain",
  [run_id]
)

CSV.open(output_csv, 'w') do |csv|
  csv << %w[domain name source icp_tier icp_score signal_score signal_trust tags batch team_size location one_liner has_api has_mcp outreach_priority outreach_reason company_url]
  rows.each do |row|
    meta = metadata[row['domain']] || {}
    csv << [
      row['domain'],
      meta['name'],
      meta['source'],
      meta['icp_tier'],
      meta['icp_score'],
      meta['signal_score'],
      meta['signal_trust'],
      meta['tags'],
      meta['batch'],
      meta['team_size'],
      meta['location'],
      meta['one_liner'],
      row['has_api'],
      row['has_mcp'],
      row['outreach_priority'],
      row['outreach_reason'],
      meta['company_url']
    ]
  end
end

puts "Exported #{rows.size} rows -> #{output_csv}"
db.close
