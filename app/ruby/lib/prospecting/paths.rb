module Prospecting
  module Paths
    ROOT_DIR = File.expand_path('../../../..', __dir__)
    DATA_DIR = File.join(ROOT_DIR, 'data')
    RAW_DIR = File.join(DATA_DIR, 'raw')
    PROCESSED_DIR = File.join(DATA_DIR, 'processed')
    LOG_DIR = File.join(DATA_DIR, 'logs')
    MASTER_DIR = File.join(DATA_DIR, 'master')
    FINAL_DIR = File.join(DATA_DIR, 'final')
    RESULTS_DIR = File.join(ROOT_DIR, 'results')
    DEFAULT_DB_PATH = ENV['DB_PATH'] || File.join(ROOT_DIR, 'mcp_scans.db')
  end
end

