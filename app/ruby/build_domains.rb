#!/usr/bin/env ruby
# build_domains.rb — Build a comprehensive domain list for scanning
# Combines: Bloomberry MCP list + top SaaS companies + API-first companies
#
# Usage: ruby build_domains.rb > domains_full.txt

require 'net/http'
require 'uri'
require 'json'
require 'set'

domains = Set.new

# =============================================================================
# Source 1: Seed list of well-known SaaS / API / AI companies
# =============================================================================
seed = %w[
  stripe.com cloudflare.com hubspot.com twilio.com sendgrid.com intercom.com
  zendesk.com freshdesk.com notion.com airtable.com linear.app figma.com
  vercel.com netlify.com supabase.com planetscale.com datadog.com sentry.io
  pagerduty.com gitlab.com asana.com monday.com clickup.com calendly.com
  typeform.com mailchimp.com brevo.com postmark.com plaid.com square.com
  shopify.com bigcommerce.com contentful.com sanity.io webflow.com
  zapier.com make.com pipedrive.com salesforce.com zoho.com amplitude.com
  mixpanel.com segment.com posthog.com miro.com canva.com grammarly.com
  deepl.com openai.com anthropic.com cohere.com replicate.com together.ai
  anyscale.com langchain.com pinecone.io weaviate.io qdrant.tech chroma.com
  render.com railway.app fly.io heroku.com digitalocean.com linode.com
  vultr.com hetzner.com auth0.com okta.com clerk.com stytch.com algolia.com
  meilisearch.com slack.com discord.com zoom.us ably.com pusher.com
  novu.co courier.com knocklabs.com livekit.io daily.co stream.io
  brex.com ramp.com mercury.com gusto.com rippling.com deel.com remote.com
  linear.app height.app shortcut.com productboard.com canny.io
  launchdarkly.com split.io statsig.com flagsmith.com
  snyk.io sonarqube.org github.com bitbucket.org
  retool.com appsmith.com tooljet.com budibase.com
  airbyte.com fivetran.com hightouch.com census.com
  snowflake.com databricks.com dbt.com
  grafana.com prometheus.io newrelic.com dynatrace.com
  twitch.tv spotify.com soundcloud.com
  hubspot.com marketo.com pardot.com
  freshworks.com helpscout.com frontapp.com
  docusign.com pandadoc.com hellosign.com
  loom.com vidyard.com wistia.com
  webex.com gotomeeting.com
  trello.com basecamp.com
  ghost.org wordpress.com squarespace.com wix.com
  godaddy.com namecheap.com
  twilio.com vonage.com bandwidth.com
  mapbox.com here.com tomtom.com
  elastic.co splunk.com
  confluent.io rabbitmq.com
  redis.com memcached.org
  mongodb.com cockroachlabs.com
  fauna.com neon.tech turso.tech
  upstash.com
  resend.com loops.so
  cal.com
  dub.co
  trigger.dev inngest.com temporal.io
  unkey.dev
  axiom.co
  tinybird.co
  convex.dev
  clerk.com
  neon.tech
  val.town
  replit.com
  codesandbox.io stackblitz.com
  gitpod.io codespaces.github.com
  circleci.com travisci.com buildkite.com
  terraform.io pulumi.com
  docker.com portainer.io
  hashicorp.com consul.io vault.io nomad.io
  istio.io envoyproxy.io
  tailscale.com zerotier.com
  1password.com bitwarden.com lastpass.com
  crowdstrike.com sentinelone.com
  palantir.com databricks.com
  huggingface.co stability.ai midjourney.com
  perplexity.ai
  jasper.ai copy.ai writesonic.com
  eleven-labs.com descript.com
  runway.com pika.art
  cursor.com codeium.com tabnine.com
  composio.dev
  toolhouse.ai
  e2b.dev
  modal.com
  weights.com
  roboflow.com scale.com labelbox.com
  banana.dev baseten.com
]

seed.each { |d| domains.add(d) }

# =============================================================================
# Source 2: Top Y Combinator companies (API-heavy)
# =============================================================================
yc = %w[
  stripe.com airbnb.com dropbox.com twitch.tv reddit.com instacart.com
  gusto.com zapier.com segment.com algolia.com mixpanel.com mux.com
  deel.com brex.com ramp.com mercury.com newfront.com lattice.com
  rippling.com whatnot.com fivetran.com launchdarkly.com
  ironclad.ai gong.io
  posthog.com cal.com dub.co resend.com trigger.dev loops.so
]

yc.each { |d| domains.add(d) }

# =============================================================================
# Source 3: G2 / Capterra top categories (enterprise SaaS)
# =============================================================================
enterprise = %w[
  servicenow.com workday.com sap.com oracle.com
  netsuite.com sage.com intuit.com freshbooks.com xero.com
  atlassian.com jetbrains.com
  adobe.com autodesk.com
  tableau.com looker.com metabase.com
  zenefits.com bamboohr.com personio.com
  lever.co greenhouse.io ashbyhq.com
  gorgias.com gladly.com kustomer.com
  braze.com iterable.com customer.io
  chameleon.io appcues.com pendo.io
  hotjar.com fullstory.com logrocket.com
  optimizely.com vwo.com
  unbounce.com instapage.com leadpages.com
  intercom.com drift.com qualified.com
  outreach.io salesloft.com apollo.io lemlist.com
  clay.com clearbit.com
  ahrefs.com semrush.com moz.com
  buffer.com hootsuite.com sproutsocial.com
  later.com planoly.com
  beehiiv.com substack.com convertkit.com
]

enterprise.each { |d| domains.add(d) }

# =============================================================================
# Source 4: AI/ML infrastructure and tooling
# =============================================================================
ai_infra = %w[
  wandb.ai neptune.ai mlflow.org
  ray.io anyscale.com
  determined.ai pachyderm.com
  argo.workflows.io kubeflow.org
  feast.dev tecton.ai
  great-expectations.io monte-carlo.io
  hex.tech deepnote.com observable.com
  streamlit.io gradio.app
  bentoml.com seldon.io
  vllm.ai
  groq.com cerebras.ai
  fireworks.ai
  mistral.ai
  abacus.ai
  datarobot.com h2o.ai
  clarifai.com
]

ai_infra.each { |d| domains.add(d) }

# Output
domains.sort.each { |d| puts d }

$stderr.puts "Total unique domains: #{domains.size}"
