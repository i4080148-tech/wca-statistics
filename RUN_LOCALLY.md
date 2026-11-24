# Running this privately on your Mac (no GitHub)

## One-time setup (Terminal)

1. Install Homebrew if you don't have it: https://brew.sh
2. Install the tools:
   ```
   brew install ruby mysql wget
   brew services start mysql
   ```
3. Close Terminal and open a new one. Then add Homebrew's Ruby to your PATH (Intel Mac):
   ```
   echo 'export PATH="/usr/local/opt/ruby/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
   ruby -v    # should say 4.x, not 2.6
   ```
   (On an Apple Silicon Mac use /opt/homebrew/opt/ruby/bin instead.)
4. In this project folder:
   ```
   cd path/to/wca_statistics-master
   bundle install
   bin/init.rb
   ```
   Homebrew's MySQL uses user `root` with no password, which matches the default `database.yml`.

## First run

```
bin/run_daily.sh
```
This downloads the full WCA database export (several GB once unzipped), so the first run takes a while.
When it finishes, open `site/index.html` in your browser.

## Update every day automatically

```
bin/install_daily_mac.sh          # runs daily at 4:30 AM
bin/install_daily_mac.sh 6 0      # or pick a time, e.g. 6:00 AM
```
If the Mac is asleep at that time, it runs when it wakes. If it's shut down, that day is skipped.
Progress and errors go to `logs/daily.log`.

## Consistency statistics (added)

Three extra pages are built along with the rest:

- **Moving consistency**: coefficient of variation (std. dev. / mean) of recent solves, exponentially weighted (α = 0.96 per solve, about the last 25 solves).
- **Moving bad-solve rate**: weighted share of recent attempts that are DNFs or slower than 1.5 × the person's own recent median, plus DNF rate and P90 / median.
- **Moving average stability**: coefficient of variation of recent round averages, weighted like the Moving average page (α = 0.8).

The math lives in `core/consistency.rb`. Tests that run without MySQL: `ruby test/consistency_test.rb`.
To compute just one of them: `bin/compute.rb statistics/moving_consistency.rb`.
