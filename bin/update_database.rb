#!/usr/bin/env ruby

# Downloads the WCA developer database dump and imports the tables we need into MySQL.
# Only results for Database::KEEP_EVENTS (2x2) are imported, which keeps memory and disk use small.

require 'tmpdir'
require 'fileutils'
require 'time'
require_relative "helpers"
require_relative "../core/database"
require_relative "../core/dump_filter"

Dir.mktmpdir do |tmp_direcory|
  FileUtils.cd tmp_direcory do
    database_export_url = "https://www.worldcubeassociation.org/wst/wca-developer-database-dump.zip"
    zip_filename = "wca-developer-database-dump.zip"
    filename = "wca-developer-database-dump.sql"
    config = Database::DATABASE_CONFIG
    mysql_with_credentials = "mysql --user=#{config["username"]} --password=#{config["password"]}"
    filter_out_mysql_warning = '2>&1 | grep -v "[Warning] Using a password on the command line interface can be insecure."'

    Helpers.timed_task("Downloading #{database_export_url}") { `wget --quiet #{database_export_url}` }
    Helpers.timed_task("Unzipping #{zip_filename}") do
      `unzip #{zip_filename}`
      File.delete(zip_filename) # Free disk space; only the .sql file is needed from here on.
    end
    raise "Download or unzip failed: #{filename} is missing" unless File.exist?(filename)
    export_timestamp = File.mtime(filename)

    table_files = nil
    Helpers.timed_task("Splitting #{filename} (keeping results for #{Database::KEEP_EVENTS.join(', ')})") do
      Dir.mkdir("tables")
      filter = DumpFilter.new(filename, required_tables: Database::REQUIRED_TABLES, keep_events: Database::KEEP_EVENTS)
      table_files = filter.split("tables")
      puts "  - Kept #{filter.row_counts["results"]} results and #{filter.row_counts["result_attempts"]} attempts"
      # Fail the build loudly instead of publishing empty pages.
      if filter.row_counts["results"] == 0 || filter.row_counts["result_attempts"] == 0
        raise "No #{Database::KEEP_EVENTS.join('/')} results or attempts were kept; the dump format may have changed."
      end
    end
    File.delete(filename) # Free disk space before importing.

    missing = Database::REQUIRED_TABLES - table_files.keys
    raise "Tables missing from the dump: #{missing.join(', ')}" unless missing.empty?

    Helpers.timed_task("Importing tables into #{config["database"]}") do
      `#{mysql_with_credentials} -e "DROP DATABASE IF EXISTS #{config["database"]}" #{filter_out_mysql_warning}`
      `#{mysql_with_credentials} -e "CREATE DATABASE #{config["database"]}" #{filter_out_mysql_warning}`
      Database::REQUIRED_TABLES.each do |table_name|
        puts "  - Importing table #{table_name}"
        output = `#{mysql_with_credentials} #{config["database"]} < #{table_files[table_name]} #{filter_out_mysql_warning}`
        puts output unless output.strip.empty?
      end
      # Custom indices, each on its own so one failing (e.g. already exists) doesn't stop the rest.
      Database::INDICES.each do |sql|
        `#{mysql_with_credentials} #{config["database"]} -e "#{sql}" #{filter_out_mysql_warning}`
      end
    end

    # Store the export timestamp
    store_metadata_sql = "CREATE TABLE wca_statistics_metadata (field varchar(255), value varchar(255)); INSERT INTO wca_statistics_metadata (field, value) VALUES ('export_timestamp', '#{export_timestamp.iso8601}')"
    `#{mysql_with_credentials} #{config["database"]} -e "#{store_metadata_sql}" #{filter_out_mysql_warning}`
  end
end
