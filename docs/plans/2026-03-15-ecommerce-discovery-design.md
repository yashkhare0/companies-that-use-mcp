# Ecommerce Discovery Design

## Objective
Add a balanced pipeline that identifies active, high-quality B2C ecommerce companies and suppresses Shopify-linked companies with explicit evidence.

## Stages
1. Candidate discovery
- Use the current active dataset as the broad seed universe.
- Score likely B2C ecommerce rows from metadata, descriptions, and business-status fields.

2. Shopify detection
- Probe shortlisted homepages.
- Detect Shopify from explicit text mentions and storefront-tech fingerprints in HTML or response headers.
- Cache probe responses so reruns stay cheap.

3. Final merge
- Combine discovery and detection outputs.
- Emit a final non-Shopify file with review flags.

## Candidate Rules
- Require active websites.
- Prefer `business_status` in `active` or `likely_active`, medium/high confidence, and non-excluded outreach rows.
- Score up for commerce terms, shopping/storefront phrases, consumer signals, and retail-category terms.
- Score down for B2B tooling, logistics/fulfillment, enterprise software, and adjacent consumer categories like travel or investing.

## Shopify Rules
- High-confidence association:
  - `shopify` or `myshopify` in metadata or final URL
  - HTML fingerprints such as `cdn.shopify.com`, `Shopify.theme`, `Shopify.routes`, `shopify-payment-button`, or `/cdn/shop/`
  - Shopify-specific headers where available
- Preserve checked URL, final URL, HTTP status, error state, and matched signals.

## Outputs
- `data/processed/ecommerce_candidates_latest.csv`
- `data/processed/shopify_detection_latest.csv`
- `data/final/non_shopify_ecommerce_latest.csv`

## Commands
- `python main.py ecommerce build`
- `python main.py ecommerce detect-shopify`
- `python main.py ecommerce finalize`
- `python main.py pipeline ecommerce-refresh`

## Limits
- This does not produce a complete list of every ecommerce company worldwide.
- Some companies will still need manual review if their sites block fetches or hide platform fingerprints.
