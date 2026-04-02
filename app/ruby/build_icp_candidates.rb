#!/usr/bin/env ruby
# build_icp_candidates.rb - Build structured prospect candidates with metadata and ICP hints

require 'cgi'
require 'csv'
require 'fileutils'
require 'json'
require 'net/http'
require 'rbconfig'
require 'set'
require 'time'
require 'uri'
require_relative 'lib/prospecting/paths'

RAW_DIR = Prospecting::Paths::RAW_DIR
RESULTS_DIR = Prospecting::Paths::PROCESSED_DIR
DEFAULT_TOP_FILE = File.join(RAW_DIR, 'top-1m.csv.zip')
DEFAULT_TOP_LIMIT = 100_000
PORTFOLIO_CANDIDATES_CSV = File.join(RESULTS_DIR, 'portfolio_candidates_latest.csv')

YC_SOURCES = [
  { key: 'yc_saas', url: 'https://www.ycombinator.com/companies/industry/SaaS', cache: 'yc_saas.html' },
  { key: 'yc_b2b', url: 'https://www.ycombinator.com/companies/industry/b2b', cache: 'yc_b2b.html' },
  { key: 'yc_fintech', url: 'https://www.ycombinator.com/companies/industry/fintech', cache: 'yc_fintech.html' },
  { key: 'yc_developer_tools', url: 'https://www.ycombinator.com/companies/industry/developer-tools', cache: 'yc_developer_tools.html' },
  { key: 'yc_artificial_intelligence', url: 'https://www.ycombinator.com/companies/industry/artificial-intelligence', cache: 'yc_artificial_intelligence.html' },
  { key: 'yc_security', url: 'https://www.ycombinator.com/companies/industry/security', cache: 'yc_security.html' },
  { key: 'yc_productivity', url: 'https://www.ycombinator.com/companies/industry/productivity', cache: 'yc_productivity.html' },
  { key: 'yc_directory', url: 'https://www.ycombinator.com/companies', cache: 'yc_companies.html' }
].freeze

ANGELPAD_SOURCES = [
  { key: 'angelpad_portfolio', url: 'https://angelpad.com/portfolio/', cache: 'angelpad_portfolio.html' },
  { key: 'angelpad_saas', url: 'https://angelpad.com/b/p-cat/saasf/', cache: 'angelpad_saas.html' }
].freeze

def log(message)
  puts "[#{Time.now.utc.iso8601}] #{message}"
end

def normalize_domain(raw)
  value = raw.to_s.strip
  return nil if value.empty?

  candidate = value.match?(%r{\Ahttps?://}i) ? value : "https://#{value}"
  uri = URI(candidate)
  host = uri.host.to_s.downcase
  host = host.sub(/\Awww\./, '')
  return nil if host.empty?

  host
rescue URI::InvalidURIError
  nil
end

def fetch_cached(url, cache_name)
  FileUtils.mkdir_p(RAW_DIR)
  cache_path = File.join(RAW_DIR, cache_name)
  refresh = ENV['REFRESH_SOURCES'] == '1'

  if !refresh && File.exist?(cache_path)
    return File.binread(cache_path).force_encoding('UTF-8').scrub
  end

  body = Net::HTTP.get(URI(url)).to_s.force_encoding('UTF-8').scrub
  File.binwrite(cache_path, body)
  body
rescue StandardError => e
  return File.binread(cache_path).force_encoding('UTF-8').scrub if File.exist?(cache_path)

  raise e
end

def safe_json_parse(value)
  JSON.parse(value)
rescue JSON::ParserError
  nil
end

def icp_tier_for(candidate)
  team_size = candidate[:team_size].to_i
  tags = Array(candidate[:tags]).map(&:downcase)
  description = [candidate[:one_liner], candidate[:description]].compact.join(' ').downcase

  return 'ICP 1' if team_size.positive? && team_size <= 30
  return 'ICP 2' if team_size > 30 && team_size <= 300
  return 'ICP 3' if team_size > 300
  return 'ICP 2' if tags.any? { |tag| %w[saas b2b developer-tools dev-tools api productivity security].include?(tag) }
  return 'ICP 2' if description.match?(/\b(api|developer|integration|workflow|automation|platform|infrastructure)\b/)

  'ICP 1'
end

def icp_score(candidate)
  score = 0
  score += 5 if candidate[:source].start_with?('yc')
  score += 4 if candidate[:source].start_with?('angelpad')
  score += 4 if %w[seedcamp point_nine antler b2venture hv_capital speedinvest project_a htgf].include?(candidate[:source])
  score += 1 if candidate[:source] == 'curated'

  tags = Array(candidate[:tags]).map(&:downcase)
  description = [candidate[:one_liner], candidate[:description]].compact.join(' ').downcase
  location = candidate[:location].to_s.downcase
  score += 3 if tags.any? { |tag| %w[saas b2b api dev-tools developer-tools fintech security hr-tech sales productivity operations infrastructure].include?(tag) }
  score += 2 if description.match?(/\b(api|developer|integration|workflow|automation|platform|infrastructure|auth|oauth)\b/)
  score += 2 if location.match?(/\b(germany|berlin|munich|muenchen|hamburg|cologne|koln|köln|frankfurt|stuttgart|dusseldorf|düsseldorf)\b/)
  score += 1 if location.match?(/\b(austria|switzerland|zurich|zürich|vienna|wien|amsterdam|netherlands|paris|france|stockholm|sweden|helsinki|finland|copenhagen|denmark|madrid|barcelona|spain|lisbon|portugal|brussels|belgium|warsaw|poland|prague|czech|dublin|ireland|luxembourg|estonia|latvia|lithuania)\b/)

  team_size = candidate[:team_size].to_i
  score += 2 if team_size.positive? && team_size <= 300
  score += 1 if team_size > 300 && team_size <= 2500
  score += 1 if candidate[:domain]

  score
end

def portfolio_candidates_from_csv(path)
  return [] unless File.exist?(path)

  CSV.foreach(path, headers: true).filter_map do |row|
    domain = normalize_domain(row['company_url'] || row['domain'])
    next unless domain

    {
      source: row['source'],
      source_url: row['source_url'] || path,
      name: row['name'],
      domain: domain,
      description: row['description'],
      one_liner: row['one_liner'] || row['description'],
      tags: row['tags'].to_s.split('|').map(&:strip).reject(&:empty?),
      batch: row['stage'] || row['investment_year'],
      team_size: nil,
      location: row['location'],
      company_url: row['company_url'],
      raw_rank: nil
    }
  end
end

def domains_from_top_1m(zip_path, max_rank)
  return [] unless File.exist?(zip_path)

  records = []
  IO.popen(['unzip', '-p', zip_path], err: File::NULL) do |io|
    io.each_line do |line|
      rank_str, domain = line.strip.split(',', 2)
      next unless domain

      rank = rank_str.to_i
      break if max_rank && rank > max_rank

      normalized = normalize_domain(domain)
      next unless normalized

      records << {
        source: 'top_1m',
        source_url: zip_path,
        name: normalized,
        domain: normalized,
        description: nil,
        one_liner: nil,
        tags: [],
        batch: nil,
        team_size: nil,
        location: nil,
        company_url: nil,
        raw_rank: rank
      }
    end
  end
  records
end

def domains_from_build_script
  script = File.join(Prospecting::Paths::ROOT_DIR, 'build_domains.rb')
  return [] unless File.exist?(script)

  IO.popen([RbConfig.ruby, script], err: File::NULL) do |io|
    io.read.split("\n").filter_map do |line|
      normalized = normalize_domain(line)
      next unless normalized

      {
        source: 'curated',
        source_url: script,
        name: normalized,
        domain: normalized,
        description: nil,
        one_liner: nil,
        tags: [],
        batch: nil,
        team_size: nil,
        location: nil,
        company_url: nil,
        raw_rank: nil
      }
    end
  end
end

def yc_candidates(source)
  body = fetch_cached(source[:url], source[:cache])
  match = body.match(/data-page="([^"]+)"/)
  return [] unless match

  data = safe_json_parse(CGI.unescapeHTML(match[1]))
  companies = Array(data.dig('props', 'companies'))

  companies.filter_map do |company|
    domain = normalize_domain(company['website'])
    next unless domain

    {
      source: source[:key],
      source_url: source[:url],
      name: company['name'],
      domain: domain,
      description: company['long_description'],
      one_liner: company['one_liner'],
      tags: Array(company['tags']),
      batch: company['batch_name'],
      team_size: company['team_size'],
      location: company['location'],
      company_url: company['ycdc_company_url'] ? URI.join(source[:url], company['ycdc_company_url']).to_s : source[:url],
      raw_rank: nil
    }
  end
end

def angelpad_candidates(source)
  body = fetch_cached(source[:url], source[:cache])

  pattern = %r{
    class="gw-gopf-col-wrap"[^>]*data-filter="(?<filters>[^"]*)".*?
    <div\s+class="gw-gopf-post-title"><b><a\s+href="(?<href>[^"]+)"[^>]*>(?<name>.*?)</a></b>\s*
    .*?<p>(?<description>.*?)</p>
  }mix

  body.scan(pattern).map do |filters, href, name, description|
    domain = normalize_domain(href)
    next unless domain
    next if domain == 'angelpad.com'

    tags = filters.to_s.split(/\s+/).reject(&:empty?)

    {
      source: source[:key],
      source_url: source[:url],
      name: CGI.unescapeHTML(name.to_s.strip),
      domain: domain,
      description: CGI.unescapeHTML(description.to_s.gsub(/<br\s*\/?>/i, ' ').gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip),
      one_liner: nil,
      tags: tags,
      batch: tags.find { |tag| tag.match?(/\Aap\d+f\z/) },
      team_size: nil,
      location: nil,
      company_url: href,
      raw_rank: nil
    }
  end.compact
end

def enrich_candidates!(candidates)
  candidates.each do |candidate|
    candidate[:icp_tier] = icp_tier_for(candidate)
    candidate[:icp_score] = icp_score(candidate)
  end
end

FileUtils.mkdir_p(RAW_DIR)
FileUtils.mkdir_p(RESULTS_DIR)

timestamp = Time.now.utc.strftime('%Y%m%d_%H%M%S')
output_prefix = ARGV[0] || File.join(RESULTS_DIR, "icp_candidates_#{timestamp}")
top_limit = (ARGV[1] || ENV['TOP_LIMIT'] || DEFAULT_TOP_LIMIT).to_i
top_limit = DEFAULT_TOP_LIMIT if top_limit <= 0

log("Building structured ICP candidates -> #{output_prefix}")

candidates = []
source_counts = {}

top_records = domains_from_top_1m(DEFAULT_TOP_FILE, top_limit)
candidates.concat(top_records)
source_counts['top_1m'] = top_records.size
log("Loaded #{top_records.size} top domains")

curated_records = domains_from_build_script
candidates.concat(curated_records)
source_counts['curated'] = curated_records.size
log("Loaded #{curated_records.size} curated domains")

YC_SOURCES.each do |source|
  begin
    records = yc_candidates(source)
    candidates.concat(records)
    source_counts[source[:key]] = records.size
    log("Loaded #{records.size} companies from #{source[:key]}")
  rescue StandardError => e
    source_counts[source[:key]] = 0
    log("Failed #{source[:key]}: #{e.class} #{e.message}")
  end
end

ANGELPAD_SOURCES.each do |source|
  begin
    records = angelpad_candidates(source)
    candidates.concat(records)
    source_counts[source[:key]] = records.size
    log("Loaded #{records.size} companies from #{source[:key]}")
  rescue StandardError => e
    source_counts[source[:key]] = 0
    log("Failed #{source[:key]}: #{e.class} #{e.message}")
  end
end

portfolio_records = portfolio_candidates_from_csv(PORTFOLIO_CANDIDATES_CSV)
candidates.concat(portfolio_records)
source_counts['portfolio_sources'] = portfolio_records.size
log("Loaded #{portfolio_records.size} portfolio-backed domains")

deduped = {}
candidates.each do |candidate|
  next unless candidate[:domain]

  existing = deduped[candidate[:domain]]
  if existing.nil? || icp_score(candidate) > icp_score(existing)
    deduped[candidate[:domain]] = candidate
  end
end

final_candidates = deduped.values
enrich_candidates!(final_candidates)
final_candidates.sort_by! { |candidate| [-candidate[:icp_score].to_i, candidate[:domain]] }

txt_path = "#{output_prefix}.txt"
csv_path = "#{output_prefix}.csv"
jsonl_path = "#{output_prefix}.jsonl"
summary_path = "#{output_prefix}.json"

File.write(txt_path, final_candidates.map { |candidate| candidate[:domain] }.join("\n") + "\n")

CSV.open(csv_path, 'w') do |csv|
  csv << %w[domain name source icp_tier icp_score tags batch team_size location one_liner description company_url source_url]
  final_candidates.each do |candidate|
    csv << [
      candidate[:domain],
      candidate[:name],
      candidate[:source],
      candidate[:icp_tier],
      candidate[:icp_score],
      Array(candidate[:tags]).join('|'),
      candidate[:batch],
      candidate[:team_size],
      candidate[:location],
      candidate[:one_liner],
      candidate[:description],
      candidate[:company_url],
      candidate[:source_url]
    ]
  end
end

File.open(jsonl_path, 'w') do |io|
  final_candidates.each do |candidate|
    io.puts(candidate.to_json)
  end
end

summary = {
  generated_at: Time.now.utc.iso8601,
  output_prefix: output_prefix,
  top_limit: top_limit,
  total_candidates: final_candidates.size,
  source_counts: source_counts,
  outputs: {
    txt: txt_path,
    csv: csv_path,
    jsonl: jsonl_path
  }
}

File.write(summary_path, JSON.pretty_generate(summary))
log("Structured ICP candidates complete: #{final_candidates.size} unique domains")
