#!/usr/bin/env ruby
# setup_db.rb — Initialize SQLite database for MCP scan results
#
# Usage: ruby setup_db.rb

require 'sqlite3'

DB_PATH = File.join(__dir__, 'mcp_scans.db')

db = SQLite3::Database.new(DB_PATH)

db.execute_batch <<-SQL
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

  CREATE INDEX IF NOT EXISTS idx_domain ON scans(domain);
  CREATE INDEX IF NOT EXISTS idx_priority ON scans(outreach_priority);
  CREATE INDEX IF NOT EXISTS idx_has_api ON scans(has_api);
  CREATE INDEX IF NOT EXISTS idx_has_mcp ON scans(has_mcp);
  CREATE INDEX IF NOT EXISTS idx_scanned_at ON scans(scanned_at);

  -- Deduplicated view: latest scan per domain
  CREATE VIEW IF NOT EXISTS latest_scans AS
  SELECT * FROM scans
  WHERE id IN (
    SELECT MAX(id) FROM scans GROUP BY domain
  );

  -- High priority prospects view
  CREATE VIEW IF NOT EXISTS prospects_high AS
  SELECT * FROM latest_scans WHERE outreach_priority = 'high'
  ORDER BY tools_count DESC, domain;

  -- Companies with MCP but security issues
  CREATE VIEW IF NOT EXISTS security_risks AS
  SELECT * FROM latest_scans
  WHERE has_mcp = 1 AND (no_auth = 1 OR wide_open_cors = 1 OR tools_leaked = 1)
  ORDER BY tools_count DESC;
SQL

puts "✅ Database created: #{DB_PATH}"
puts "   Tables: scans"
puts "   Views: latest_scans, prospects_high, security_risks"

# Quick stats if data exists
count = db.get_first_value("SELECT COUNT(*) FROM scans")
puts "   Records: #{count}"

db.close
