# Run with: ruby test/consistency_test.rb
# Tests the consistency math and the three statistics against fake data, without MySQL.
require "minitest/autorun"

# Stand-ins for MySQL so the statistics can be built without a database.
module Mysql2; class Error < StandardError; end; end
$LOADED_FEATURES << File.expand_path("../core/database.rb", __dir__)
module Database
  class FakeClient
    def initialize(rows_by_event) = @rows_by_event = rows_by_event
    def query(sql, **_options)
      raise Mysql2::Error, "index exists" if sql.start_with?("CREATE INDEX")
      event_id = sql[/event_id = '([^']+)'/, 1]
      @rows_by_event.fetch(event_id, [])
    end
  end
  class << self
    attr_accessor :rows_by_event
    def client = FakeClient.new(rows_by_event)
    def metadata = { "export_timestamp" => "2026-11-23T00:00:00Z" }
  end
end

require_relative "../core/consistency"
require_relative "../statistics/moving_consistency"
require_relative "../statistics/moving_bad_solve_rate"
require_relative "../statistics/moving_average_stability"

class ConsistencyMathTest < Minitest::Test
  def test_equal_weights_match_ordinary_sample_sd
    values = [100, 120, 110, 130, 90]
    sd = Consistency.weighted_sd(values, [1.0] * 5)
    mean = values.sum / 5.0
    expected = Math.sqrt(values.sum { |v| (v - mean)**2 } / 4.0)
    assert_in_delta expected, sd, 1e-9
  end

  def test_recent_values_weigh_more
    w = Consistency.weights(3, 0.5)
    assert_equal [0.25, 0.5, 1.0], w
    assert_operator Consistency.weighted_mean([100, 100, 200], w), :>, 150
  end

  def test_weighted_quantile
    assert_equal 3, Consistency.weighted_quantile([5, 1, 3, 2, 4], [1] * 5, 0.5)
    assert_equal 5, Consistency.weighted_quantile([1, 2, 3, 4, 5], [1] * 5, 0.9)
  end

  def test_solve_summary_counts_dnfs_and_slow_solves_as_bad
    attempts = [130] * 24 + [300, -1] + [130] * 4 # 30 attempts, one 3.00 and one DNF
    s = Consistency.solve_summary(attempts, alpha: 1.0, min_completed: 25, bad_factor: 1.5)
    assert_in_delta 2.0 / 30, s[:bad_rate], 1e-9
    assert_in_delta 1.0 / 30, s[:dnf_rate], 1e-9
    assert_equal 130, s[:median]
    assert_equal 29, s[:completed]
  end

  def test_dns_and_skipped_are_ignored
    attempts = [130] * 25 + [-2, 0, 0]
    s = Consistency.solve_summary(attempts, alpha: 1.0, min_completed: 25, bad_factor: 1.5)
    assert_equal 0.0, s[:bad_rate]
  end

  def test_too_few_solves_gives_nil
    assert_nil Consistency.solve_summary([130] * 24 + [-1], alpha: 0.96, min_completed: 25, bad_factor: 1.5)
    assert_nil Consistency.average_summary([130, 140, -1, 0], alpha: 0.8, min_averages: 5)
  end

  def test_each_person_groups_sorted_stream
    rows = [["a", "A", 1], ["a", "A", 2], ["b", "B", 3]]
    out = []
    Consistency.each_person(rows) { |link, values| out << [link, values] }
    assert_equal [["A", [1, 2]], ["B", [3]]], out
  end
end

class ConsistencyStatisticsTest < Minitest::Test
  def setup
    rng = Random.new(42)
    steady = Array.new(60) { 130 + rng.rand(-8..8) }               # ~1.30, tight
    swingy = Array.new(60) { |i| i % 6 == 0 ? 240 : 115 + rng.rand(-10..10) } # fast but with blowups
    swingy[-3] = -1
    few = [120] * 10                                               # not enough solves
    attempt_rows = steady.map { |v| ["2026STEA01", "[Steady](x)", v] } +
                   swingy.map { |v| ["2026SWIN01", "[Swingy](y)", v] } +
                   few.map { |v| ["2026FEWW01", "[Few](z)", v] }
    Database.rows_by_event = { "222" => attempt_rows }
  end

  def test_moving_consistency_ranks_steady_first
    md = MovingConsistency.new.markdown
    table = md.split("### 2x2x2 Cube").last
    assert_operator table.index("Steady"), :<, table.index("Swingy")
    refute_includes md, "[Few]"
    assert_includes md, "| 1 | "
  end

  def test_bad_solve_rate_flags_swingy
    md = MovingBadSolveRate.new.markdown
    swingy_line = md.lines.find { |l| l.include?("Swingy") }
    steady_line = md.lines.find { |l| l.include?("Steady") }
    assert_match(/\| 0\.0% \| 0\.0% \|/, steady_line)
    refute_match(/\| 0\.0% \|/, swingy_line.split("|")[2])
    puts "\n" + md.split("### 2x2x2 Cube").last
  end

  def test_average_stability_uses_averages_query
    sql = MovingAverageStability.new.event_query("222")
    assert_includes sql, "result.average > 0"
    Database.rows_by_event = { "222" => [130, 128, 135, 129, 131, 127].map { |v| ["P", "[P](p)", v] } }
    md = MovingAverageStability.new.markdown
    assert_includes md, "[P](p)"
    puts md.split("### 2x2x2 Cube").last
  end
end
