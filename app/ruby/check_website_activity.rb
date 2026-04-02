#!/usr/bin/env ruby
# check_website_activity.rb - Lightweight website availability checks for candidate domains

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
DEFAULT_WORKERS = (ENV['WEBSITE_WORKERS'] || '40').to_i
OPEN_TIMEOUT = (ENV['WEBSITE_OPEN_TIMEOUT'] || '4').to_i
READ_TIMEOUT = (ENV['WEBSITE_READ_TIMEOUT'] || '4').to_i
MAX_REDIRECTS = 4

abort 'Usage: ruby check_website_activity.rb metadata.csv output.csv [workers]' unless ARGV[0] && ARGV[1]

metadata_csv = ARGV[0]
output_csv = ARGV[1]
workers = (ARGV[2] || DEFAULT_WORKERS).to_i
workers = 1 if workers <= 0

def valid_domain?(domain)
  domain.to_s.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+\z/i)
end

def response_status(response)
  code = response.code.to_i
  active = code < 500 || [401, 403, 405, 429].include?(code)
  status =
    case code
    when 200..299 then 'active'
    when 300..399 then 'redirect'
    when 401, 403, 405, 429 then 'blocked'
    when 400..499 then 'client_error'
    when 500..599 then 'server_error'
    else 'unknown'
    end

  [status, active ? 1 : 0]
end

def request_once(uri, method)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == 'https'
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
  http.open_timeout = OPEN_TIMEOUT
  http.read_timeout = READ_TIMEOUT

  request = method == :head ? Net::HTTP::Head.new(uri) : Net::HTTP::Get.new(uri)
  request['User-Agent'] = USER_AGENT

  http.request(request)
end

def probe_uri(uri_str, redirects = 0)
  uri = URI(uri_str)
  response = request_once(uri, :head)
  response = request_once(uri, :get) if response.code.to_i == 405

  if response.is_a?(Net::HTTPRedirection) && redirects < MAX_REDIRECTS
    location = response['location']
    return probe_uri(URI.join(uri, location).to_s, redirects + 1) if location
  end

  status, active = response_status(response)
  {
    'website_status' => status,
    'website_active' => active,
    'http_code' => response.code.to_i,
    'scheme' => uri.scheme,
    'final_url' => uri.to_s,
    'error' => ''
  }
rescue URI::InvalidURIError => e
  {
    'website_status' => 'invalid_url',
    'website_active' => 0,
    'http_code' => '',
    'scheme' => uri&.scheme.to_s,
    'final_url' => uri_str,
    'error' => e.message
  }
rescue SocketError => e
  {
    'website_status' => 'dns_error',
    'website_active' => 0,
    'http_code' => '',
    'scheme' => uri&.scheme.to_s,
    'final_url' => uri_str,
    'error' => e.message
  }
rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
  {
    'website_status' => 'timeout',
    'website_active' => 0,
    'http_code' => '',
    'scheme' => uri&.scheme.to_s,
    'final_url' => uri_str,
    'error' => e.message
  }
rescue OpenSSL::SSL::SSLError => e
  {
    'website_status' => 'ssl_error',
    'website_active' => 0,
    'http_code' => '',
    'scheme' => uri&.scheme.to_s,
    'final_url' => uri_str,
    'error' => e.message
  }
rescue StandardError => e
  {
    'website_status' => 'connection_error',
    'website_active' => 0,
    'http_code' => '',
    'scheme' => uri&.scheme.to_s,
    'final_url' => uri_str,
    'error' => e.message
  }
end

def probe_domain(domain)
  return {
    'website_status' => 'invalid_domain',
    'website_active' => 0,
    'http_code' => '',
    'scheme' => '',
    'final_url' => '',
    'error' => 'Domain format invalid'
  } unless valid_domain?(domain)

  https_result = probe_uri("https://#{domain}")
  return https_result if https_result['website_active'].to_i == 1
  return https_result if %w[redirect blocked client_error].include?(https_result['website_status'])

  http_result = probe_uri("http://#{domain}")
  return http_result if http_result['website_active'].to_i == 1

  https_result
end

domains = []
CSV.foreach(metadata_csv, headers: true) do |row|
  domains << row['domain']
end
domains = domains.compact.map(&:strip).reject(&:empty?).uniq

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

      result = probe_domain(domain)
      results << result.merge(
        'domain' => domain,
        'checked_at' => Time.now.utc.iso8601
      )

      mutex.synchronize do
        processed += 1
        puts "[#{Time.now.utc.iso8601}] website-check progress=#{processed}/#{domains.size}" if (processed % 500).zero? || processed == domains.size
      end
    end
  end
end

threads.each(&:join)

rows = []
rows << results.pop until results.empty?
rows.sort_by! { |row| row['domain'] }

headers = %w[domain checked_at website_status website_active http_code scheme final_url error]
CSV.open(output_csv, 'w') do |csv|
  csv << headers
  rows.each do |row|
    csv << headers.map { |header| row[header] }
  end
end

latest_path = File.join(MASTER_DIR, 'website_activity_latest.csv')
FileUtils.cp(output_csv, latest_path)

puts "Checked #{rows.size} domains -> #{output_csv}"
puts "Latest copy -> #{latest_path}"
