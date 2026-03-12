FROM ruby:3.3-slim

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    libsqlite3-dev \
    pkg-config \
    unzip \
  && rm -rf /var/lib/apt/lists/*

RUN gem install sqlite3 --no-document

CMD ["ruby", "scan_to_db.rb", "--stats"]
