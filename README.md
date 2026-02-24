# mcp_scanner.rb

A Ruby script that probes domains for MCP servers and fingerprints their SDK, authentication method, transport protocol, security posture, and exposed tools.

Built to power the research behind **[We analyzed 1,400 MCP servers — here's what we learned](https://bloomberry.com/blog/we-analyzed-1400-mcp-servers-heres-what-we-learned/)**.

A live list of known MCP server domains (updated regularly) is available at **[bloomberry.com/data/mcp](https://bloomberry.com/data/mcp/)**.

---

## Requirements

- Ruby 2.3+
- No gems — stdlib only (`net/http`, `openssl`, `uri`, `json`, `resolv`, `timeout`)

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
pp result['mcp']
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

```
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

The easiest way to get started is to download the curated list of known MCP server domains from **[bloomberry.com/data/mcp](https://bloomberry.com/data/mcp/)**, save it as `domains.txt` (one domain per line), and run:

```bash
ruby mcp_scanner.rb < domains.txt
```

---

## Methodology notes

- Discovery is based on `mcp.*` subdomains — a strong signal that a company is making a deliberate commitment to MCP (vs. an internal or staging server)
- SSL certificate errors are ignored (`VERIFY_NONE`) since many MCP servers use self-signed certs
- A bogus subdomain check is performed to guard against wildcard DNS responses
- Per-domain timeout is 15 seconds
- The full methodology is described in the [blog post](https://bloomberry.com/blog/we-analyzed-1400-mcp-servers-heres-what-we-learned/)

---

## License

MIT
