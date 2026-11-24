require_relative "grouped_statistic"
require_relative "events"
require_relative "solve_time"
require_relative "consistency"

# Shared base for the moving consistency statistics. Results are read one event at a time,
# streamed from MySQL sorted by person, so memory use stays small even for 3x3.
class MovingConsistencyStatistic < GroupedStatistic
  # Blindfolded and multi-blind are mostly DNFs, and Fewest Moves results are move counts, not times.
  # Only events whose results are imported (Database::KEEP_EVENTS, i.e. 2x2).
  EVENTS = Events::ALL
    .reject { |event_id, _| %w(333bf 444bf 555bf 333mbf 333mbo 333fm).include?(event_id) }
    .select { |event_id, _| Database::KEEP_EVENTS.include?(event_id) }
  TOP = 500

  # Subclasses return [sort key, table row] for one person, or nil to leave them out.
  def person_row(event_id, values, person_link)
    raise "Must implement #person_row"
  end

  # Subclasses return the SQL selecting [person_id, person_link, value] for one event, sorted by person then time.
  def event_query(event_id)
    raise "Must implement #event_query"
  end

  def query
    nil # Not used: rows are streamed per event in #data.
  end

  def data
    @data ||= begin
      client = Database.client
      ensure_indices(client)
      EVENTS.map do |event_id, event_name|
        rows = client.query(event_query(event_id), stream: true, cache_rows: false, as: :array)
        entries = []
        Consistency.each_person(rows) do |person_link, values|
          entry = person_row(event_id, values, person_link)
          entries << entry if entry
        end
        top = entries.sort_by(&:first).first(TOP).map(&:last)
        [event_name, top]
      end
    end
  end

  def clock(event_id, centiseconds)
    SolveTime.new(event_id, :single, centiseconds.round).clock_format
  end

  private

  # These make the per-event, per-person queries fast. Creating an index that
  # already exists raises an error, which is fine to ignore.
  def ensure_indices(client)
    [
      "CREATE INDEX index_results_on_event_id_person_id ON results (event_id, person_id)",
      "CREATE INDEX index_result_attempts_on_result_id ON result_attempts (result_id)",
    ].each do |sql|
      begin
        client.query(sql)
      rescue Mysql2::Error
        # Index already exists.
      end
    end
  end

  def attempts_query(event_id)
    <<-SQL
      SELECT
        result.person_id,
        CONCAT('[', person.name, '](https://www.worldcubeassociation.org/persons/', person.wca_id, ')') person_link,
        attempt.value
      FROM results result
      JOIN result_attempts attempt ON attempt.result_id = result.id
      JOIN persons person ON person.wca_id = result.person_id AND person.sub_id = 1
      JOIN competitions competition ON competition.id = result.competition_id
      JOIN round_types round_type ON round_type.id = result.round_type_id
      WHERE result.event_id = '#{event_id}'
      ORDER BY result.person_id, competition.start_date, round_type.rank, attempt.attempt_number
    SQL
  end

  def averages_query(event_id)
    <<-SQL
      SELECT
        result.person_id,
        CONCAT('[', person.name, '](https://www.worldcubeassociation.org/persons/', person.wca_id, ')') person_link,
        result.average
      FROM results result
      JOIN persons person ON person.wca_id = result.person_id AND person.sub_id = 1
      JOIN competitions competition ON competition.id = result.competition_id
      JOIN round_types round_type ON round_type.id = result.round_type_id
      WHERE result.event_id = '#{event_id}' AND result.average > 0
      ORDER BY result.person_id, competition.start_date, round_type.rank
    SQL
  end
end
