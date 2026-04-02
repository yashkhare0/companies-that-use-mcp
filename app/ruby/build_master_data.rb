#!/usr/bin/env ruby
# build_master_data.rb - Build one outreach-friendly master CSV for the full candidate universe

require 'csv'
require 'fileutils'
require 'json'
require 'set'
require 'sqlite3'
require 'time'
require_relative 'lib/prospecting/paths'

DB_PATH = Prospecting::Paths::DEFAULT_DB_PATH
MASTER_DIR = Prospecting::Paths::MASTER_DIR
FINAL_DIR = Prospecting::Paths::FINAL_DIR
WEBSITE_ACTIVITY_LATEST = File.join(MASTER_DIR, 'website_activity_latest.csv')
WEBSITE_META_LATEST = File.join(MASTER_DIR, 'website_meta_latest.csv')

abort 'Usage: ruby build_master_data.rb RUN_ID metadata.csv output.csv' unless ARGV[0] && ARGV[1] && ARGV[2]

run_id = ARGV[0]
metadata_csv = ARGV[1]
output_csv = ARGV[2]

EU_KEYWORDS = %w[
  austria belgium bulgaria croatia cyprus czech denmark estonia finland france germany
  greece hungary ireland italy latvia lithuania luxembourg malta netherlands poland
  portugal romania slovakia slovenia spain sweden switzerland norway united-kingdom uk england
  scotland wales london berlin munich muenchen hamburg cologne koln köln frankfurt stuttgart
  dusseldorf düsseldorf leipzig bonn karlsruhe aachen potsdam dresden heidelberg paris madrid
  barcelona lisbon stockholm helsinki copenhagen amsterdam vienna wien zurich zürich brussels
  warsaw prague dublin
].freeze

GERMANY_KEYWORDS = %w[
  germany berlin munich muenchen hamburg cologne koln köln frankfurt stuttgart
  dusseldorf düsseldorf leipzig bonn karlsruhe aachen potsdam dresden heidelberg biberach
].freeze

def normalize_text(value)
  value.to_s.downcase.strip
end

def sanitize_value(value)
  value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').strip
end

def truthy_int?(value)
  value.to_i == 1
end

def contains_any?(text, keywords)
  haystack = normalize_text(text)
  keywords.any? { |keyword| haystack.include?(keyword) }
end

def split_tags(value)
  value.to_s.split('|').map(&:strip).reject(&:empty?)
end

def valid_domain?(domain)
  domain.to_s.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\z/i)
end

def source_family(source)
  return 'yc' if source.to_s.start_with?('yc_')
  return 'accelerator' if source.to_s.start_with?('angelpad')
  return 'vc_portfolio' if %w[seedcamp point_nine antler b2venture hv_capital speedinvest project_a htgf].include?(source)

  source.to_s.empty? ? 'unknown' : source
end

def industry_flags(meta)
  tags = split_tags(meta['tags']).map(&:downcase)
  text = [
    tags.join(' '),
    meta['one_liner'],
    meta['description'],
    meta['name']
  ].compact.join(' ').downcase

  {
    'tag_fintech' => (tags.any? { |tag| tag.match?(/fintech|finance|payments|bank|insur|accounting/) } || text.match?(/\b(fintech|payments|banking|bank|insurance|insurtech|cards|payroll|treasury|expense)\b/)) ? 1 : 0,
    'tag_devtools' => (tags.any? { |tag| tag.match?(/developer|dev-tools|devtools|api|sdk/) } || text.match?(/\b(api|developer|sdk|cli|devops|platform engineering|testing|observability)\b/)) ? 1 : 0,
    'tag_security' => (tags.any? { |tag| tag.match?(/security|identity|auth/) } || text.match?(/\b(security|cyber|identity|authentication|auth|fraud|compliance)\b/)) ? 1 : 0,
    'tag_ai' => (tags.any? { |tag| tag.match?(/ai|artificial intelligence|machine learning|data infrastructure|llm/) } || text.match?(/\b(ai|artificial intelligence|machine learning|llm|agent|agents|model)\b/)) ? 1 : 0,
    'tag_data' => (tags.any? { |tag| tag.match?(/data|analytics|insights/) } || text.match?(/\b(data|analytics|insights|warehouse|search)\b/)) ? 1 : 0,
    'tag_infra' => (tags.any? { |tag| tag.match?(/infra|infrastructure|cloud|platform/) } || text.match?(/\b(infrastructure|cloud|platform|deployment|hosting|storage|network)\b/)) ? 1 : 0,
    'tag_hr' => (tags.any? { |tag| tag.match?(/hr|people|recruit|talent|workforce/) } || text.match?(/\b(hr|people ops|recruit|talent|hiring|payroll|workforce)\b/)) ? 1 : 0,
    'tag_productivity' => (tags.any? { |tag| tag.match?(/productivity|workflow|automation|operations/) } || text.match?(/\b(productivity|workflow|automation|ops|operations)\b/)) ? 1 : 0,
    'tag_b2b' => (tags.any? { |tag| tag.match?(/b2b|enterprise|saas/) } || text.match?(/\b(b2b|enterprise|saas)\b/)) ? 1 : 0
  }
end

def build_master_tags(row)
  tags = []
  tags << row['outreach_priority']
  tags << row['scan_status']
  tags << row['source_family']
  tags << row['source']
  tags << row['icp_tier'].to_s.downcase.tr(' ', '_') unless row['icp_tier'].to_s.empty?
  tags << 'germany' if row['tag_germany'].to_i == 1
  tags << 'eu' if row['tag_eu'].to_i == 1
  tags << 'high_profile' if row['tag_high_profile'].to_i == 1
  tags << 'verified_api_no_mcp' if row['tag_outreach_ready'].to_i == 1
  tags << 'already_has_mcp' if row['tag_excluded_mcp'].to_i == 1
  tags << 'website_active' if row['tag_website_active'].to_i == 1
  tags << 'invalid_domain' if row['tag_invalid_domain'].to_i == 1

  %w[
    tag_fintech tag_devtools tag_security tag_ai tag_data tag_infra
    tag_hr tag_productivity tag_b2b
  ].each do |key|
    tags << key.sub('tag_', '') if row[key].to_i == 1
  end

  tags.uniq.join('|')
end

def recommended_segment(row)
  return 'suppress_mcp' if row['tag_excluded_mcp'].to_i == 1
  return 'germany_tier1' if row['tag_outreach_ready'].to_i == 1 && row['tag_germany'].to_i == 1
  return 'eu_tier1' if row['tag_outreach_ready'].to_i == 1 && row['tag_eu'].to_i == 1
  return 'global_tier1' if row['tag_outreach_ready'].to_i == 1
  return 'research_queue' if row['scan_status'] == 'unscanned'

  'review_later'
end

def priority_score(row)
  score = 0
  score += row['icp_score'].to_i
  score += row['signal_score'].to_i
  score += 8 if row['tag_outreach_ready'].to_i == 1
  score += 4 if row['tag_high_profile'].to_i == 1
  score += 4 if row['tag_germany'].to_i == 1
  score += 2 if row['tag_eu'].to_i == 1
  score += 2 if row['tag_website_active'].to_i == 1
  score -= 10 if row['tag_excluded_mcp'].to_i == 1
  score -= 3 if row['scan_status'] == 'unscanned'
  score -= 6 if row['tag_invalid_domain'].to_i == 1
  score
end

metadata = {}
CSV.foreach(metadata_csv, headers: true) do |row|
  metadata[sanitize_value(row['domain'])] = row.to_h.transform_values { |value| sanitize_value(value) }
end

website_checks = {}
if File.exist?(WEBSITE_ACTIVITY_LATEST)
  CSV.foreach(WEBSITE_ACTIVITY_LATEST, headers: true) do |row|
    website_checks[sanitize_value(row['domain'])] = row.to_h.transform_values { |value| sanitize_value(value) }
  end
end

website_meta = {}
if File.exist?(WEBSITE_META_LATEST)
  CSV.foreach(WEBSITE_META_LATEST, headers: true) do |row|
    website_meta[sanitize_value(row['domain'])] = row.to_h.transform_values { |value| sanitize_value(value) }
  end
end

db = SQLite3::Database.new(DB_PATH)
db.results_as_hash = true

run_rows = db.execute(
  'SELECT domain, has_api, has_mcp, outreach_priority, outreach_reason, run_id, source_file, scanned_at FROM scans WHERE run_id = ? ORDER BY domain',
  [run_id]
)

latest_rows = db.execute(
  'SELECT domain, has_api, has_mcp, outreach_priority, outreach_reason, run_id, source_file, scanned_at FROM latest_scans ORDER BY domain'
)

run_scans = {}
run_rows.each { |row| run_scans[row['domain']] = row }
run_scans.transform_keys! { |key| sanitize_value(key) }

latest_scans = {}
latest_rows.each { |row| latest_scans[row['domain']] = row }
latest_scans.transform_keys! { |key| sanitize_value(key) }

FileUtils.mkdir_p(File.dirname(output_csv))
FileUtils.mkdir_p(MASTER_DIR)
FileUtils.mkdir_p(FINAL_DIR)

headers = %w[
  run_id scanned_at domain name source source_family icp_tier icp_score signal_score signal_trust
  tags location batch team_size one_liner description company_url source_url
  has_api has_mcp outreach_priority outreach_reason scan_status source_file
  website_checked_at website_status website_active website_http_code website_scheme website_final_url website_error
  website_meta_checked_at website_title website_meta_description website_og_description
  tag_scanned tag_outreach_ready tag_excluded_mcp tag_needs_review tag_website_active tag_invalid_domain
  tag_high_profile tag_germany tag_eu
  tag_fintech tag_devtools tag_security tag_ai tag_data tag_infra tag_hr tag_productivity tag_b2b
  priority_score recommended_segment master_tags
  sheet_status owner contact_name contact_email linkedin_url first_message_angle notes
]

CSV.open(output_csv, 'w') do |csv|
  csv << headers

  metadata.keys.sort.each do |domain|
    meta = metadata[domain] || {}
    scan = run_scans[domain] || latest_scans[domain] || {}
    website = website_checks[domain] || {}
    website_meta_row = website_meta[domain] || {}
    scan_status =
      if run_scans.key?(domain)
        'scanned_in_run'
      elsif latest_scans.key?(domain)
        'scanned_previous'
      else
        'unscanned'
      end

    location = meta['location'].to_s
    flags = industry_flags(meta)
    invalid_domain = valid_domain?(domain) ? 0 : 1
    row = {
      'run_id' => scan['run_id'] || '',
      'scanned_at' => scan['scanned_at'],
      'domain' => domain,
      'name' => meta['name'],
      'source' => meta['source'],
      'source_family' => source_family(meta['source']),
      'icp_tier' => meta['icp_tier'],
      'icp_score' => meta['icp_score'],
      'signal_score' => meta['signal_score'],
      'signal_trust' => meta['signal_trust'],
      'tags' => meta['tags'],
      'location' => location,
      'batch' => meta['batch'],
      'team_size' => meta['team_size'],
      'one_liner' => meta['one_liner'],
      'description' => meta['description'],
      'company_url' => meta['company_url'],
      'source_url' => meta['source_url'],
      'has_api' => scan['has_api'] || '',
      'has_mcp' => scan['has_mcp'] || '',
      'outreach_priority' => scan['outreach_priority'] || 'unscanned',
      'outreach_reason' => scan['outreach_reason'] || 'Not scanned yet',
      'scan_status' => scan_status,
      'source_file' => scan['source_file'] || '',
      'website_checked_at' => website['checked_at'] || '',
      'website_status' => website['website_status'] || '',
      'website_active' => website['website_active'] || '',
      'website_http_code' => website['http_code'] || '',
      'website_scheme' => website['scheme'] || '',
      'website_final_url' => website['final_url'] || '',
      'website_error' => website['error'] || '',
      'website_meta_checked_at' => website_meta_row['checked_at'] || '',
      'website_title' => website_meta_row['title'] || '',
      'website_meta_description' => website_meta_row['meta_description'] || '',
      'website_og_description' => website_meta_row['og_description'] || '',
      'tag_scanned' => scan_status == 'unscanned' ? 0 : 1,
      'tag_outreach_ready' => (scan['outreach_priority'] == 'high' && truthy_int?(scan['has_api']) && !truthy_int?(scan['has_mcp'])) ? 1 : 0,
      'tag_excluded_mcp' => truthy_int?(scan['has_mcp']) ? 1 : 0,
      'tag_needs_review' => %w[low unscanned].include?(scan['outreach_priority'].to_s) || scan_status == 'unscanned' ? 1 : 0,
      'tag_website_active' => website['website_active'].to_i == 1 ? 1 : 0,
      'tag_invalid_domain' => invalid_domain,
      'tag_high_profile' => meta['icp_tier'] == 'ICP 3' ? 1 : 0,
      'tag_germany' => contains_any?(location, GERMANY_KEYWORDS) ? 1 : 0,
      'tag_eu' => contains_any?(location, EU_KEYWORDS) ? 1 : 0,
      'sheet_status' => '',
      'owner' => '',
      'contact_name' => '',
      'contact_email' => '',
      'linkedin_url' => '',
      'first_message_angle' => '',
      'notes' => ''
    }.merge(flags)

    row['priority_score'] = priority_score(row)
    row['recommended_segment'] = recommended_segment(row)
    row['master_tags'] = build_master_tags(row)
    csv << headers.map { |header| sanitize_value(row[header]) }
  end
end

latest_path = File.join(MASTER_DIR, 'master_data_latest.csv')
FileUtils.cp(output_csv, latest_path)

summary = {
  generated_at: Time.now.utc.iso8601,
  run_id: run_id,
  rows: metadata.size,
  scanned_in_run: run_scans.size,
  scanned_any_time: latest_scans.size,
  website_checks: website_checks.size,
  website_meta: website_meta.size,
  metadata_csv: metadata_csv,
  output_csv: output_csv,
  latest_csv: latest_path
}

File.write(File.join(MASTER_DIR, 'master_data_latest.json'), JSON.pretty_generate(summary))

puts "Built #{metadata.size} rows -> #{output_csv}"
puts "Latest copy -> #{latest_path}"
