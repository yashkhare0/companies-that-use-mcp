#!/usr/bin/env ruby
# enrich_business_status.rb - Score whether active companies appear to still be in business

require 'csv'
require 'fileutils'
require 'net/http'
require 'openssl'
require 'thread'
require 'time'
require 'uri'
require_relative 'lib/prospecting/paths'

USER_AGENT = 'Mozilla/5.0 (compatible; drio-prospect-bot/1.0; +https://drio.com)'
DEFAULT_WORKERS = (ENV['BUSINESS_STATUS_WORKERS'] || '24').to_i
OPEN_TIMEOUT = (ENV['BUSINESS_STATUS_OPEN_TIMEOUT'] || '4').to_i
READ_TIMEOUT = (ENV['BUSINESS_STATUS_READ_TIMEOUT'] || '4').to_i
MAX_REDIRECTS = 4
MAX_BODY_BYTES = (ENV['BUSINESS_STATUS_MAX_BODY_BYTES'] || '131072').to_i
LATEST_PATH = File.join(Prospecting::Paths::FINAL_DIR, 'active_data_latest.csv')

abort 'Usage: ruby enrich_business_status.rb input.csv output.csv [workers]' unless ARGV[0] && ARGV[1]

input_csv = ARGV[0]
output_csv = ARGV[1]
workers = (ARGV[2] || DEFAULT_WORKERS).to_i
workers = 1 if workers <= 0

CAREERS_PATHS = %w[/careers /jobs /hiring /company/careers].freeze
CONTENT_PATHS = %w[/blog /news /changelog /updates].freeze
DOCS_PATHS = %w[/docs].freeze
STATUS_PATHS = %w[/status].freeze
APP_PATHS = %w[/app /login].freeze
CAREERS_KEYWORDS = %w[careers career jobs hiring openings join-us].freeze
CONTENT_KEYWORDS = %w[blog news changelog updates release releases].freeze
DOCS_KEYWORDS = %w[documentation developer api reference docs].freeze
STATUS_KEYWORDS = %w[status uptime incident incidents availability].freeze
APP_KEYWORDS = ['sign in', 'sign-in', 'log in', 'login', 'dashboard', 'workspace'].freeze

def sanitize_value(value)
  value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').strip
end

def blank?(value)
  sanitize_value(value).empty?
end

def valid_domain?(domain)
  domain.to_s.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\z/i)
end

def truthy?(value)
  value.to_i == 1
end

def response_active?(code)
  code = code.to_i
  code.positive? && (code < 500 || [401, 403, 405, 429].include?(code))
end

def decode_html(text)
  sanitize_value(text)
    .gsub(/<[^>]+>/, ' ')
    .gsub('&amp;', '&')
    .gsub('&quot;', '"')
    .gsub('&#39;', "'")
    .gsub('&lt;', '<')
    .gsub('&gt;', '>')
    .gsub(/\s+/, ' ')
    .strip
end

def keyword_match?(text, keywords)
  haystack = decode_html(text).downcase
  return false if haystack.empty?

  keywords.any? { |keyword| haystack.include?(keyword) }
end

def url_keyword_match?(url, keywords)
  haystack = sanitize_value(url).downcase
  return false if haystack.empty?

  keywords.any? { |keyword| haystack.include?(keyword.tr(' ', '-')) || haystack.include?(keyword.tr(' ', '')) || haystack.include?(keyword) }
end

def request_uri(uri_str, want_body: false, redirects: 0)
  uri = URI(uri_str)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
  http.open_timeout = OPEN_TIMEOUT
  http.read_timeout = READ_TIMEOUT

  request = want_body ? Net::HTTP::Get.new(uri) : Net::HTTP::Head.new(uri)
  request['User-Agent'] = USER_AGENT

  payload = nil
  http.request(request) do |response|
    if response.code.to_i == 405 && !want_body
      return request_uri(uri_str, want_body: true, redirects: redirects)
    end

    if response.is_a?(Net::HTTPRedirection) && redirects < MAX_REDIRECTS && response['location']
      return request_uri(URI.join(uri, response['location']).to_s, want_body: want_body, redirects: redirects + 1)
    end

    body = +''
    if want_body
      response.read_body do |chunk|
        body << chunk
        break if body.bytesize >= MAX_BODY_BYTES
      end
    end

    payload = {
      active: response_active?(response.code),
      code: response.code.to_i,
      final_url: uri.to_s,
      body: sanitize_value(body)
    }
  end

  payload || { active: false, code: '', final_url: uri_str, body: '' }
rescue StandardError
  { active: false, code: '', final_url: uri_str, body: '' }
end

def build_candidate_urls(domain, base_url, subdomains, paths)
  urls = []

  if valid_domain?(domain)
    subdomains.each do |subdomain|
      urls << "https://#{subdomain}.#{domain}"
    end
  end

  unless blank?(base_url)
    paths.each do |path|
      begin
        urls << URI.join(base_url.end_with?('/') ? base_url : "#{base_url}/", path.sub(%r{\A/}, '')).to_s
      rescue URI::InvalidURIError
        next
      end
    end
  end

  urls.uniq
end

def probe_surface(urls, keywords, require_recent: false)
  urls.each do |url|
    result = request_uri(url, want_body: true)
    next unless result[:active]

    body_match = keyword_match?(result[:body], keywords)
    protected_url_match = [401, 403].include?(result[:code].to_i) && url_keyword_match?(result[:final_url], keywords)
    recent_match = require_recent && recent_content?(result[:body])

    valid = if require_recent
      recent_match || body_match
    else
      body_match || protected_url_match
    end

    return result.merge(url: url) if valid
  end

  nil
end

def recent_content?(text)
  sanitized = sanitize_value(text).downcase
  return false if sanitized.empty?

  sanitized.match?(/\b(2026|2025)\b/) ||
    sanitized.match?(/\b(january|february|march|april|may|june|july|august|september|october|november|december)\b/)
end

def base_site_score(row)
  case row['website_status']
  when 'active' then 3
  when 'redirect', 'blocked' then 2
  when 'client_error' then 1
  else 0
  end
end

def classify_status(score, independent_signals)
  if score >= 9 && independent_signals >= 3
    ['active', independent_signals >= 4 ? 'high' : 'medium']
  elsif score >= 6 && independent_signals >= 2
    ['likely_active', independent_signals >= 3 ? 'high' : 'medium']
  elsif score >= 4
    ['unclear', 'medium']
  elsif score >= 2
    ['likely_inactive', 'low']
  else
    ['inactive', 'low']
  end
end

rows = CSV.read(
  input_csv,
  headers: true,
  liberal_parsing: true,
  encoding: 'bom|utf-8:utf-8'
).map(&:to_h)
queue = Queue.new
rows.each_with_index { |row, index| queue << [index, row.transform_keys(&:to_s)] }

results = Array.new(rows.length)
mutex = Mutex.new
processed = 0

threads = Array.new(workers) do
  Thread.new do
    loop do
      item = queue.pop(true) rescue nil
      break unless item

      index, row = item
      domain = sanitize_value(row['domain'])
      base_url = sanitize_value(row['website_final_url'])

      homepage_signal = truthy?(row['website_active'])
      metadata_signal = !blank?(row['website_title']) || !blank?(row['website_meta_description']) || !blank?(row['website_og_description'])
      product_signal = truthy?(row['has_api']) || truthy?(row['has_mcp'])

      docs_probe = probe_surface(build_candidate_urls(domain, base_url, %w[docs developer], DOCS_PATHS), DOCS_KEYWORDS)
      status_probe = probe_surface(build_candidate_urls(domain, base_url, %w[status], STATUS_PATHS), STATUS_KEYWORDS)
      app_probe = probe_surface(build_candidate_urls(domain, base_url, %w[app], APP_PATHS), APP_KEYWORDS)
      careers_probe = probe_surface(build_candidate_urls(domain, base_url, [], CAREERS_PATHS), CAREERS_KEYWORDS)
      content_probe = probe_surface(build_candidate_urls(domain, base_url, [], CONTENT_PATHS), CONTENT_KEYWORDS, require_recent: true)

      recent_signal = content_probe && recent_content?(content_probe[:body])

      score = 0
      reasons = []
      evidence = []
      independent_signals = 0

      if homepage_signal
        score += base_site_score(row)
        reasons << "site=#{row['website_status']}"
        evidence << base_url unless blank?(base_url)
        independent_signals += 1
      end

      if metadata_signal
        score += 1
        reasons << 'homepage metadata present'
      end

      if product_signal
        score += 3
        reasons << 'public product/API signal present'
        independent_signals += 1
      end

      if docs_probe
        score += 1
        reasons << 'docs/developer surface found'
        evidence << docs_probe[:url]
      end

      if status_probe
        score += 1
        reasons << 'status surface found'
        evidence << status_probe[:url]
      end

      if app_probe
        score += 1
        reasons << 'app/login surface found'
        evidence << app_probe[:url]
      end

      operational_surface = !!(docs_probe || status_probe || app_probe)
      if operational_surface
        independent_signals += 1
      end

      if careers_probe
        score += 2
        reasons << 'careers/jobs surface found'
        evidence << careers_probe[:url]
        independent_signals += 1
      end

      if recent_signal
        score += 2
        reasons << 'recent content signal found'
        evidence << content_probe[:url]
        independent_signals += 1
      elsif content_probe
        score += 1
        reasons << 'content/news surface found'
        evidence << content_probe[:url]
      end

      business_status, confidence = classify_status(score, independent_signals)

      row['business_status_checked_at'] = Time.now.utc.iso8601
      row['business_status_score'] = score
      row['business_status'] = business_status
      row['business_status_confidence'] = confidence
      row['business_status_reason'] = reasons.uniq.join('; ')
      row['business_status_evidence_urls'] = evidence.compact.map { |value| sanitize_value(value) }.reject(&:empty?).uniq.join(' | ')
      row['signal_site_live'] = homepage_signal ? 1 : 0
      row['signal_brand_metadata'] = metadata_signal ? 1 : 0
      row['signal_product_surface'] = product_signal ? 1 : 0
      row['signal_docs_surface'] = docs_probe ? 1 : 0
      row['signal_status_surface'] = status_probe ? 1 : 0
      row['signal_app_surface'] = app_probe ? 1 : 0
      row['signal_hiring_surface'] = careers_probe ? 1 : 0
      row['signal_recent_content'] = recent_signal ? 1 : 0
      row['business_status_signal_count'] = independent_signals

      results[index] = row

      mutex.synchronize do
        processed += 1
        puts "[#{Time.now.utc.iso8601}] business-status progress=#{processed}/#{rows.length}" if (processed % 200).zero? || processed == rows.length
      end
    end
  end
end

threads.each(&:join)

headers = results.first.keys + %w[
  business_status_checked_at business_status_score business_status business_status_confidence
  business_status_reason business_status_evidence_urls signal_site_live signal_brand_metadata
  signal_product_surface signal_docs_surface signal_status_surface signal_app_surface
  signal_hiring_surface signal_recent_content business_status_signal_count
]
headers = headers.uniq

FileUtils.mkdir_p(File.dirname(output_csv))
CSV.open(output_csv, 'w') do |csv|
  csv << headers
  results.each do |row|
    csv << headers.map { |header| sanitize_value(row[header]) }
  end
end

FileUtils.cp(output_csv, LATEST_PATH) if File.expand_path(output_csv) != File.expand_path(LATEST_PATH)

puts "Enriched #{results.length} rows -> #{output_csv}"
