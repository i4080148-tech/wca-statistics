require_relative "../core/moving_consistency_statistic"

class MovingAverageStability < MovingConsistencyStatistic
  ALPHA = 0.8
  MIN_AVERAGES = 5
  RECENT_LIMIT = 40

  def initialize
    @title = "Moving average stability"
    @note = <<-NOTE
      How much the given person's round averages have been changing from round to round recently.
      CV is the standard deviation of the averages divided by their mean, exponentially weighted with α = 0.8,
      the same weighting as the Moving average statistic (emphasizes the last ~5 averages).
      Low CV means the person gets about the same average every round; high CV means big swings.
      People with fewer than 5 averages are ignored. Lower is more stable.
    NOTE
    .strip
    @table_header = { "CV" => :right, "Std. dev." => :right, "Moving average" => :right, "Person" => :left }
  end

  def event_query(event_id)
    averages_query(event_id)
  end

  def person_row(event_id, values, person_link)
    summary = Consistency.average_summary(
      Consistency.recent(values, RECENT_LIMIT),
      alpha: ALPHA, min_averages: MIN_AVERAGES
    )
    return nil unless summary
    [
      summary[:cv],
      [Consistency.percent(summary[:cv]), clock(event_id, summary[:sd]), clock(event_id, summary[:mean]), person_link],
    ]
  end
end
