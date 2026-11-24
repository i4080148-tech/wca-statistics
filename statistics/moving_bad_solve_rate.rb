require_relative "../core/moving_consistency_statistic"

class MovingBadSolveRate < MovingConsistencyStatistic
  ALPHA = 0.96
  MIN_COMPLETED = 25
  RECENT_LIMIT = 150
  BAD_FACTOR = 1.5

  def initialize
    @title = "Moving bad-solve rate"
    @note = <<-NOTE
      How often the given person has had a bad solve recently.
      A bad solve is a DNF or a solve slower than 1.5 × the person's own recent median
      (for someone with a 1.30 median in 2x2 that means anything over 1.95).
      P90 / median compares a slow-but-normal solve (the 90th percentile) to a typical one: 1.20 means the slowest
      1 in 10 solves are at least 20% slower than the median. It breaks ties.
      Exponentially weighted with α = 0.96 per solve (emphasizes the last ~25 solves).
      People with fewer than 25 completed solves are ignored. Lower is better.
    NOTE
    .strip
    @table_header = {
      "Bad-solve rate" => :right, "DNF rate" => :right, "P90 / median" => :right, "Median" => :right, "Person" => :left,
    }
  end

  def event_query(event_id)
    attempts_query(event_id)
  end

  def person_row(event_id, values, person_link)
    summary = Consistency.solve_summary(
      Consistency.recent(values, RECENT_LIMIT),
      alpha: ALPHA, min_completed: MIN_COMPLETED, bad_factor: BAD_FACTOR
    )
    return nil unless summary
    [
      [summary[:bad_rate].round(6), summary[:tail_ratio]],
      [
        Consistency.percent(summary[:bad_rate]),
        Consistency.percent(summary[:dnf_rate]),
        format("%.2f", summary[:tail_ratio]),
        clock(event_id, summary[:median]),
        person_link,
      ],
    ]
  end
end
