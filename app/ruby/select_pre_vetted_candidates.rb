#!/usr/bin/env ruby
# select_pre_vetted_candidates.rb - Intersect structured candidates with strict digital-first signals

require 'csv'
require 'fileutils'
require 'json'
require 'time'

abort 'Usage: ruby select_pre_vetted_candidates.rb candidates.csv prefilter.csv output_prefix' unless ARGV[0] && ARGV[1] && ARGV[2]

candidates_path = ARGV[0]
prefilter_path = ARGV[1]
output_prefix = ARGV[2]

allowed_sources = (ENV['ALLOWED_SOURCES'] || 'yc_,seedcamp,point_nine,antler,b2venture,hv_capital,speedinvest,project_a,htgf').split(',').map(&:strip).reject(&:empty?)
min_icp_score = (ENV['MIN_ICP_SCORE'] || '12').to_i
max_team_size = (ENV['MAX_TEAM_SIZE'] || '2500').to_i
source_min_scores = (ENV['SOURCE_MIN_SCORES'] || 'yc_=12,seedcamp=5,point_nine=8,antler=7,b2venture=7,hv_capital=8,speedinvest=7,project_a=7,htgf=7').split(',').filter_map do |entry|
  prefix, score = entry.split('=', 2).map(&:strip)
  next if prefix.to_s.empty? || score.to_s.empty?

  [prefix, score.to_i]
end.to_h

def source_allowed?(source, allowed_sources)
  allowed_sources.any? { |prefix| source.to_s.start_with?(prefix) }
end

def min_score_for(source, fallback, source_min_scores)
  matched = source_min_scores.keys.select { |prefix| source.to_s.start_with?(prefix) }.max_by(&:length)
  matched ? source_min_scores[matched] : fallback
end

FileUtils.mkdir_p(File.dirname(output_prefix))

prefilter_rows = {}
CSV.foreach(prefilter_path, headers: true) do |row|
  prefilter_rows[row['domain']] = row.to_h
end

selected = []
CSV.foreach(candidates_path, headers: true) do |row|
  domain = row['domain']
  next unless prefilter_rows.key?(domain)
  next unless source_allowed?(row['source'], allowed_sources)
  next if row['icp_score'].to_i < min_score_for(row['source'], min_icp_score, source_min_scores)

  team_size = row['team_size'].to_i
  next if team_size.positive? && team_size > max_team_size

  merged = row.to_h.merge(
    'signal_score' => prefilter_rows[domain]['signal_score'],
    'signal_trust' => prefilter_rows[domain]['signal_trust'],
    'signals' => prefilter_rows[domain]['signals']
  )
  selected << merged
end

selected.sort_by! do |row|
  [-row['icp_score'].to_i, -row['signal_score'].to_i, row['domain']]
end

txt_path = "#{output_prefix}.txt"
csv_path = "#{output_prefix}.csv"
json_path = "#{output_prefix}.json"

File.write(txt_path, selected.map { |row| row['domain'] }.join("\n") + "\n")

CSV.open(csv_path, 'w') do |csv|
  csv << %w[domain name source icp_tier icp_score signal_score signal_trust signals tags batch team_size location one_liner description company_url source_url]
  selected.each do |row|
    csv << [
      row['domain'],
      row['name'],
      row['source'],
      row['icp_tier'],
      row['icp_score'],
      row['signal_score'],
      row['signal_trust'],
      row['signals'],
      row['tags'],
      row['batch'],
      row['team_size'],
      row['location'],
      row['one_liner'],
      row['description'],
      row['company_url'],
      row['source_url']
    ]
  end
end

File.write(
  json_path,
  JSON.pretty_generate(
    {
      generated_at: Time.now.utc.iso8601,
      candidates_path: candidates_path,
      prefilter_path: prefilter_path,
      output_prefix: output_prefix,
      selected_candidates: selected.size,
      allowed_sources: allowed_sources,
      min_icp_score: min_icp_score,
      source_min_scores: source_min_scores,
      max_team_size: max_team_size
    }
  )
)

puts "Selected #{selected.size} pre-vetted candidates -> #{output_prefix}"
