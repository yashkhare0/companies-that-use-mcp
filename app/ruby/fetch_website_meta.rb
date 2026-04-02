#!/usr/bin/env ruby
# fetch_website_meta.rb - Fetch homepage title and description tags for active domains

require 'csv'
require 'fileutils'
require 'net/http'
require 'openssl'
require 'thread'
require 'time'
require 'uri'
require_relative 'lib/prospecting/paths'

MASTER_DIR = Prospecting::Paths::MASTER_DIR
USER_AGENT = 'Mozilla/5.0 (compatible; drio-prospect-bot/1.0; +https://drio.com)'
DEFAULT_WORKERS = (ENV['WEBSITE_META_WORKERS'] || '30').to_i
OPEN_TIMEOUT = (ENV['WEBSITE_META_OPEN_TIMEOUT'] || '5').to_i
READ_TIMEOUT = (ENV['WEBSITE_META_READ_TIMEOUT'] || '5').to_i
MAX_REDIRECTS = 4
MAX_BYTES = (ENV['WEBSITE_META_MAX_BYTES'] || '262144').to_i

abort 'Usage: ruby fetch_website_meta.rb input.csv output.csv [workers]' unless ARGV[0] && ARGV[1]

input_csv = ARGV[0]
output_csv = ARGV[1]
workers = (ARGV[2] || DEFAULT_WORKERS).to_i
workers = 1 if workers <= 0

def valid_domain?(domain)
  domain.to_s.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\z/i)
end

def decode_html(value)
  return '' if value.nil?

  value
    .to_s
    .encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    .gsub(/<[^>]+>/, ' ')
    .gsub('&amp;', '&')
    .gsub('&quot;', '"')
    .gsub('&#39;', "'")
    .gsub('&apos;', "'")
    .gsub('&lt;', '<')
    .gsub('&gt;', '>')
    .gsub(/\s+/, ' ')
    .strip
end

def sanitize_value(value)
  value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').strip
end

def extract_title(html)
  match = html.match(/<title[^>]*>(.*?)<\/title>/im)
  decode_html(match && match[1])
end

def extract_meta_content(html, matcher)
  match = html.match(matcher)
  decode_html(match && match[1])
end

def fetch_body(uri_str, redirects = 0)
  uri = URI(uri_str)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
  http.open_timeout = OPEN_TIMEOUT
  http.read_timeout = READ_TIMEOUT

  request = Net::HTTP::Get.new(uri)
  request['User-Agent'] = USER_AGENT

  payload = nil
  http.request(request) do |response|
    if response.is_a?(Net::HTTPRedirection) && redirects < MAX_REDIRECTS && response['location']
      return fetch_body(URI.join(uri, response['location']).to_s, redirects + 1)
    end

    body = +''
    response.read_body do |chunk|
      body << chunk
      break if body.bytesize >= MAX_BYTES
    end

    payload = {
      'http_code' => response.code.to_i,
      'final_url' => uri.to_s,
      'body' => body
    }
  end

  payload || {
    'http_code' => '',
    'final_url' => uri.to_s,
    'body' => ''
  }
end

def extract_meta_for_domain(domain)
  return {
    'fetch_status' => 'invalid_domain',
    'http_code' => '',
    'final_url' => '',
    'title' => '',
    'meta_description' => '',
    'og_description' => '',
    'error' => 'Domain format invalid'
  } unless valid_domain?(domain)

  result = fetch_body("https://#{domain}")
  body = result['body'].to_s

  {
    'fetch_status' => result['http_code'].to_i.positive? ? 'ok' : 'empty',
    'http_code' => result['http_code'],
    'final_url' => result['final_url'],
    'title' => extract_title(body),
    'meta_description' => extract_meta_content(body, /<meta[^>]+name=["']description["'][^>]+content=["'](.*?)["'][^>]*>/im),
    'og_description' => extract_meta_content(body, /<meta[^>]+property=["']og:description["'][^>]+content=["'](.*?)["'][^>]*>/im),
    'error' => ''
  }
rescue URI::InvalidURIError => e
  {
    'fetch_status' => 'invalid_url',
    'http_code' => '',
    'final_url' => "https://#{domain}",
    'title' => '',
    'meta_description' => '',
    'og_description' => '',
    'error' => e.message
  }
rescue SocketError => e
  {
    'fetch_status' => 'dns_error',
    'http_code' => '',
    'final_url' => "https://#{domain}",
    'title' => '',
    'meta_description' => '',
    'og_description' => '',
    'error' => e.message
  }
rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
  {
    'fetch_status' => 'timeout',
    'http_code' => '',
    'final_url' => "https://#{domain}",
    'title' => '',
    'meta_description' => '',
    'og_description' => '',
    'error' => e.message
  }
rescue OpenSSL::SSL::SSLError => e
  {
    'fetch_status' => 'ssl_error',
    'http_code' => '',
    'final_url' => "https://#{domain}",
    'title' => '',
    'meta_description' => '',
    'og_description' => '',
    'error' => e.message
  }
rescue StandardError => e
  {
    'fetch_status' => 'connection_error',
    'http_code' => '',
    'final_url' => "https://#{domain}",
    'title' => '',
    'meta_description' => '',
    'og_description' => '',
    'error' => e.message
  }
end

domains = []
CSV.foreach(input_csv, headers: true) do |row|
  next if row['domain'].to_s.strip.empty?
  next if row['website_active'] && row['website_active'].to_i != 1

  domains << row['domain'].strip
end
domains = domains.uniq

FileUtils.mkdir_p(File.dirname(output_csv))
FileUtils.mkdir_p(MASTER_DIR)

queue = Queue.new
domains.each { |domain| queue << domain }
results = Queue.new
mutex = Mutex.new
processed = 0

threads = Array.new(workers) do
  Thread.new do
    loop do
      domain = queue.pop(true) rescue nil
      break unless domain

      meta = extract_meta_for_domain(domain)
      results << meta.merge(
        'domain' => domain,
        'checked_at' => Time.now.utc.iso8601
      )

      mutex.synchronize do
        processed += 1
        puts "[#{Time.now.utc.iso8601}] website-meta progress=#{processed}/#{domains.size}" if (processed % 250).zero? || processed == domains.size
      end
    end
  end
end

threads.each(&:join)

rows = []
rows << results.pop until results.empty?
rows.sort_by! { |row| row['domain'] }

headers = %w[domain checked_at fetch_status http_code final_url title meta_description og_description error]
CSV.open(output_csv, 'w') do |csv|
  csv << headers
  rows.each do |row|
    csv << headers.map { |header| sanitize_value(row[header]) }
  end
end

latest_path = File.join(MASTER_DIR, 'website_meta_latest.csv')
FileUtils.cp(output_csv, latest_path)

puts "Fetched meta for #{rows.size} domains -> #{output_csv}"
puts "Latest copy -> #{latest_path}"
