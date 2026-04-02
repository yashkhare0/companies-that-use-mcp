#!/usr/bin/env ruby
# build_candidate_universe.rb - Build a large candidate universe for prospecting

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

def domains_from_top_1m(zip_path, max_rank = nil)
  return [] unless File.exist?(zip_path)

  domains = []
  IO.popen(['unzip', '-p', zip_path], err: File::NULL) do |io|
    io.each_line do |line|
      rank_str, domain = line.strip.split(',', 2)
      next unless domain

      rank = rank_str.to_i
      break if max_rank && rank > max_rank

      normalized = normalize_domain(domain)
      domains << normalized if normalized
    end
  end
  domains
end

def domains_from_build_script
  script = File.join(Prospecting::Paths::ROOT_DIR, 'build_domains.rb')
  return [] unless File.exist?(script)

  IO.popen([RbConfig.ruby, script], err: File::NULL) do |io|
    io.read.split("\n").map { |line| normalize_domain(line) }.compact
  end
end

def domains_from_yc_saas
  body = Net::HTTP.get(URI('https://www.ycombinator.com/companies/industry/SaaS'))
  FileUtils.mkdir_p(RAW_DIR)
  File.write(File.join(RAW_DIR, 'yc_saas.html'), body)
  match = body.match(/data-page="([^"]+)"/)
  return [] unless match

  data = JSON.parse(CGI.unescapeHTML(match[1]))
  companies = Array(data.dig('props', 'companies'))
  companies.filter_map do |company|
    normalize_domain(company['website'])
  end
end

FileUtils.mkdir_p(RAW_DIR)
FileUtils.mkdir_p(RESULTS_DIR)

output_path = ARGV[0]
max_rank = ARGV[1]&.to_i
output_path ||= File.join(RESULTS_DIR, "universe_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.txt")

log("Building candidate universe -> #{output_path}")

sources = {}

log("Loading top domains from #{DEFAULT_TOP_FILE}")
sources['top_1m'] = domains_from_top_1m(DEFAULT_TOP_FILE, max_rank)
log("Loaded #{sources['top_1m'].size} domains from top-1m")

log('Loading curated seed domains')
sources['curated'] = domains_from_build_script
log("Loaded #{sources['curated'].size} curated domains")

log('Loading YC SaaS domains')
sources['yc_saas'] = domains_from_yc_saas
log("Loaded #{sources['yc_saas'].size} YC SaaS domains")

all_domains = Set.new
sources.each_value { |list| list.each { |domain| all_domains.add(domain) } }

File.write(output_path, all_domains.to_a.sort.join("\n") + "\n")

summary = {
  generated_at: Time.now.utc.iso8601,
  output_path: output_path,
  total_unique_domains: all_domains.size,
  sources: sources.transform_values(&:size)
}

File.write(output_path.sub(/\.txt\z/, '.json'), JSON.pretty_generate(summary))

log("Candidate universe complete: #{all_domains.size} unique domains")
