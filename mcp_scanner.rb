# mcp_scanner.rb
#
# MCP Server Scanner — scans a list of domains for MCP servers and collects
# metadata including SDK, auth type, transport, security posture, and tools.
#
# Works two ways:
#
#   1) FROM THE COMMAND LINE:
#
#      ruby mcp_scanner.rb stripe.com cloudflare.com hubspot.com
#      ruby mcp_scanner.rb < domains.txt
#      cat domains.txt | ruby mcp_scanner.rb
#
#      Need domains to scan? Download the full list of known MCP servers at:
#      https://bloomberry.com/data/mcp/
#
#   2) AS A LIBRARY:
#
#      require_relative 'mcp_scanner'
#
#      analyzeMcp(["stripe.com", "cloudflare.com"])  # scan a list
#      analyzeMcp(domains, 50)                        # scan a random sample of 50
#      getMcpStatus("stripe.com")                     # probe a single domain
#
# Ruby 2.3+ compatible. No gems required — uses stdlib only:
#   net/http, openssl, uri, json, resolv, timeout

require 'net/http'
require 'openssl'
require 'uri'
require 'json'
require 'timeout'

# =============================================================================
# DNS HELPERS
# =============================================================================

# Resolves A records for a given hostname.
# Returns an array of IP address strings, or [] if none found.
def get_a_records(hostname)
  require 'resolv'
  Resolv.getaddresses(hostname)
rescue
  []
end

# =============================================================================
# ENTRY POINTS
# =============================================================================

# Scans a list of domains for MCP servers and prints aggregate statistics.
#
# @param domains  [Array<String>] list of domain names to probe (e.g. ["stripe.com"])
# @param num      [Integer, nil]  optional — randomly sample this many domains from the list
def analyzeMcp(domains, num = nil)
  domains = domains.shuffle.slice(0, num) if num

  no_auth_domains  = []
  errors           = {}
  protocol_versions = Hash.new(0)
  tools_seen        = Hash.new(0)

  totals = {
    total:                0,
    mcp_detected:         0,
    init_success:         0,
    sdk_fastmcp:          0,
    sdk_official_ts:      0,
    sdk_cf_workers_oauth: 0,
    sdk_ts_fastmcp:       0,
    sdk_stagehand:        0,
    oauth_auth:           0,
    api_key_auth:         0,
    no_auth:              0,
    sse_transport:        0,
    streamable_transport: 0,
    stateful:             0,
    stateless:            0,
    wide_open_cors:       0,
    ip_restricted:        0,
    rate_limited:         0,
    cap_tools:            0,
    cap_resources:        0,
    cap_prompts:          0,
    cap_logging:          0,
    tools_enumerated:     0,
    tools_via_cold_probe: 0,
    total_tools:          0,
    total_tools_read:     0,
    total_tools_write:    0,
    total_tools_unknown:  0,
  }

  domains.each_with_index do |domain, idx|
    puts "[#{idx + 1}/#{domains.size}] Scanning: #{domain}"
    totals[:total] += 1

    begin
      Timeout.timeout(15) do
        result = getMcpStatus(domain)
        mcp    = result['mcp']
        next unless mcp['status'] == 1

        totals[:mcp_detected] += 1

        # Tally up all binary (0/1) fields
        %i[
          init_success
          sdk_fastmcp sdk_official_ts sdk_cf_workers_oauth sdk_ts_fastmcp sdk_stagehand
          oauth_auth api_key_auth no_auth
          sse_transport streamable_transport
          stateful stateless
          wide_open_cors ip_restricted rate_limited
          cap_tools cap_resources cap_prompts cap_logging
          tools_enumerated tools_via_cold_probe
        ].each { |key| totals[key] += mcp[key.to_s].to_i }

        # Track domains that expose tools without authentication
        if mcp['no_auth'] == 1
          no_auth_domains << {
            domain:      domain,
            tools:       mcp['tools_list'],
            tools_count: mcp['tools_count'],
            cors:        mcp['wide_open_cors'],
            sdk:         mcp.select { |k, v| k.start_with?('sdk_') && v == 1 }.keys.first
          }
        end

        protocol_versions[mcp['protocol_version']] += 1 if mcp['protocol_version']

        if mcp['tools_count'].to_i > 0
          totals[:total_tools]         += mcp['tools_count'].to_i
          totals[:total_tools_read]    += mcp['tools_read_count'].to_i
          totals[:total_tools_write]   += mcp['tools_write_count'].to_i
          totals[:total_tools_unknown] += mcp['tools_unknown_count'].to_i

          if mcp['tools_list']
            begin
              tool_names = JSON.parse(mcp['tools_list'])
              tool_names.each { |name| tools_seen[name] += 1 }
            rescue JSON::ParserError
            end
          end
        end
      end

    rescue Timeout::Error
      puts "  TIMEOUT for #{domain}, skipping"
      errors[domain] = 'timeout'
    rescue => e
      puts "  ERROR for #{domain}: #{e.message}"
      errors[domain] = e.message
    end
  end

  print_results(totals, protocol_versions, tools_seen, no_auth_domains, errors)
end

# =============================================================================
# CORE PROBE: getMcpStatus
# =============================================================================

# Probes a single domain for an MCP server on the mcp.* subdomain.
# Returns a hash with all detected attributes.
#
# @param domain           [String]  base domain, e.g. "stripe.com"
# @param check_subdomain  [Boolean] when true, prepends "mcp." to the domain
# @return                 [Hash]    { 'mcp' => { ... } }
def getMcpStatus(domain, check_subdomain = true)
  result = { 'mcp' => default_mcp_hash }

  target = check_subdomain ? "mcp.#{domain}" : domain

  # Skip if the subdomain doesn't resolve
  a_records = get_a_records(target)
  if a_records.empty?
    puts "  No DNS records for #{target}"
    return result
  end

  url = "https://#{target}"
  uri = URI(url)
  puts "  Probing #{url}"

  http              = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl      = true
  http.verify_mode  = OpenSSL::SSL::VERIFY_NONE  # many MCP servers use self-signed certs
  http.read_timeout = 5

  # Try each standard MCP path in turn; stop after the first successful response
  ['/', '/mcp', '/sse'].each do |path|
    next unless probe_path(result, http, path, domain, check_subdomain)
    break  # found a working MCP endpoint
  end

  result
end

# Probes a single path on an already-opened HTTP connection.
# Mutates +result+ in place. Returns true if an MCP response was detected.
def probe_path(result, http, path, domain, check_subdomain)
  # -------------------------------------------------------------------------
  # Step 1: Send MCP initialize request
  # -------------------------------------------------------------------------
  init_request              = Net::HTTP::Post.new(path)
  init_request['Content-Type'] = 'application/json'
  init_request['Accept']       = 'application/json, text/event-stream'
  init_request.body = {
    jsonrpc: '2.0',
    id:      1,
    method:  'initialize',
    params:  {
      protocolVersion: '2024-11-05',
      capabilities:    {},
      clientInfo:      { name: 'mcp-scanner', version: '1.0' }
    }
  }.to_json

  puts "  → initialize #{path}"
  response = http.request(init_request)

  raw_body = response.body.to_s
  # SSE responses embed JSON after "data: " lines; extract the last data frame
  json_str = raw_body.include?("\ndata: ") ? raw_body.split("\ndata: ").last.to_s.strip : raw_body

  json = JSON.parse(json_str)
  return false if json.keys.empty?

  # -------------------------------------------------------------------------
  # Sanity check: make sure this isn't a wildcard DNS hit by probing a
  # deliberately bogus subdomain and checking if it also responds.
  # -------------------------------------------------------------------------
  if check_subdomain
    bogus = "mcpp#{rand(1000..9999)}.#{domain}"
    bogus_result, _ = getMcpStatus(bogus, false)
    return false if bogus_result['mcp']['status'] == 1
  end

  result['mcp']['status'] = 1
  puts "  ✓ MCP detected on #{path}"

  headers = {}
  response.each_header { |k, v| headers[k.downcase] = v }

  # Run all classifiers against the init response
  classify_auth(result,      json_str, json, headers)
  classify_transport(result, json_str, json, headers, http, path)
  classify_state(result,     headers)
  classify_protocol(result,  json)
  classify_security(result,  json_str, headers)
  classify_capabilities(result, json)

  session_id = headers['mcp-session-id']

  # -------------------------------------------------------------------------
  # Step 2: If init succeeded, complete the handshake then enumerate tools
  # -------------------------------------------------------------------------
  if json.dig('result', 'protocolVersion')
    result['mcp']['init_success'] = 1

    # Send notifications/initialized to complete the MCP handshake
    notif              = Net::HTTP::Post.new(path)
    notif['Content-Type']   = 'application/json'
    notif['Accept']          = 'application/json, text/event-stream'
    notif['Mcp-Session-Id'] = session_id if session_id
    notif.body = { jsonrpc: '2.0', method: 'notifications/initialized' }.to_json

    begin
      notif_resp = http.request(notif)
      puts "  ✓ notifications/initialized → #{notif_resp.code}"
    rescue => e
      puts "  ! notifications/initialized failed: #{e.message}"
    end

    sleep(0.2)

    # Enumerate tools
    tools_body = send_tools_list(result, http, path, session_id)
    classify_sdk(result, json_str, json, headers, http, path, tools_body)

  else
    # Init returned an error (likely auth required)
    classify_sdk(result, json_str, json, headers, http, path, nil)

    # -----------------------------------------------------------------------
    # Step 3: Cold tools/list probe — some servers enforce auth on initialize
    # but accidentally leave tools/list open
    # -----------------------------------------------------------------------
    cold_probe_tools(result, http, path)
  end

  true
rescue => e
  puts "  ! Error on #{path}: #{e.message}"
  false
end

# Sends a tools/list request after a successful handshake.
# Returns the raw response body string, or nil on failure.
def send_tools_list(result, http, path, session_id)
  req = Net::HTTP::Post.new(path)
  req['Content-Type']    = 'application/json'
  req['Accept']           = 'application/json, text/event-stream'
  req['Mcp-Session-Id'] = session_id if session_id
  req.body = { jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} }.to_json

  resp     = http.request(req)
  raw      = resp.body.to_s
  body     = raw.include?("\ndata: ") ? raw.split("\ndata: ").last.to_s.strip : raw
  parsed   = JSON.parse(body)
  tools    = parsed.dig('result', 'tools')

  if tools.is_a?(Array)
    result['mcp']['tools_enumerated'] = 1
    result['mcp']['tools_count']      = tools.size
    result['mcp']['tools_list']       = tools.map { |t| t['name'] }.to_json
    classify_tools_read_write(result, tools)
    puts "  ✓ #{tools.size} tools enumerated"
  end

  body
rescue => e
  puts "  ! tools/list failed: #{e.message}"
  nil
end

# Attempts a tools/list call without any session or auth headers.
# Flags the result if tools are returned without authentication.
def cold_probe_tools(result, http, path)
  puts "  → cold tools/list probe (no auth)..."
  req      = Net::HTTP::Post.new(path)
  req['Content-Type'] = 'application/json'
  req['Accept']        = 'application/json, text/event-stream'
  req.body = { jsonrpc: '2.0', id: 99, method: 'tools/list', params: {} }.to_json

  resp   = http.request(req)
  parsed = JSON.parse(resp.body)
  tools  = parsed.dig('result', 'tools')

  if tools.is_a?(Array)
    result['mcp']['tools_via_cold_probe'] = 1
    result['mcp']['tools_enumerated']     = 1
    result['mcp']['tools_count']          = tools.size
    result['mcp']['tools_list']           = tools.map { |t| t['name'] }.to_json
    classify_tools_read_write(result, tools)
    puts "  ⚠ SECURITY: #{tools.size} tools leaked without authentication!"
  end
rescue => e
  puts "  ! cold probe failed: #{e.message}"
end

# =============================================================================
# CLASSIFIERS
# =============================================================================

# Detects which MCP SDK the server is using based on response fingerprints.
# Sets exactly one of: sdk_fastmcp, sdk_official_ts, sdk_cf_workers_oauth,
# sdk_ts_fastmcp, sdk_stagehand.
def classify_sdk(result, body_str, json, headers, http, path, tools_body)
  mcp = result['mcp']

  # Stagehand / Browserbase — identified by distinctive tool name prefixes
  if tools_body
    begin
      tool_names = JSON.parse(tools_body).fetch('result', {})
                                         .fetch('tools', [])
                                         .map { |t| t['name'].to_s }
      if tool_names.any? { |n| n.start_with?('stagehand_', 'browserbase_') }
        mcp['sdk_stagehand'] = 1
        return
      end
    rescue JSON::ParserError
    end
  end

  caps        = json.dig('result', 'capabilities')
  server_info = json.dig('result', 'serverInfo')

  if caps.is_a?(Hash) && server_info.is_a?(Hash)
    # FastMCP (Python) — has 'instructions' key or 'experimental' capability
    if json['result'].is_a?(Hash) && (json['result'].key?('instructions') || caps.key?('experimental'))
      mcp['sdk_fastmcp'] = 1
      return
    end

    # TS FastMCP vs Official TS SDK — both advertise a 'tools' capability;
    # distinguished by whether a /health or /ready endpoint exists
    if caps.key?('tools')
      if probe_ts_fastmcp_health(http, path)
        mcp['sdk_ts_fastmcp'] = 1
      else
        mcp['sdk_official_ts'] = 1
      end
      return
    end
  end

  # Error response fingerprints
  error_code = dig_error_code(json)
  error_msg  = dig_error_message(json).to_s

  # FastMCP produces this specific auth error message
  if body_str.include?("To resolve: clear authentication tokens in your MCP client and reconnect")
    mcp['sdk_fastmcp'] = 1
    return
  end

  if error_code == -32600 && error_msg.include?("Not Acceptable: Client must accept")
    mcp['sdk_fastmcp'] = 1
    return
  end

  if error_code == -32000 && error_msg.include?("Not Acceptable: Client must accept")
    mcp['sdk_official_ts'] = 1
    return
  end

  if error_code == -32000 && error_msg.include?("Bad Request: No valid session ID provided")
    mcp['sdk_official_ts'] = 1
    return
  end

  # Cloudflare Workers OAuth pattern
  if body_str.include?("Missing or invalid access token") && body_str.include?('realm="OAuth"')
    mcp['sdk_cf_workers_oauth'] = 1
    return
  end

  if body_str.include?('invalid_token') && body_str.include?('access token')
    mcp['sdk_cf_workers_oauth'] = 1
  end
end

# Checks whether a TS-FastMCP health endpoint exists (used to distinguish it
# from the official TypeScript SDK, which does not expose one).
def probe_ts_fastmcp_health(http, path)
  ['/health', '/ready'].each do |health_path|
    begin
      resp = http.get(health_path)
      body = resp.body.to_s
      return true if body.include?('"mode"') &&
                     body.include?('"stateless"') &&
                     body.include?('"status"') &&
                     body.include?('"ready"')
    rescue
    end
  end
  false
end

# Classifies how the server requires authentication.
# Sets one or more of: no_auth, oauth_auth, api_key_auth.
def classify_auth(result, body_str, json, headers)
  mcp       = result['mcp']
  www_auth  = headers['www-authenticate'].to_s
  body_lower = body_str.downcase

  # No auth required — initialize returned a protocol version
  if json.dig('result', 'protocolVersion')
    mcp['no_auth'] = 1
    return
  end

  # OAuth — indicated by WWW-Authenticate header or body mentions
  if www_auth.include?('resource_metadata')  ||
     www_auth.include?('oauth-protected-resource') ||
     body_str.include?('oauth-protected-resource') ||
     body_str.include?('authorization_uri')
    mcp['oauth_auth'] = 1
    return
  end

  # Token / OAuth error in body
  if body_str.include?('invalid_token') && body_str.include?('access token')
    mcp['oauth_auth'] = 1
    return
  end

  # API key — various common patterns
  if body_lower.include?('api key')    ||
     body_lower.include?('api_key')   ||
     body_lower.include?('x-api-key') ||
     body_lower.include?('apikey')    ||
     body_lower.include?('bearer token') ||
     body_lower.include?('missing authorization') ||
     body_lower.include?('unauthorized') ||
     body_str.include?("Authorization required")
    mcp['api_key_auth'] = 1
  end
end

# Determines the transport protocol: Streamable HTTP (current standard) or
# legacy SSE (Server-Sent Events).
def classify_transport(result, body_str, json, headers, http, path)
  mcp       = result['mcp']
  error_msg = dig_error_message(json).to_s

  # Streamable HTTP: successful init response
  if json.dig('result', 'protocolVersion')
    mcp['streamable_transport'] = 1
    return
  end

  # Streamable HTTP: server rejected due to Accept header mismatch
  if error_msg.include?("Client must accept both application/json and text/event-stream") ||
     error_msg.include?("Client must accept application/json")
    mcp['streamable_transport'] = 1
    return
  end

  # Legacy SSE: try a GET request and look for text/event-stream content-type
  begin
    get_req = Net::HTTP::Get.new(path)
    get_req['Accept'] = 'text/event-stream'
    get_resp = http.request(get_req)
    if get_resp['content-type'].to_s.include?('text/event-stream')
      mcp['sse_transport'] = 1
      return
    end
  rescue => e
    puts "  ! GET probe failed on #{path}: #{e.message}"
  end

  # SSE fallback: POST rejected with Method Not Allowed but GET is allowed
  allow_header = headers['allow'].to_s.upcase
  if (body_str.include?('Method Not Allowed') || body_str.include?("method 'POST' not supported")) &&
     allow_header.include?('GET') && !allow_header.include?('POST')
    mcp['sse_transport'] = 1
  end
end

# Determines whether the session is stateful (has Mcp-Session-Id) or stateless.
def classify_state(result, headers)
  if headers.key?('mcp-session-id')
    result['mcp']['stateful'] = 1
  else
    result['mcp']['stateless'] = 1
  end
end

# Records the MCP protocol version advertised by the server.
def classify_protocol(result, json)
  version = json.dig('result', 'protocolVersion')
  result['mcp']['protocol_version'] = version if version
end

# Checks for common security issues: wide-open CORS, IP allowlisting, rate limiting.
def classify_security(result, body_str, headers)
  mcp        = result['mcp']
  body_lower = body_str.downcase

  mcp['wide_open_cors'] = 1 if headers['access-control-allow-origin'] == '*'

  if body_lower.include?('not in allowlist') ||
     body_lower.include?('ip blocked')       ||
     body_lower.include?('ip whitelist')     ||
     body_lower.include?('ip not allowed')
    mcp['ip_restricted'] = 1
  end

  if headers.key?('ratelimit-limit')   ||
     headers.key?('x-ratelimit-limit') ||
     headers.key?('x-rate-limit-limit')
    mcp['rate_limited'] = 1
  end
end

# Records which capability categories the server advertises (tools, resources,
# prompts, logging).
def classify_capabilities(result, json)
  caps = json.dig('result', 'capabilities')
  return unless caps.is_a?(Hash)

  mcp = result['mcp']
  mcp['cap_tools']     = 1 if caps.key?('tools')
  mcp['cap_resources'] = 1 if caps.key?('resources')
  mcp['cap_prompts']   = 1 if caps.key?('prompts')
  mcp['cap_logging']   = 1 if caps.key?('logging')
end

# Classifies each tool as a read or write operation based on its name prefix
# and, as a fallback, keywords in its description.
def classify_tools_read_write(result, tools)
  write_prefixes = %w[
    create update delete remove send post put patch
    set add insert schedule cancel submit execute run
    invoke trigger start stop enable disable assign
    upload write modify edit replace move copy rename
    publish deploy revoke reset clear purge archive
    unarchive restore approve reject close reopen
    subscribe unsubscribe register unregister
    book order purchase pay checkout transfer
    merge split lock unlock pin unpin mute unmute
    ban unban block unblock follow unfollow
    mark flag tag untag label
  ]

  read_prefixes = %w[
    get fetch list search find query read retrieve
    lookup check describe show view count
    download export extract analyze summarize
    suggest recommend preview validate verify
    calculate compute estimate compare
    parse inspect monitor watch status ping health
  ]

  # Fallback keyword lists for when neither prefix matches
  write_signals = %w[creates updates deletes sends modifies submits triggers
                     executes schedules write mutate change remove cancel
                     publish deploy upload]
  read_signals  = %w[returns retrieves fetches lists searches finds gets shows
                     displays read-only readonly query]

  reads    = []
  writes   = []
  unknowns = []

  tools.each do |tool|
    raw_name = tool['name'] || ''
    name     = raw_name.downcase.gsub(/[-_]/, ' ').strip
    desc     = (tool['description'] || '').downcase
    classified = false

    write_prefixes.each do |prefix|
      if name == prefix || name.start_with?("#{prefix} ", "#{prefix}_", "#{prefix}-", prefix)
        writes << raw_name
        classified = true
        break
      end
    end
    next if classified

    read_prefixes.each do |prefix|
      if name == prefix || name.start_with?("#{prefix} ", "#{prefix}_", "#{prefix}-", prefix)
        reads << raw_name
        classified = true
        break
      end
    end
    next if classified

    # Description fallback
    if write_signals.any? { |s| desc.include?(s) }
      writes << raw_name
    elsif read_signals.any? { |s| desc.include?(s) }
      reads << raw_name
    else
      unknowns << raw_name
    end
  end

  mcp = result['mcp']
  mcp['tools_read_count']   = reads.size
  mcp['tools_write_count']  = writes.size
  mcp['tools_unknown_count'] = unknowns.size
  mcp['tools_read_list']    = reads.to_json
  mcp['tools_write_list']   = writes.to_json
end

# =============================================================================
# HELPERS
# =============================================================================

# Returns an empty MCP result hash with all fields initialised to their
# zero/nil defaults. This makes downstream code safe against missing keys.
def default_mcp_hash
  {
    # Detection
    'status'               => 0,
    'body'                 => nil,

    # SDK detection (exactly one will be set to 1 when identified)
    'sdk_fastmcp'          => 0,
    'sdk_official_ts'      => 0,
    'sdk_cf_workers_oauth' => 0,
    'sdk_ts_fastmcp'       => 0,
    'sdk_stagehand'        => 0,

    # Authentication method
    'oauth_auth'           => 0,
    'api_key_auth'         => 0,
    'no_auth'              => 0,

    # Transport protocol
    'sse_transport'        => 0,
    'streamable_transport' => 0,

    # Session state
    'stateful'             => 0,
    'stateless'            => 0,

    # MCP protocol version string (e.g. "2024-11-05")
    'protocol_version'     => nil,

    # Security posture
    'wide_open_cors'       => 0,
    'ip_restricted'        => 0,
    'rate_limited'         => 0,

    # Advertised capabilities (from successful init)
    'cap_tools'            => 0,
    'cap_resources'        => 0,
    'cap_prompts'          => 0,
    'cap_logging'          => 0,

    # Tool enumeration results
    'init_success'         => 0,
    'tools_enumerated'     => 0,
    'tools_count'          => nil,
    'tools_list'           => nil,          # JSON array of tool names
    'tools_via_cold_probe' => 0,            # 1 = tools leaked without auth
    'tools_read_count'     => 0,
    'tools_write_count'    => 0,
    'tools_unknown_count'  => 0,
    'tools_read_list'      => nil,          # JSON array
    'tools_write_list'     => nil,          # JSON array
  }
end

# Extracts the JSON-RPC error code from a parsed response, or nil.
def dig_error_code(json)
  err = json['error']
  err.is_a?(Hash) ? err['code'] : nil
end

# Extracts the JSON-RPC error message string from a parsed response, or nil.
def dig_error_message(json)
  err = json['error']
  err.is_a?(Hash) ? err['message'] : nil
end

# =============================================================================
# OUTPUT
# =============================================================================

# Prints a formatted summary report to stdout.
def print_results(totals, protocol_versions, tools_seen, no_auth_domains, errors)
  pct = lambda { |part, whole| whole.zero? ? 'N/A' : "#{(part.to_f / whole * 100).round(1)}%" }

  d   = totals[:mcp_detected]
  e   = totals[:tools_enumerated]

  puts "\n#{'=' * 50}"
  puts "MCP SCAN RESULTS"
  puts "#{'-' * 50}"
  puts "Domains scanned : #{totals[:total]}"
  puts "MCP detected    : #{d} (#{pct.call(d, totals[:total])})"
  puts "Init succeeded  : #{totals[:init_success]} (#{pct.call(totals[:init_success], d)})"
  puts "Errors          : #{errors.size}"

  puts "\n--- SDK ---"
  puts "FastMCP (Python)     : #{totals[:sdk_fastmcp]} (#{pct.call(totals[:sdk_fastmcp], d)})"
  puts "Official TypeScript  : #{totals[:sdk_official_ts]} (#{pct.call(totals[:sdk_official_ts], d)})"
  puts "TS FastMCP           : #{totals[:sdk_ts_fastmcp]} (#{pct.call(totals[:sdk_ts_fastmcp], d)})"
  puts "CF Workers OAuth     : #{totals[:sdk_cf_workers_oauth]} (#{pct.call(totals[:sdk_cf_workers_oauth], d)})"
  puts "Stagehand/Browserbase: #{totals[:sdk_stagehand]} (#{pct.call(totals[:sdk_stagehand], d)})"

  puts "\n--- Authentication ---"
  puts "No auth  : #{totals[:no_auth]} (#{pct.call(totals[:no_auth], d)})"
  puts "OAuth    : #{totals[:oauth_auth]} (#{pct.call(totals[:oauth_auth], d)})"
  puts "API key  : #{totals[:api_key_auth]} (#{pct.call(totals[:api_key_auth], d)})"

  puts "\n--- Transport ---"
  puts "Streamable HTTP : #{totals[:streamable_transport]} (#{pct.call(totals[:streamable_transport], d)})"
  puts "SSE (deprecated): #{totals[:sse_transport]} (#{pct.call(totals[:sse_transport], d)})"

  puts "\n--- Session State ---"
  puts "Stateful  : #{totals[:stateful]} (#{pct.call(totals[:stateful], d)})"
  puts "Stateless : #{totals[:stateless]} (#{pct.call(totals[:stateless], d)})"

  puts "\n--- Security ---"
  puts "Wide-open CORS  : #{totals[:wide_open_cors]} (#{pct.call(totals[:wide_open_cors], d)})"
  puts "IP restricted   : #{totals[:ip_restricted]} (#{pct.call(totals[:ip_restricted], d)})"
  puts "Rate limited    : #{totals[:rate_limited]} (#{pct.call(totals[:rate_limited], d)})"
  puts "Cold probe leaks: #{totals[:tools_via_cold_probe]} (#{pct.call(totals[:tools_via_cold_probe], d)})"

  puts "\n--- Capabilities (from successful init) ---"
  puts "Tools     : #{totals[:cap_tools]}"
  puts "Resources : #{totals[:cap_resources]}"
  puts "Prompts   : #{totals[:cap_prompts]}"
  puts "Logging   : #{totals[:cap_logging]}"

  puts "\n--- Tool Enumeration ---"
  puts "Servers enumerated   : #{e} (#{pct.call(e, d)})"
  puts "Total tools          : #{totals[:total_tools]}"
  puts "Avg tools per server : #{e.zero? ? 'N/A' : (totals[:total_tools].to_f / e).round(1)}"
  puts "Read tools           : #{totals[:total_tools_read]}"
  puts "Write tools          : #{totals[:total_tools_write]}"
  puts "Unknown tools        : #{totals[:total_tools_unknown]}"

  puts "\n--- Protocol Versions ---"
  if protocol_versions.empty?
    puts "(none detected)"
  else
    protocol_versions.sort_by { |_, c| -c }.each do |ver, count|
      puts "  #{ver}: #{count} (#{pct.call(count, d)})"
    end
  end

  puts "\n--- Top 20 Tool Names ---"
  if tools_seen.empty?
    puts "(none)"
  else
    tools_seen.sort_by { |_, c| -c }.first(20).each_with_index do |(name, count), i|
      puts "  #{(i + 1).to_s.rjust(2)}. #{name}: #{count}"
    end
  end

  unless no_auth_domains.empty?
    puts "\n--- Domains with No Authentication (⚠ security risk) ---"
    no_auth_domains.each do |d|
      puts "  #{d[:domain]} | cors=#{d[:cors]} | tools=#{d[:tools_count]} | sdk=#{d[:sdk]}"
      puts "    tools: #{d[:tools]}" if d[:tools]
    end
  end

  unless errors.empty?
    puts "\n--- Errors ---"
    errors.each { |domain, msg| puts "  #{domain}: #{msg}" }
  end

  puts "\n#{'=' * 50}"
  puts "Done."
end

# =============================================================================
# CLI ENTRY POINT
# =============================================================================
#
# Run directly from the command line:
#
#   ruby mcp_scanner.rb stripe.com cloudflare.com hubspot.com
#
#   cat domains.txt | ruby mcp_scanner.rb
#
#   ruby mcp_scanner.rb < domains.txt
#
# Need a list of domains to scan? Download the full list of known MCP servers
# (updated regularly) from: https://bloomberry.com/data/mcp/
# Save the domains one per line into a .txt file and pipe it in as above.
#
if __FILE__ == $0
  domains = ARGV.map(&:strip).reject(&:empty?)

  # Fall back to stdin if no args given (supports piping / redirection)
  if domains.empty? && !STDIN.tty?
    domains = STDIN.read.split("\n").map(&:strip).reject(&:empty?)
  end

  if domains.empty?
    puts "Usage:"
    puts "  ruby mcp_scanner.rb stripe.com cloudflare.com ..."
    puts "  ruby mcp_scanner.rb < domains.txt"
    puts "  cat domains.txt | ruby mcp_scanner.rb"
    puts ""
    puts "Get a list of known MCP server domains at: https://bloomberry.com/data/mcp/"
    exit 1
  end

  analyzeMcp(domains)
end
