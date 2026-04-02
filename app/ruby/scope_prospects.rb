# scope_prospects.rb
#
# Drio Prospect Scoper — scans domains for MCP presence and generates
# an outreach-ready CSV with company info, MCP status, and security posture.
#
# Usage:
#   ruby scope_prospects.rb domains.txt              # scan all
#   ruby scope_prospects.rb domains.txt 50           # scan random 50
#   ruby scope_prospects.rb domains.txt --api-only   # only check api.* subdomains (no MCP yet = prospects)
#
# Output: results/scan_YYYY-MM-DD_HHMMSS.csv
#
# Each row contains:
#   domain, has_api, has_mcp, mcp_auth, mcp_sdk, mcp_transport, tools_count,
#   tools_list, security_issues, outreach_priority, outreach_reason

require_relative 'mcp_scanner'
require 'csv'
require 'resolv'
require 'net/http'
require 'openssl'
require 'timeout'
require 'json'

# =============================================================================
# API SUBDOMAIN CHECK
# =============================================================================

def has_api_subdomain?(domain)
  records = begin
    Resolv.getaddresses("api.#{domain}")
  rescue
    []
  end
  !records.empty?
end

# =============================================================================
# PROSPECT SCORING
# =============================================================================

def score_prospect(has_api, mcp_result)
  mcp = mcp_result['mcp']
  has_mcp = mcp['status'] == 1

  reasons = []
  priority = 'low'

  if has_api && !has_mcp
    # Best prospect: has API infrastructure, no MCP yet
    priority = 'high'
    reasons << 'Has API but no MCP — ready for MCP adoption'
  elsif has_api && has_mcp && mcp['no_auth'] == 1
    # Has MCP but insecure — needs better tooling
    priority = 'high'
    reasons << 'Has MCP but NO AUTH — security risk, needs Drio'
  elsif has_api && has_mcp && mcp['tools_count'].to_i <= 4
    # Has MCP but barely using it — needs better tooling
    priority = 'medium'
    reasons << "Has MCP but only #{mcp['tools_count']} tools — early stage, needs better builder"
  elsif has_api && has_mcp
    # Has both, fully set up — lower priority but potential upgrade
    priority = 'low'
    reasons << 'Has API + MCP — potential upgrade/migration target'
  elsif !has_api && !has_mcp
    # No API, no MCP — might need Drio to get started
    priority = 'medium'
    reasons << 'No API or MCP — could use Drio as first AI integration'
  elsif !has_api && has_mcp
    # No API but has MCP — early adopter of MCP-first approach
    priority = 'low'
    reasons << 'MCP-first company — already building'
  end

  security_issues = []
  security_issues << 'NO_AUTH' if mcp['no_auth'] == 1
  security_issues << 'WIDE_OPEN_CORS' if mcp['wide_open_cors'] == 1
  security_issues << 'NO_RATE_LIMIT' if mcp['rate_limited'] == 0 && has_mcp
  security_issues << 'TOOLS_LEAKED' if mcp['tools_via_cold_probe'] == 1

  {
    priority: priority,
    reasons: reasons.join('; '),
    security_issues: security_issues.join(', ')
  }
end

# =============================================================================
# MAIN
# =============================================================================

if __FILE__ == $0
  file = ARGV[0]
  sample_size = ARGV[1]&.to_i unless ARGV[1] == '--api-only'
  api_only = ARGV.include?('--api-only')

  unless file && File.exist?(file)
    puts "Usage: ruby scope_prospects.rb domains.txt [sample_size] [--api-only]"
    puts ""
    puts "  domains.txt   — one domain per line (e.g. stripe.com)"
    puts "  sample_size   — optional, scan a random subset"
    puts "  --api-only    — only find companies WITH api.* but WITHOUT mcp.* (best prospects)"
    puts ""
    puts "Output: results/scan_<timestamp>.csv"
    exit 1
  end

  domains = File.readlines(file).map(&:strip).reject(&:empty?).uniq
  domains = domains.shuffle.first(sample_size) if sample_size

  # Create results directory
  Dir.mkdir('results') unless Dir.exist?('results')
  timestamp = Time.now.strftime('%Y-%m-%d_%H%M%S')
  csv_file = "results/scan_#{timestamp}.csv"

  puts "=" * 60
  puts "DRIO PROSPECT SCOPER"
  puts "=" * 60
  puts "Domains to scan: #{domains.size}"
  puts "Mode: #{api_only ? 'API-only (find prospects without MCP)' : 'Full scan'}"
  puts "Output: #{csv_file}"
  puts "-" * 60

  results = []
  stats = { total: 0, has_api: 0, has_mcp: 0, high: 0, medium: 0, low: 0 }

  CSV.open(csv_file, 'w') do |csv|
    csv << [
      'domain', 'has_api', 'has_mcp', 'mcp_auth_type', 'mcp_sdk',
      'mcp_transport', 'tools_count', 'tools_list', 'security_issues',
      'outreach_priority', 'outreach_reason'
    ]

    domains.each_with_index do |domain, idx|
      puts "\n[#{idx + 1}/#{domains.size}] #{domain}"
      stats[:total] += 1

      # Check API subdomain
      has_api = has_api_subdomain?(domain)
      stats[:has_api] += 1 if has_api
      puts "  api.#{domain}: #{has_api ? '✓ exists' : '✗ not found'}"

      # If api-only mode, skip MCP scan for domains without API
      if api_only && !has_api
        puts "  Skipping (no API subdomain)"
        next
      end

      # Scan for MCP
      mcp_result = begin
        Timeout.timeout(20) { getMcpStatus(domain) }
      rescue => e
        puts "  MCP scan error: #{e.message}"
        { 'mcp' => default_mcp_hash }
      end

      mcp = mcp_result['mcp']
      has_mcp = mcp['status'] == 1
      stats[:has_mcp] += 1 if has_mcp

      # Determine auth type
      auth = if mcp['no_auth'] == 1 then 'none'
             elsif mcp['oauth_auth'] == 1 then 'oauth'
             elsif mcp['api_key_auth'] == 1 then 'api_key'
             else 'unknown'
             end

      # Determine SDK
      sdk = if mcp['sdk_fastmcp'] == 1 then 'FastMCP'
            elsif mcp['sdk_official_ts'] == 1 then 'Official TS'
            elsif mcp['sdk_cf_workers_oauth'] == 1 then 'CF Workers'
            elsif mcp['sdk_ts_fastmcp'] == 1 then 'TS FastMCP'
            elsif mcp['sdk_stagehand'] == 1 then 'Stagehand'
            else 'unknown'
            end

      # Determine transport
      transport = if mcp['streamable_transport'] == 1 then 'streamable_http'
                  elsif mcp['sse_transport'] == 1 then 'sse'
                  else 'unknown'
                  end

      # Score the prospect
      score = score_prospect(has_api, mcp_result)
      stats[score[:priority].to_sym] += 1

      puts "  MCP: #{has_mcp ? '✓' : '✗'} | API: #{has_api ? '✓' : '✗'} | Priority: #{score[:priority].upcase}"

      csv << [
        domain, has_api, has_mcp, auth, sdk, transport,
        mcp['tools_count'], mcp['tools_list'],
        score[:security_issues], score[:priority], score[:reasons]
      ]
    end
  end

  puts "\n#{'=' * 60}"
  puts "SCAN COMPLETE"
  puts "#{'=' * 60}"
  puts "Total scanned  : #{stats[:total]}"
  puts "Has API        : #{stats[:has_api]}"
  puts "Has MCP        : #{stats[:has_mcp]}"
  puts "Gap (API, no MCP): #{stats[:has_api] - stats[:has_mcp]}"
  puts ""
  puts "HIGH priority  : #{stats[:high]}"
  puts "MEDIUM priority: #{stats[:medium]}"
  puts "LOW priority   : #{stats[:low]}"
  puts ""
  puts "Results: #{csv_file}"
  puts "#{'=' * 60}"
end
