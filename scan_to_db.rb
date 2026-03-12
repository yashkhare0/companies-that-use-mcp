#!/usr/bin/env ruby
# scan_to_db.rb - Scan domains and store prospect results in SQLite

require_relative 'mcp_scanner'
require 'csv'
require 'fileutils'
require 'json'
require 'resolv'
require 'securerandom'
require 'sqlite3'
require 'time'
require 'timeout'

DB_PATH = ENV['DB_PATH'] || File.join(__dir__, 'mcp_scans.db')
LOG_DIR = File.join(__dir__, 'data', 'logs')

def open_db
  unless File.exist?(DB_PATH)
    puts "Database not found. Run: ruby setup_db.rb"
    exit 1
  end

  db = SQLite3::Database.new(DB_PATH)
  db.results_as_hash = true
  db.busy_timeout = 5_000
  db
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

  if has_api && !has_mcp
    return {
      priority: 'high',
      reasons: 'Digital-first company with public API signal and no MCP endpoint detected',
      security: ''
    }
  end

  security = []
  security << 'NO_AUTH' if mcp['no_auth'] == 1
  security << 'WIDE_OPEN_CORS' if mcp['wide_open_cors'] == 1
  security << 'NO_RATE_LIMIT' if mcp['rate_limited'] == 0 && has_mcp
  security << 'TOOLS_LEAKED' if mcp['tools_via_cold_probe'] == 1

  if has_mcp
    {
      priority: 'excluded',
      reasons: 'Public MCP already detected; excluded from prospect list',
      security: security.join(', ')
    }
  elsif has_api
    {
      priority: 'high',
      reasons: 'Digital-first company with public API signal and no MCP endpoint detected',
      security: ''
    }
  else
    {
      priority: 'low',
      reasons: 'No public API signal found',
      security: ''
    }
  end
end

def log_line(log_io, message)
  line = "[#{Time.now.utc.iso8601}] #{message}"
  puts line
  log_io.puts(line)
  log_io.flush
end

def log_event(jsonl_io, event_name, payload = {})
  jsonl_io.puts({ ts: Time.now.utc.iso8601, event: event_name }.merge(payload).to_json)
  jsonl_io.flush
end

def show_stats
  db = open_db

  total = db.get_first_value('SELECT COUNT(DISTINCT domain) FROM scans')
  has_api = db.get_first_value('SELECT COUNT(*) FROM latest_scans WHERE has_api = 1')
  has_mcp = db.get_first_value('SELECT COUNT(*) FROM latest_scans WHERE has_mcp = 1')
  prospects = db.get_first_value('SELECT COUNT(*) FROM prospects_high')
  risks = db.get_first_value('SELECT COUNT(*) FROM security_risks')

  puts '=' * 50
  puts 'PROSPECT SCAN DATABASE STATS'
  puts '=' * 50
  puts "Unique domains scanned  : #{total}"
  puts "Has API subdomain       : #{has_api}"
  puts "Has MCP server          : #{has_mcp}"
  puts "Target prospects        : #{prospects}"
  puts "Security risks          : #{risks}"

  puts "\n--- Top 10 Target Prospects ---"
  db.execute('SELECT domain, outreach_reason FROM prospects_high LIMIT 10').each do |row|
    puts "  #{row['domain']} - #{row['outreach_reason']}"
  end

  puts "\n--- Top 10 Security Risks ---"
  db.execute('SELECT domain, tools_count, security_issues FROM security_risks LIMIT 10').each do |row|
    puts "  #{row['domain']} | #{row['tools_count']} tools | #{row['security_issues']}"
  end

  db.close
end

def export_csv(filter)
  db = open_db

  query = case filter
          when 'high', 'prospects' then 'SELECT * FROM prospects_high'
          when 'risks', 'security' then 'SELECT * FROM security_risks'
          else 'SELECT * FROM latest_scans ORDER BY outreach_priority, domain'
          end

  rows = db.execute(query)
  return puts('No data to export.') if rows.empty?

  FileUtils.mkdir_p(File.join(__dir__, 'results'))
  filename = File.join(__dir__, 'results', "export_#{filter}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv")

  CSV.open(filename, 'w') do |csv|
    csv << rows.first.keys
    rows.each { |row| csv << row.values }
  end

  puts "Exported #{rows.size} rows to #{filename}"
  db.close
end

def insert_run(db, run_id, source_file, sample_size, input_domains, scheduled_domains, log_path, jsonl_path)
  db.execute(
    'INSERT INTO scan_runs (run_id, started_at, source_file, sample_size, input_domains, scheduled_domains, status, log_path, jsonl_path) VALUES (?, datetime(\'now\'), ?, ?, ?, ?, ?, ?, ?)',
    [run_id, source_file, sample_size, input_domains, scheduled_domains, 'running', log_path, jsonl_path]
  )
end

def update_run(db, run_id, counts, status, notes = nil)
  db.execute(
    'UPDATE scan_runs SET finished_at = CASE WHEN ? IN (\'completed\', \'failed\') THEN datetime(\'now\') ELSE finished_at END, scanned_domains = ?, api_domains = ?, mcp_domains = ?, prospect_domains = ?, excluded_mcp_domains = ?, status = ?, notes = ? WHERE run_id = ?',
    [status, counts[:scanned], counts[:api], counts[:mcp], counts[:prospects], counts[:excluded_mcp], status, notes, run_id]
  )
end

def scan_domains(file, sample_size = nil)
  db = open_db
  input_domains = File.readlines(file).map(&:strip).reject(&:empty?).uniq
  domains = sample_size ? input_domains.shuffle.first(sample_size) : input_domains.dup

  today = Time.now.strftime('%Y-%m-%d')
  already = db.execute("SELECT domain FROM scans WHERE scanned_at LIKE '#{today}%'").flatten
  before = domains.size
  domains -= already

  FileUtils.mkdir_p(LOG_DIR)
  run_id = "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{SecureRandom.hex(4)}"
  log_path = File.join(LOG_DIR, "scan_#{run_id}.log")
  jsonl_path = File.join(LOG_DIR, "scan_#{run_id}.jsonl")

  File.open(log_path, 'a') do |log_io|
    File.open(jsonl_path, 'a') do |jsonl_io|
      insert_run(db, run_id, file, sample_size, input_domains.size, domains.size, log_path, jsonl_path)

      log_line(log_io, 'Prospect scan started')
      log_line(log_io, "Run ID: #{run_id}")
      log_line(log_io, "Source file: #{file}")
      log_line(log_io, "Input domains: #{input_domains.size}")
      log_line(log_io, "Domains scheduled: #{domains.size}")
      log_line(log_io, "Domains skipped today: #{before - domains.size}")

      log_event(jsonl_io, 'run_started', {
        run_id: run_id,
        source_file: file,
        input_domains: input_domains.size,
        scheduled_domains: domains.size,
        skipped_today: before - domains.size
      })

      counts = {
        scanned: 0,
        api: 0,
        mcp: 0,
        prospects: 0,
        excluded_mcp: 0
      }

      domains.each_with_index do |domain, idx|
        log_line(log_io, "[#{idx + 1}/#{domains.size}] #{domain}")

        has_api = has_api_subdomain?(domain)
        log_line(log_io, "  api.#{domain}: #{has_api ? 'yes' : 'no'}")

        error_message = nil
        mcp_result = begin
          Timeout.timeout(20) { getMcpStatus(domain) }
        rescue => e
          error_message = e.message
          log_line(log_io, "  MCP scan error: #{error_message}")
          { 'mcp' => default_mcp_hash }
        end

        mcp = mcp_result['mcp']
        has_mcp = mcp['status'] == 1
        score = score_prospect(has_api, mcp)

        auth = if mcp['no_auth'] == 1
                 'none'
               elsif mcp['oauth_auth'] == 1
                 'oauth'
               elsif mcp['api_key_auth'] == 1
                 'api_key'
               else
                 'unknown'
               end

        sdk = if mcp['sdk_fastmcp'] == 1
                'FastMCP'
              elsif mcp['sdk_official_ts'] == 1
                'Official TS'
              elsif mcp['sdk_cf_workers_oauth'] == 1
                'CF Workers'
              elsif mcp['sdk_ts_fastmcp'] == 1
                'TS FastMCP'
              elsif mcp['sdk_stagehand'] == 1
                'Stagehand'
              else
                'unknown'
              end

        transport = if mcp['streamable_transport'] == 1
                      'streamable_http'
                    elsif mcp['sse_transport'] == 1
                      'sse'
                    else
                      'unknown'
                    end

        db.execute(
          'INSERT INTO scans (domain, scanned_at, run_id, source_file, has_api, has_mcp, mcp_init_success, mcp_auth_type, mcp_sdk, mcp_transport, mcp_stateful, mcp_protocol_version, tools_count, tools_list, tools_read_count, tools_write_count, tools_unknown_count, no_auth, wide_open_cors, ip_restricted, rate_limited, tools_leaked, cap_tools, cap_resources, cap_prompts, cap_logging, outreach_priority, outreach_reason, security_issues, error) VALUES (?, datetime(\'now\'), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            domain,
            run_id,
            file,
            has_api ? 1 : 0,
            has_mcp ? 1 : 0,
            mcp['init_success'],
            auth,
            sdk,
            transport,
            mcp['stateful'],
            mcp['protocol_version'],
            mcp['tools_count'].to_i,
            mcp['tools_list'],
            mcp['tools_read_count'].to_i,
            mcp['tools_write_count'].to_i,
            mcp['tools_unknown_count'].to_i,
            mcp['no_auth'],
            mcp['wide_open_cors'],
            mcp['ip_restricted'],
            mcp['rate_limited'],
            mcp['tools_via_cold_probe'],
            mcp['cap_tools'],
            mcp['cap_resources'],
            mcp['cap_prompts'],
            mcp['cap_logging'],
            score[:priority],
            score[:reasons],
            score[:security],
            error_message
          ]
        )

        counts[:scanned] += 1
        counts[:api] += 1 if has_api
        counts[:mcp] += 1 if has_mcp
        counts[:prospects] += 1 if has_api && !has_mcp
        counts[:excluded_mcp] += 1 if has_mcp

        log_line(log_io, "  result: api=#{has_api ? 1 : 0} mcp=#{has_mcp ? 1 : 0} prospect=#{has_api && !has_mcp ? 1 : 0} priority=#{score[:priority]}")
        log_event(jsonl_io, 'domain_scanned', {
          run_id: run_id,
          index: idx + 1,
          total: domains.size,
          domain: domain,
          has_api: has_api ? 1 : 0,
          has_mcp: has_mcp ? 1 : 0,
          prospect: has_api && !has_mcp ? 1 : 0,
          priority: score[:priority],
          error: error_message
        })

        if ((idx + 1) % 100).zero? || idx + 1 == domains.size
          update_run(db, run_id, counts, 'running', "Last domain: #{domain}")
          log_line(log_io, "Checkpoint: scanned=#{counts[:scanned]} api=#{counts[:api]} mcp=#{counts[:mcp]} prospects=#{counts[:prospects]}")
        end
      end

      update_run(db, run_id, counts, 'completed', 'Run completed successfully')
      log_line(log_io, 'Prospect scan complete')
      log_line(log_io, "Run log: #{log_path}")
      log_line(log_io, "Event log: #{jsonl_path}")
      log_event(jsonl_io, 'run_completed', counts.merge(run_id: run_id))
    end
  end

  db.close
end

if __FILE__ == $0
  if ARGV[0] == '--stats'
    show_stats
  elsif ARGV[0] == '--export'
    export_csv(ARGV[1] || 'all')
  elsif ARGV[0] && File.exist?(ARGV[0])
    scan_domains(ARGV[0], ARGV[1]&.to_i)
  else
    puts 'Usage:'
    puts '  ruby scan_to_db.rb domains.txt [sample_size]   - scan domains into SQLite'
    puts '  ruby scan_to_db.rb --stats                      - show DB stats'
    puts '  ruby scan_to_db.rb --export prospects|all|security - export to CSV'
  end
end
