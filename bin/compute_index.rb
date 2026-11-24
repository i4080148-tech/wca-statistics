#!/usr/bin/env ruby

require_relative "../statistics/index"

# Generate statistics index.
puts "Computing statistics index."
build_path = File.expand_path("../build", __dir__)

list = STATISTICS
  .sort_by { |statistics_id, statistic_object| statistic_object.title.gsub(/\d+/) { |number| number.rjust(10, "0") } }
  .map { |statistics_id, statistic_object| "- [#{statistic_object.title}](#{statistics_id})\n" }
  .join

list = "Daily-updated WCA statistics, including moving consistency statistics (Moving consistency, Moving bad-solve rate, Moving average stability). Based on [Jonatan Klosko's WCA statistics](https://github.com/jonatanklosko/wca_statistics) and [Justin Barker's fork](https://github.com/JustinTimeCuber/wca_statistics).\n\n" + list

destination_path = File.join(build_path, "README.md")
File.write(destination_path, list)
puts "File generated at #{destination_path}"
