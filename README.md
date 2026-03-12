# mcp_scanner.rb

A Ruby script that probes domains for MCP servers and fingerprints their SDK, authentication method, transport protocol, security posture, and exposed tools.

Built to power the research behind [We analyzed 1,400 MCP servers - here's what we learned](https://bloomberry.com/blog/we-analyzed-1400-mcp-servers-heres-what-we-learned/).

A live list of known MCP server domains (updated regularly) is available at [bloomberry.com/data/mcp](https://bloomberry.com/data/mcp/).

---

## Requirements

- Ruby 2.3+
- `mcp_scanner.rb` itself uses only Ruby stdlib: `net/http`, `openssl`, `uri`, `json`, `resolv`, `timeout`
- `setup_db.rb` and `scan_to_db.rb` also require the `sqlite3` Ruby gem

### Docker

If you want an isolated runtime instead of installing Ruby locally, use Docker Desktop:

```bash
# Build the image
docker compose build

# Initialize the database
docker compose run --rm mcp-scanner ruby setup_db.rb

# Build a seed domain list
docker compose run --rm mcp-scanner ruby build_domains.rb > domains_full.txt

# Scan all domains into mcp_scans.db
docker compose run --rm mcp-scanner ruby scan_to_db.rb domains_full.txt

# Show DB stats
docker compose run --rm mcp-scanner ruby scan_to_db.rb --stats

# Export all latest rows or just the highest-priority prospects
docker compose run --rm mcp-scanner ruby scan_to_db.rb --export all
docker compose run --rm mcp-scanner ruby scan_to_db.rb --export high
```

The compose service mounts this repo into the container, so `mcp_scans.db` and `results/` stay on the host.

---

## Usage

### Command line

```bash
# Pass domains as arguments
ruby mcp_scanner.rb stripe.com cloudflare.com hubspot.com

# Read from a file
ruby mcp_scanner.rb < domains.txt

# Pipe in a list
cat domains.txt | ruby mcp_scanner.rb
```

### As a library

```ruby
require_relative 'mcp_scanner'

# Scan a list of domains
analyzeMcp(["stripe.com", "cloudflare.com", "hubspot.com"])

# Scan a random sample of 50 from a larger list
analyzeMcp(domains, 50)

# Probe a single domain and inspect the raw result hash
result = getMcpStatus("stripe.com")
pp result["mcp"]
```

---

## What it detects

| Category | Details |
|---|---|
| **SDK** | FastMCP (Python), Official TypeScript SDK, TS FastMCP, Cloudflare Workers OAuth, Stagehand/Browserbase |
| **Auth** | No auth, OAuth, API key |
| **Transport** | Streamable HTTP (current standard), SSE (deprecated) |
| **State** | Stateful (session ID), Stateless |
| **Security** | Wide-open CORS, IP restrictions, rate limiting, unauthenticated tool leaks |
| **Capabilities** | Tools, Resources, Prompts, Logging |
| **Tools** | Count, names, read vs. write classification |

---

## How it works

For each domain, the scanner:

1. Checks that `mcp.<domain>` resolves in DNS
2. Sends an MCP `initialize` request to `/`, `/mcp`, and `/sse`
3. If init succeeds, completes the handshake and calls `tools/list` to enumerate tools
4. If init fails (auth required), attempts a cold `tools/list` probe to check for unauthenticated tool leaks
5. Fingerprints the SDK, auth method, transport, and security posture from the responses

---

## Output

A summary report is printed after all domains are scanned:

```text
==================================================
MCP SCAN RESULTS
--------------------------------------------------
Domains scanned : 100
MCP detected    : 42 (42.0%)
Init succeeded  : 28 (66.7%)
...
--- Authentication ---
No auth  : 16 (38.1%)
OAuth    : 14 (33.3%)
API key  : 12 (28.6%)
...
--- Top 20 Tool Names ---
   1. search: 18
   2. fetch: 13
   3. ping: 12
...
```

---

## Getting a domain list

The easiest way to get started is to download the curated list of known MCP server domains from [bloomberry.com/data/mcp](https://bloomberry.com/data/mcp/), save it as `domains.txt` (one domain per line), and run:

```bash
ruby mcp_scanner.rb < domains.txt
```

This repo also includes:

- `build_domains.rb` to emit a curated broader seed list into `domains_full.txt`
- `scan_to_db.rb` to scan domains into `mcp_scans.db`
- `scope_prospects.rb` to scan and write a CSV prospect list into `results/`

---

## Methodology notes

- Discovery is based on `mcp.*` subdomains, a strong signal that a company is making a deliberate commitment to MCP versus an internal or staging server
- SSL certificate errors are ignored (`VERIFY_NONE`) since many MCP servers use self-signed certs
- A bogus subdomain check is performed to guard against wildcard DNS responses
- Per-domain timeout is 15 seconds in `mcp_scanner.rb` and 20 seconds in the higher-level wrappers
- The full methodology is described in the blog post linked above

---

## License

MIT
