#!/usr/bin/env ruby
# scan_to_db.rb — Scan domains and store results in SQLite
#
# Usage:
#   ruby scan_to_db.rb domains.txt           # scan all
#   ruby scan_to_db.rb domains.txt 50        # scan random 50
#   ruby scan_to_db.rb --stats               # show DB stats
#   ruby scan_to_db.rb --export high         # export high priority to CSV
#   ruby scan_to_db.rb --export all          # export all to CSV

require_relative 'mcp_scanner'
require 'sqlite3'
require 'resolv'
require 'timeout'
require 'csv'

DB_PATH = File.join(__dir__, 'mcp_scans.db')

def open_db
  unless File.exist?(DB_PATH)
    puts "Database not found. Run: ruby setup_db.rb"
    exit 1
  end
  SQLite3::Database.new(DB_PATH)
end

def has_api_subdomain?(domain)
  records = begin
    Resolv.getaddresses("api.#{domain}")
  rescue
    []
  end
  !records.empty?
end

def score_prospect(has_api, mcp)
  has_mcp = mcp['status'] == 1
  reasons = []
  priority = 'low'

  if has_api && !has_mcp
    priority = 'high'
    reasons << 'Has API but no MCP — ready for MCP adoption'
  elsif has_api && has_mcp && mcp['no_auth'] == 1
    priority = 'high'
    reasons << 'Has MCP but NO AUTH — security risk, needs Drio'
  elsif has_api && has_mcp && mcp['tools_count'].to_i <= 4
    priority = 'medium'
    reasons << "Has MCP but only #{mcp['tools_count']} tools — early stage"
  elsif has_api && has_mcp
    priority = 'low'
    reasons << 'Has API + MCP — potential upgrade target'
  elsif !has_api && !has_mcp
    priority = 'medium'
    reasons << 'No API or MCP — could use Drio as first AI integration'
  elsif !has_api && has_mcp
    priority = 'low'
    reasons << 'MCP-first company — already building'
  end

  security = []
  security << 'NO_AUTH' if mcp['no_auth'] == 1
  security << 'WIDE_OPEN_CORS' if mcp['wide_open_cors'] == 1
  security << 'NO_RATE_LIMIT' if mcp['rate_limited'] == 0 && has_mcp
  security << 'TOOLS_LEAKED' if mcp['tools_via_cold_probe'] == 1

  { priority: priority, reasons: reasons.join('; '), security: security.join(', ') }
end

def show_stats
  db = open_db
  db.results_as_hash = true

  total = db.get_first_value("SELECT COUNT(DISTINCT domain) FROM scans")
  has_api = db.get_first_value("SELECT COUNT(*) FROM latest_scans WHERE has_api = 1")
  has_mcp = db.get_first_value("SELECT COUNT(*) FROM latest_scans WHERE has_mcp = 1")
  high = db.get_first_value("SELECT COUNT(*) FROM prospects_high")
  risks = db.get_first_value("SELECT COUNT(*) FROM security_risks")

  puts "=" * 50
  puts "MCP SCAN DATABASE STATS"
  puts "=" * 50
  puts "Unique domains scanned : #{total}"
  puts "Has API subdomain      : #{has_api}"
  puts "Has MCP server         : #{has_mcp}"
  puts "Gap (API, no MCP)      : #{has_api.to_i - has_mcp.to_i}"
  puts "HIGH priority prospects : #{high}"
  puts "Security risks          : #{risks}"

  puts "\n--- Top 10 HIGH Priority Prospects ---"
  db.execute("SELECT domain, outreach_reason FROM prospects_high LIMIT 10").each do |row|
    puts "  #{row['domain']} — #{row['outreach_reason']}"
  end

  puts "\n--- Top 10 Security Risks ---"
  db.execute("SELECT domain, tools_count, security_issues FROM security_risks LIMIT 10").each do |row|
    puts "  #{row['domain']} | #{row['tools_count']} tools | #{row['security_issues']}"
  end

  db.close
end

def export_csv(filter)
  db = open_db
  db.results_as_hash = true

  query = case filter
          when 'high' then "SELECT * FROM prospects_high"
          when 'risks', 'security' then "SELECT * FROM security_risks"
          else "SELECT * FROM latest_scans ORDER BY outreach_priority, domain"
          end

  rows = db.execute(query)
  return puts("No data to export.") if rows.empty?

  filename = "results/export_#{filter}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
  Dir.mkdir('results') unless Dir.exist?('results')

  CSV.open(filename, 'w') do |csv|
    csv << rows.first.keys
    rows.each { |row| csv << row.values }
  end

  puts "Exported #{rows.size} rows to #{filename}"
  db.close
end

def scan_domains(file, sample_size = nil)
  db = open_db

  domains = File.readlines(file).map(&:strip).reject(&:empty?).uniq
  domains = domains.shuffle.first(sample_size) if sample_size

  # Skip already scanned (today)
  today = Time.now.strftime('%Y-%m-%d')
  already = db.execute("SELECT domain FROM scans WHERE scanned_at LIKE '#{today}%'").flatten
  before = domains.size
  domains -= already
  puts "Skipping #{before - domains.size} already scanned today" if before != domains.size

  puts "=" * 60
  puts "DRIO PROSPECT SCOPER → SQLite"
  puts "=" * 60
  puts "Domains to scan: #{domains.size}"
  puts "Database: #{DB_PATH}"
  puts "-" * 60

  domains.each_with_index do |domain, idx|
    puts "\n[#{idx + 1}/#{domains.size}] #{domain}"

    has_api = has_api_subdomain?(domain)
    puts "  api.#{domain}: #{has_api ? '✓' : '✗'}"

    mcp_result = begin
      Timeout.timeout(20) { getMcpStatus(domain) }
    rescue => e
      puts "  MCP scan error: #{e.message}"
      { 'mcp' => default_mcp_hash }
    end

    mcp = mcp_result['mcp']
    has_mcp = mcp['status'] == 1
    score = score_prospect(has_api, mcp)

    auth = if mcp['no_auth'] == 1 then 'none'
           elsif mcp['oauth_auth'] == 1 then 'oauth'
           elsif mcp['api_key_auth'] == 1 then 'api_key'
           else 'unknown'
           end

    sdk = if mcp['sdk_fastmcp'] == 1 then 'FastMCP'
          elsif mcp['sdk_official_ts'] == 1 then 'Official TS'
          elsif mcp['sdk_cf_workers_oauth'] == 1 then 'CF Workers'
          elsif mcp['sdk_ts_fastmcp'] == 1 then 'TS FastMCP'
          elsif mcp['sdk_stagehand'] == 1 then 'Stagehand'
          else 'unknown'
          end

    transport = if mcp['streamable_transport'] == 1 then 'streamable_http'
                elsif mcp['sse_transport'] == 1 then 'sse'
                else 'unknown'
                end

    puts "  MCP: #{has_mcp ? '✓' : '✗'} | API: #{has_api ? '✓' : '✗'} | Priority: #{score[:priority].upcase}"

    db.execute(
      "INSERT INTO scans (domain, has_api, has_mcp, mcp_init_success, mcp_auth_type, mcp_sdk, " \
      "mcp_transport, mcp_stateful, mcp_protocol_version, tools_count, tools_list, " \
      "tools_read_count, tools_write_count, tools_unknown_count, no_auth, wide_open_cors, " \
      "ip_restricted, rate_limited, tools_leaked, cap_tools, cap_resources, cap_prompts, " \
      "cap_logging, outreach_priority, outreach_reason, security_issues) " \
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [domain, has_api ? 1 : 0, has_mcp ? 1 : 0, mcp['init_success'],
       auth, sdk, transport, mcp['stateful'], mcp['protocol_version'],
       mcp['tools_count'].to_i, mcp['tools_list'],
       mcp['tools_read_count'].to_i, mcp['tools_write_count'].to_i, mcp['tools_unknown_count'].to_i,
       mcp['no_auth'], mcp['wide_open_cors'], mcp['ip_restricted'], mcp['rate_limited'],
       mcp['tools_via_cold_probe'], mcp['cap_tools'], mcp['cap_resources'],
       mcp['cap_prompts'], mcp['cap_logging'],
       score[:priority], score[:reasons], score[:security]]
    )
  end

  db.close
  puts "\n✅ Scan complete. Run: ruby scan_to_db.rb --stats"
end

# =============================================================================
# CLI
# =============================================================================
if __FILE__ == $0
  if ARGV[0] == '--stats'
    show_stats
  elsif ARGV[0] == '--export'
    export_csv(ARGV[1] || 'all')
  elsif ARGV[0] && File.exist?(ARGV[0])
    scan_domains(ARGV[0], ARGV[1]&.to_i)
  else
    puts "Usage:"
    puts "  ruby scan_to_db.rb domains.txt [sample_size]  — scan domains"
    puts "  ruby scan_to_db.rb --stats                     — show DB stats"
    puts "  ruby scan_to_db.rb --export high|all|security  — export to CSV"
  end
end
