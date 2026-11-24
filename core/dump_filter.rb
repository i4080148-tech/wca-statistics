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
    each_dump_line do |line|
      if (match = line.match(TABLE_START))
        table = match[1]
        create_lines = []
        columns = nil
        next
      end
      next unless table == "results"
      if columns.nil? && !line.start_with?("INSERT INTO")
        create_lines << line
        next
      end
      next unless line.start_with?("INSERT INTO")
      columns ||= insert_columns(line) || DumpFilter.column_names(create_lines)
      id_index = columns.index("id")
      event_index = columns.index("event_id")
      line.scan(TUPLE) do |tuple|
        next unless @keep_events.any? { |event| tuple.include?(event) }
        values = DumpFilter.fields(tuple)
        ids << values[id_index].to_i if @keep_events.include?(values[event_index])
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
    columns = nil
    index_creations = []

    finish_table = lambda do
      return unless out
      out.write(index_creations.join)
      out.close
      out = nil
    end

    each_dump_line do |line|
      if (match = line.match(TABLE_START))
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

      if line.start_with?("INSERT INTO")
        columns ||= insert_columns(line) || DumpFilter.column_names(create_lines)
        write_filtered_insert(out, line, columns)
      else
        out.write(line)
      end
    end
    finish_table.call
    files
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

  def write_filtered_insert(out, line, columns)
    table = line[/\AINSERT INTO `([^`]+)`/, 1]
    prefix = line[/\AINSERT INTO .*? VALUES\s*/]
    keep =
      case table
      when "results"
        event_index = columns.index("event_id")
        ->(tuple) { @keep_events.any? { |e| tuple.include?(e) } && @keep_events.include?(DumpFilter.fields(tuple)[event_index]) }
      when "result_attempts"
        result_index = columns.index("result_id")
        # Attempt rows are all numbers, so a plain split is enough (and fast).
        ->(tuple) { @kept_result_ids.include?(tuple[1...-1].split(",")[result_index].to_i) }
      end

    if keep.nil?
      out.write(line)
      return
    end

    kept = []
    line.scan(TUPLE) { |tuple| kept << tuple if keep.call(tuple) }
    @row_counts[table] += kept.size
    kept.each_slice(ROWS_PER_INSERT) do |rows|
      out.write(prefix + rows.join(",") + ";\n")
    end
  end
end
