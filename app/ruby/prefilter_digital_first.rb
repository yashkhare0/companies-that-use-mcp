#!/usr/bin/env ruby
# prefilter_digital_first.rb - Conservative DNS-first filter for likely digital-first companies

require 'csv'
require 'fileutils'
require 'json'
require 'resolv'
require 'securerandom'
require 'thread'
require 'time'
require_relative 'lib/prospecting/paths'

RESULTS_DIR = Prospecting::Paths::PROCESSED_DIR
LOG_DIR = Prospecting::Paths::LOG_DIR

HIGH_TRUST_SIGNALS = %w[api docs developer developers auth platform console].freeze
MEDIUM_TRUST_SIGNALS = %w[app dashboard].freeze
LOW_TRUST_SIGNALS = %w[status].freeze
SIGNALS = (HIGH_TRUST_SIGNALS + MEDIUM_TRUST_SIGNALS + LOW_TRUST_SIGNALS).freeze
DEFAULT_WORKERS = 50

def resolve_addresses(hostname)
  Resolv.getaddresses(hostname).uniq
rescue StandardError
  []
end

def resolve_signal(domain, signal)
  addresses = resolve_addresses("#{signal}.#{domain}")
  return nil if addresses.empty?

  { signal: signal, addresses: addresses }
end

def wildcard_probe(domain)
  token = "zz-mcp-probe-#{SecureRandom.hex(6)}"
  resolve_addresses("#{token}.#{domain}")
end

def classify_signal_strength(signals)
  names = signals.map { |signal| signal[:signal] }
  high = names & HIGH_TRUST_SIGNALS
  medium = names & MEDIUM_TRUST_SIGNALS
  low = names & LOW_TRUST_SIGNALS

  score = (high.size * 3) + (medium.size * 2) + low.size
  trust =
    if high.any? && score >= 3
      'high'
    elsif high.any? || medium.size >= 2
      'medium'
    else
      'low'
    end

  {
    score: score,
    trust: trust,
    high: high,
    medium: medium,
    low: low
  }
end

def keep_candidate?(wildcard_addresses, classification)
  return false unless wildcard_addresses.empty?
  classification[:trust] == 'high'
end

def log_line(log_io, message)
  line = "[#{Time.now.utc.iso8601}] #{message}"
  puts line
  log_io.puts(line)
  log_io.flush
end

abort 'Usage: ruby prefilter_digital_first.rb domains.txt [workers]' unless ARGV[0] && File.exist?(ARGV[0])

input_path = ARGV[0]
worker_count = (ARGV[1] || ENV['WORKERS'] || DEFAULT_WORKERS).to_i
worker_count = DEFAULT_WORKERS if worker_count <= 0

FileUtils.mkdir_p(RESULTS_DIR)
FileUtils.mkdir_p(LOG_DIR)

timestamp = Time.now.utc.strftime('%Y%m%d_%H%M%S')
txt_output = File.join(RESULTS_DIR, "digital_first_#{timestamp}.txt")
csv_output = File.join(RESULTS_DIR, "digital_first_#{timestamp}.csv")
log_path = File.join(LOG_DIR, "prefilter_#{timestamp}.log")

domains = File.readlines(input_path, chomp: true).map(&:strip).reject(&:empty?).uniq
queue = Queue.new
domains.each { |domain| queue << domain }

results = []
mutex = Mutex.new
processed = 0
kept = 0
wildcard_skipped = 0
weak_signal_skipped = 0

File.open(log_path, 'a') do |log_io|
  log_line(log_io, "Prefilter started: input=#{input_path} domains=#{domains.size} workers=#{worker_count}")

  workers = Array.new(worker_count) do
    Thread.new do
      loop do
        domain = begin
          queue.pop(true)
        rescue ThreadError
          nil
        end
        break unless domain

        wildcard_addresses = wildcard_probe(domain)
        signals = SIGNALS.filter_map { |signal| resolve_signal(domain, signal) }
        classification = classify_signal_strength(signals)
        keep = keep_candidate?(wildcard_addresses, classification)

        row = {
          domain: domain,
          signals: signals.map { |signal| signal[:signal] },
          signal_score: classification[:score],
          signal_trust: classification[:trust],
          wildcard_dns: !wildcard_addresses.empty?,
          wildcard_addresses: wildcard_addresses,
          high_trust_signals: classification[:high],
          medium_trust_signals: classification[:medium],
          low_trust_signals: classification[:low]
        }

        mutex.synchronize do
          processed += 1

          if keep
            kept += 1
            results << row
          elsif row[:wildcard_dns]
            wildcard_skipped += 1
          elsif !row[:signals].empty?
            weak_signal_skipped += 1
          end

          if (processed % 500).zero? || processed == domains.size
            log_line(
              log_io,
              "Progress: processed=#{processed}/#{domains.size} kept=#{kept} wildcard_skipped=#{wildcard_skipped} weak_signal_skipped=#{weak_signal_skipped}"
            )
          end
        end
      end
    end
  end

  workers.each(&:join)

  results.sort_by! { |row| [-row[:signal_score], row[:domain]] }
  File.write(txt_output, results.map { |row| row[:domain] }.join("\n") + "\n")

  CSV.open(csv_output, 'w') do |csv|
    csv << %w[domain signal_score signal_trust signals high_trust_signals medium_trust_signals low_trust_signals wildcard_dns wildcard_addresses]
    results.each do |row|
      csv << [
        row[:domain],
        row[:signal_score],
        row[:signal_trust],
        row[:signals].join('|'),
        row[:high_trust_signals].join('|'),
        row[:medium_trust_signals].join('|'),
        row[:low_trust_signals].join('|'),
        row[:wildcard_dns] ? 1 : 0,
        row[:wildcard_addresses].join('|')
      ]
    end
  end

  summary = {
    generated_at: Time.now.utc.iso8601,
    input_path: input_path,
    output_txt: txt_output,
    output_csv: csv_output,
    total_domains: domains.size,
    kept_domains: kept,
    wildcard_skipped: wildcard_skipped,
    weak_signal_skipped: weak_signal_skipped,
    workers: worker_count,
    signals: {
      high_trust: HIGH_TRUST_SIGNALS,
      medium_trust: MEDIUM_TRUST_SIGNALS,
      low_trust: LOW_TRUST_SIGNALS
    }
  }

  File.write(csv_output.sub(/\.csv\z/, '.json'), JSON.pretty_generate(summary))
  log_line(log_io, "Prefilter complete: kept=#{kept} txt=#{txt_output} csv=#{csv_output}")
end
