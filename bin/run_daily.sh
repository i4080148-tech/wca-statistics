#!/bin/bash
# Downloads the latest WCA export, recomputes every statistic and rebuilds site/.
# Run it by hand, or let the daily schedule (bin/install_daily_mac.sh) run it.
set -e
cd "$(dirname "$0")/.."
# Homebrew's Ruby, MySQL and wget (Intel and Apple Silicon paths), ahead of macOS's old system Ruby.
export PATH="/usr/local/opt/ruby/bin:/opt/homebrew/opt/ruby/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
echo "=== Started $(date) ==="
[ -f database.yml ] || bin/init.rb
mkdir -p build
bin/update_database.rb
bin/compute_all.rb
bin/compute_index.rb
bin/to_html.rb
echo "=== Finished $(date) ==="
