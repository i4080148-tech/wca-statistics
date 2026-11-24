# Splits the WCA developer database dump into one SQL file per table, keeping only the
# rows we need, while reading the dump line by line (it is gigabytes in size).
#
# - `results` keeps only rows whose event_id is in keep_events (Database::KEEP_EVENTS).
# - `result_attempts` keeps only attempts that belong to those results.
# - Every other required table is kept whole (they are small).
#
# `result_attempts` comes before `results` in the dump, so the dump is read twice:
# first to collect the ids of the results we keep, then to write the table files.
#
# Plain Ruby with no database access, so it can be tested on its own (test/dump_filter_test.rb).

require "set"

class DumpFilter
  TABLE_START = /-- Table structure for table `(.*?)`/
  # One row inside VALUES (...),(...): strings may contain commas, parentheses and escaped quotes.
  TUPLE = /\((?:[^'()]|'(?:[^'\\]|\\.|'')*')*\)/
  FIELD = /'(?:[^'\\]|\\.|'')*'|[^,]+/
  ROWS_PER_INSERT = 1000

  attr_reader :kept_result_ids, :row_counts

  def initialize(dump_path, required_tables:, keep_events:)
    @dump_path = dump_path
    @required_tables = required_tables
    @keep_events = keep_events.map { |event_id| "'#{event_id}'" }
    @row_counts = Hash.new(0)
  end

  # Returns { table_name => sql_file_path }.
  def split(output_dir)
    @kept_result_ids = collect_result_ids
    write_tables(output_dir)
  end

  private

  def each_dump_line
    File.open(@dump_path, "r") do |file|
      # MariaDB dumps start with a sandbox-mode line MySQL doesn't understand; always skip it.
      first = file.gets
      yield first unless first&.include?("enable the sandbox mode")
      file.each_line { |line| yield line }
    end
  end

  def self.fields(tuple)
    tuple[1...-1].scan(FIELD).map(&:strip)
  end

  def self.column_names(create_table_lines)
    create_table_lines.filter_map { |line| line[/\A\s*`([^`]+)`\s/, 1] }
  end

  # Pass 1: ids of the results for the events we keep.
  def collect_result_ids
    ids = Set.new
    table = nil
    create_lines = []
    columns = nil
    in_insert = false
    each_dump_line do |line|
      if !in_insert && (match = line.match(TABLE_START))
        table = match[1]
        create_lines = []
        columns = nil
        next
      end
      next unless table == "results"
      starts_insert = line.start_with?("INSERT INTO")
      unless in_insert || starts_insert
        create_lines << line if columns.nil?
        next
      end
      if starts_insert
        columns ||= insert_columns(line) || DumpFilter.column_names(create_lines)
        id_index = columns.index("id")
        event_index = columns.index("event_id")
        raise "results table has no id/event_id column (columns: #{columns.join(', ')})" unless id_index && event_index
        @results_id_index = id_index
        @results_event_index = event_index
      end
      # A statement may put all rows on one line or one row per line; it ends at the line ending with ";".
      in_insert = !statement_end?(line)
      rows_part(line).scan(TUPLE) do |tuple|
        next unless @keep_events.any? { |event| tuple.include?(event) }
        values = DumpFilter.fields(tuple)
        ids << values[@results_id_index].to_i if @keep_events.include?(values[@results_event_index])
      end
    end
    ids
  end

  # Pass 2: write one file per required table.
  def write_tables(output_dir)
    header_lines = []
    header_done = false
    files = {}
    out = nil
    table = nil
    create_lines = []
    in_create = false
    in_insert = false
    columns = nil
    index_creations = []
    insert_prefix = nil
    keep = nil
    kept = []

    finish_table = lambda do
      return unless out
      out.write(index_creations.join)
      out.close
      out = nil
    end

    each_dump_line do |line|
      if !in_insert && (match = line.match(TABLE_START))
        header_done = true
        finish_table.call
        table = match[1]
        columns = nil
        create_lines = []
        index_creations = []
        if @required_tables.include?(table)
          path = File.join(output_dir, "#{table}.sql")
          files[table] = path
          out = File.open(path, "w")
          out.write(header_lines.join)
          out.write(line)
        end
        next
      end

      unless header_done
        header_lines << line
        next
      end
      next unless out

      if line.start_with?("CREATE TABLE")
        in_create = true
        create_lines = [line]
        next
      end
      if in_create
        create_lines << line
        if line.start_with?(")")
          in_create = false
          out.write(strip_keys(create_lines.join, index_creations))
        end
        next
      end

      starts_insert = !in_insert && line.start_with?("INSERT INTO")
      if starts_insert
        columns ||= insert_columns(line) || DumpFilter.column_names(create_lines)
        insert_prefix = line[/\AINSERT INTO .*? VALUES\s*/]
        keep = row_filter(table, columns)
        kept = []
      end

      if starts_insert || in_insert
        in_insert = !statement_end?(line)
        if keep.nil?
          out.write(line) # Tables we keep whole are copied as they are.
        else
          rows_part(line).scan(TUPLE) { |tuple| kept << tuple if keep.call(tuple) }
          unless in_insert
            @row_counts[table] += kept.size
            kept.each_slice(ROWS_PER_INSERT) { |rows| out.write(insert_prefix + rows.join(",") + ";\n") }
            kept = []
          end
        end
      else
        out.write(line)
      end
    end
    finish_table.call
    files
  end

  # The part of a line holding rows: everything after VALUES on the statement's first line.
  def rows_part(line)
    line.start_with?("INSERT INTO") ? line.sub(/\AINSERT INTO .*? VALUES\s*/, "") : line
  end

  def statement_end?(line)
    line.rstrip.end_with?(";")
  end

  # Returns a lambda that says whether to keep a row, or nil to keep the whole table.
  def row_filter(table, columns)
    case table
    when "results"
      event_index = columns.index("event_id")
      ->(tuple) { @keep_events.any? { |e| tuple.include?(e) } && @keep_events.include?(DumpFilter.fields(tuple)[event_index]) }
    when "result_attempts"
      result_index = columns.index("result_id")
      raise "result_attempts table has no result_id column (columns: #{columns.join(', ')})" unless result_index
      column_count = columns.size
      lambda do |tuple|
        parts = tuple[1...-1].split(",")
        # Fast path: no commas inside quoted values. Otherwise parse properly.
        parts = DumpFilter.fields(tuple) unless parts.size == column_count
        @kept_result_ids.include?(parts[result_index].to_i)
      end
    end
  end

  # Moves KEY definitions out of CREATE TABLE so indexes are built after the rows are inserted.
  def strip_keys(create_sql, index_creations)
    table_name = create_sql[/CREATE TABLE `([^`]+)`/, 1]
    create_sql.gsub(/,\s*KEY (.\w+.) (\([^)]*\))/m) do
      index_creations << "CREATE INDEX #{$1} ON #{table_name} #{$2};\n"
      ""
    end
  end

  def insert_columns(line)
    list = line[/\AINSERT INTO `[^`]+` \(([^)]*)\) VALUES/, 1]
    list&.scan(/`([^`]+)`/)&.flatten
  end
end
