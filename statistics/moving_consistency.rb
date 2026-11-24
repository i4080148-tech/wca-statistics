require_relative "../core/moving_consistency_statistic"

class MovingConsistency < MovingConsistencyStatistic
  ALPHA = 0.96
  MIN_COMPLETED = 25
  RECENT_LIMIT = 150

  def initialize
    @title = "Moving consistency"
    @note = <<-NOTE
      How consistent the given person has been recently, measured on individual solves.
      CV (coefficient of variation) is the standard deviation divided by the mean, so it compares spread
      fairly between faster and slower people: 10% means a typical solve is about 10% away from the person's own mean.
      Both are exponentially weighted with α = 0.96 per solve, which emphasizes the last ~25 solves
      (about 5 averages, like the Moving average statistic). DNFs are left out of the spread; see Moving bad-solve rate for those.
      People with fewer than 25 completed solves are ignored. Lower is more consistent.
    NOTE
    .strip
    @table_header = { "CV" => :right, "Std. dev." => :right, "Moving mean" => :right, "Person" => :left }
  end

  def event_query(event_id)
    attempts_query(event_id)
  end

  def person_row(event_id, values, person_link)
    summary = Consistency.solve_summary(
      Consistency.recent(values, RECENT_LIMIT),
      alpha: ALPHA, min_completed: MIN_COMPLETED, bad_factor: 1.5
    )
    return nil unless summary
    [
      summary[:cv],
      [Consistency.percent(summary[:cv]), clock(event_id, summary[:sd]), clock(event_id, summary[:mean]), person_link],
    ]
  end
end
