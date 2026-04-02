#!/usr/bin/env ruby
# setup_db.rb - Initialize SQLite database for MCP prospect scans

require 'sqlite3'
require_relative 'lib/prospecting/paths'

DB_PATH = Prospecting::Paths::DEFAULT_DB_PATH

def ensure_column(db, table_name, column_name, column_sql)
  existing = db.table_info(table_name).map { |row| row['name'] }
  return if existing.include?(column_name)

  db.execute("ALTER TABLE #{table_name} ADD COLUMN #{column_sql}")
end

db = SQLite3::Database.new(DB_PATH)
db.results_as_hash = true

db.execute_batch <<~SQL
  PRAGMA journal_mode = WAL;

  CREATE TABLE IF NOT EXISTS scans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL,
    scanned_at TEXT NOT NULL DEFAULT (datetime('now')),
    has_api INTEGER DEFAULT 0,
    has_mcp INTEGER DEFAULT 0,
    mcp_init_success INTEGER DEFAULT 0,
    mcp_auth_type TEXT,
    mcp_sdk TEXT,
    mcp_transport TEXT,
    mcp_stateful INTEGER DEFAULT 0,
    mcp_protocol_version TEXT,
    tools_count INTEGER DEFAULT 0,
    tools_list TEXT,
    tools_read_count INTEGER DEFAULT 0,
    tools_write_count INTEGER DEFAULT 0,
    tools_unknown_count INTEGER DEFAULT 0,
    no_auth INTEGER DEFAULT 0,
    wide_open_cors INTEGER DEFAULT 0,
    ip_restricted INTEGER DEFAULT 0,
    rate_limited INTEGER DEFAULT 0,
    tools_leaked INTEGER DEFAULT 0,
    cap_tools INTEGER DEFAULT 0,
    cap_resources INTEGER DEFAULT 0,
    cap_prompts INTEGER DEFAULT 0,
    cap_logging INTEGER DEFAULT 0,
    outreach_priority TEXT,
    outreach_reason TEXT,
    security_issues TEXT,
    error TEXT,
    UNIQUE(domain, scanned_at)
  );

  CREATE TABLE IF NOT EXISTS scan_runs (
    run_id TEXT PRIMARY KEY,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    source_file TEXT,
    sample_size INTEGER,
    input_domains INTEGER DEFAULT 0,
    scheduled_domains INTEGER DEFAULT 0,
    scanned_domains INTEGER DEFAULT 0,
    api_domains INTEGER DEFAULT 0,
    mcp_domains INTEGER DEFAULT 0,
    prospect_domains INTEGER DEFAULT 0,
    excluded_mcp_domains INTEGER DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'running',
    log_path TEXT,
    jsonl_path TEXT,
    notes TEXT
  );
SQL

ensure_column(db, 'scans', 'run_id', 'run_id TEXT')
ensure_column(db, 'scans', 'source_file', 'source_file TEXT')

db.execute_batch <<~SQL
  CREATE INDEX IF NOT EXISTS idx_domain ON scans(domain);
  CREATE INDEX IF NOT EXISTS idx_priority ON scans(outreach_priority);
  CREATE INDEX IF NOT EXISTS idx_has_api ON scans(has_api);
  CREATE INDEX IF NOT EXISTS idx_has_mcp ON scans(has_mcp);
  CREATE INDEX IF NOT EXISTS idx_scanned_at ON scans(scanned_at);
  CREATE INDEX IF NOT EXISTS idx_run_id ON scans(run_id);
  CREATE INDEX IF NOT EXISTS idx_scan_runs_started_at ON scan_runs(started_at);
  CREATE INDEX IF NOT EXISTS idx_scan_runs_status ON scan_runs(status);

  DROP VIEW IF EXISTS latest_scans;
  CREATE VIEW latest_scans AS
  SELECT *
  FROM scans
  WHERE id IN (
    SELECT MAX(id) FROM scans GROUP BY domain
  );

  DROP VIEW IF EXISTS prospects_high;
  CREATE VIEW prospects_high AS
  SELECT *
  FROM latest_scans
  WHERE has_api = 1 AND has_mcp = 0
  ORDER BY domain;

  DROP VIEW IF EXISTS security_risks;
  CREATE VIEW security_risks AS
  SELECT *
  FROM latest_scans
  WHERE has_mcp = 1 AND (no_auth = 1 OR wide_open_cors = 1 OR tools_leaked = 1)
  ORDER BY tools_count DESC;
SQL

db.execute(<<~SQL)
  UPDATE scans
  SET outreach_priority = CASE
    WHEN has_api = 1 AND has_mcp = 0 THEN 'high'
    WHEN has_mcp = 1 THEN 'excluded'
    ELSE COALESCE(outreach_priority, 'low')
  END
SQL

db.execute(<<~SQL)
  UPDATE scans
  SET outreach_reason = CASE
    WHEN has_api = 1 AND has_mcp = 0 THEN 'Digital-first company with public API signal and no MCP endpoint detected'
    WHEN has_mcp = 1 THEN 'Public MCP already detected; excluded from prospect list'
    ELSE COALESCE(outreach_reason, 'No public API signal found')
  END
SQL

puts "Database created: #{DB_PATH}"
puts "  Tables: scans, scan_runs"
puts "  Views: latest_scans, prospects_high, security_risks"
puts "  Records: #{db.get_first_value('SELECT COUNT(*) FROM scans')}"

db.close
