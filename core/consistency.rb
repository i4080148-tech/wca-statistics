# Math for the "moving consistency" statistics.
#
# Everything here is plain Ruby with no database access, so it can be tested on its own
# (see bin/test_consistency.rb).
#
# All the measures are exponentially weighted, like the Moving average statistic:
# a value k steps back gets weight alpha**k. Recent results count most.
# With alpha = 0.96 per solve the "memory" is about 1 / (1 - alpha) = 25 solves,
# which matches the ~5 averages the Moving average statistic emphasizes (alpha = 0.8 per average).
module Consistency
  DNF = -1
  DNS = -2
  SKIPPED = 0

  # Weights for values ordered oldest first: the newest value gets weight 1.
  def self.weights(count, alpha)
    (0...count).map { |i| alpha**(count - 1 - i) }
  end

  def self.weighted_mean(values, weights)
    total = weights.sum
    values.zip(weights).sum { |value, weight| value * weight } / total
  end

  # Weighted standard deviation with the "reliability weights" correction
  # (the weighted version of dividing by n - 1), so people with few results aren't flattered.
  def self.weighted_sd(values, weights)
    return nil if values.size < 2
    mean = weighted_mean(values, weights)
    v1 = weights.sum
    v2 = weights.sum { |weight| weight * weight }
    denominator = v1 - v2 / v1
    return nil if denominator <= 0
    variance = values.zip(weights).sum { |value, weight| weight * (value - mean)**2 } / denominator
    Math.sqrt(variance)
  end

  # Weighted quantile (q between 0 and 1): the smallest value at which the
  # cumulative weight reaches q of the total weight.
  def self.weighted_quantile(values, weights, q)
    pairs = values.zip(weights).sort_by(&:first)
    total = weights.sum
    target = q * total
    cumulative = 0.0
    pairs.each do |value, weight|
      cumulative += weight
      return value if cumulative >= target - 1e-12
    end
    pairs.last.first
  end

  # Summary of one person's attempts in one event (attempt values in centiseconds,
  # oldest first, WCA codes: -1 DNF, -2 DNS, 0 skipped).
  #
  # Returns nil when there are fewer than min_completed completed solves.
  def self.solve_summary(attempts, alpha:, min_completed:, bad_factor:)
    attempts = attempts.reject { |value| value == SKIPPED || value == DNS }
    completed_count = attempts.count { |value| value > 0 }
    return nil if completed_count < min_completed

    all_weights = weights(attempts.size, alpha)
    completed = []
    completed_weights = []
    attempts.zip(all_weights).each do |value, weight|
      next unless value > 0
      completed << value
      completed_weights << weight
    end

    mean = weighted_mean(completed, completed_weights)
    sd = weighted_sd(completed, completed_weights)
    return nil if sd.nil?
    median = weighted_quantile(completed, completed_weights, 0.5)
    p90 = weighted_quantile(completed, completed_weights, 0.9)

    # A "bad" attempt is a DNF or a solve slower than bad_factor x the person's own (weighted) median.
    threshold = bad_factor * median
    total_weight = all_weights.sum
    bad_weight = attempts.zip(all_weights).sum { |value, weight| (value == DNF || value > threshold) ? weight : 0 }
    dnf_weight = attempts.zip(all_weights).sum { |value, weight| value == DNF ? weight : 0 }

    {
      mean: mean,
      sd: sd,
      cv: sd / mean,
      median: median,
      p90: p90,
      tail_ratio: p90.to_f / median,
      bad_rate: bad_weight / total_weight,
      dnf_rate: dnf_weight / total_weight,
      completed: completed_count,
    }
  end

  # Summary of one person's round averages in one event (centiseconds, oldest first).
  # DNF averages (-1) and missing averages (0) are ignored, like in the Moving average statistic.
  def self.average_summary(averages, alpha:, min_averages:)
    averages = averages.select { |value| value > 0 }
    return nil if averages.size < min_averages
    w = weights(averages.size, alpha)
    mean = weighted_mean(averages, w)
    sd = weighted_sd(averages, w)
    return nil if sd.nil?
    { mean: mean, sd: sd, cv: sd / mean, count: averages.size }
  end

  # Groups a stream of rows that is sorted by person into one [key, values] pair per person,
  # without holding more than one person's rows in memory.
  # rows yields [person_key, person_link, value].
  def self.each_person(rows)
    current_key = nil
    current_link = nil
    values = []
    rows.each do |key, link, value|
      if key != current_key
        yield current_link, values if current_key
        current_key = key
        current_link = link
        values = []
      end
      values << value
    end
    yield current_link, values if current_key
  end

  # Keeps only the most recent values; older ones have negligible weight
  # (0.96**150 is about 0.002) and dropping them keeps the math fast.
  def self.recent(values, limit)
    values.size > limit ? values.last(limit) : values
  end

  def self.percent(fraction, decimals = 1)
    format("%.#{decimals}f%%", fraction * 100)
  end
end
