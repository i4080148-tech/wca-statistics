# Run with: ruby test/dump_filter_test.rb
require "minitest/autorun"
require "tmpdir"
require_relative "../core/dump_filter"

class DumpFilterTest < Minitest::Test
  DUMP = <<~'SQL'
    /*!999999\- enable the sandbox mode */
    -- MariaDB dump
    /*!40101 SET NAMES utf8mb4 */;

    --
    -- Table structure for table `persons`
    --

    DROP TABLE IF EXISTS `persons`;
    CREATE TABLE `persons` (
      `wca_id` varchar(10) NOT NULL,
      `sub_id` tinyint NOT NULL,
      `name` varchar(80) DEFAULT NULL,
      KEY `index_persons_on_name` (`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

    LOCK TABLES `persons` WRITE;
    INSERT INTO `persons` VALUES ('2022FRED05',1,'Ian (Cantius), Fredric'),('2009ZEMD01',1,'O\'Brien ''222''');
    UNLOCK TABLES;

    --
    -- Table structure for table `result_attempts`
    --

    DROP TABLE IF EXISTS `result_attempts`;
    CREATE TABLE `result_attempts` (
      `value` int NOT NULL,
      `attempt_number` tinyint NOT NULL,
      `result_id` bigint NOT NULL,
      PRIMARY KEY (`result_id`,`attempt_number`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

    INSERT INTO `result_attempts` VALUES (130,1,1),(108,2,1),(900,1,2),(-1,1,3),(122,2,3);
    INSERT INTO `result_attempts` VALUES (777,1,4);

    --
    -- Table structure for table `results`
    --

    DROP TABLE IF EXISTS `results`;
    CREATE TABLE `results` (
      `id` bigint NOT NULL AUTO_INCREMENT,
      `competition_id` varchar(32) NOT NULL,
      `event_id` varchar(6) NOT NULL,
      `person_id` varchar(10) NOT NULL,
      `person_name` varchar(80) DEFAULT NULL,
      PRIMARY KEY (`id`),
      KEY `results_event` (`event_id`),
      KEY `results_person` (`person_id`,`event_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

    INSERT INTO `results` VALUES (1,'Comp2026','222','2022FRED05','Ian (Cantius), Fredric'),(2,'Comp2026','333','2022FRED05','x'),(3,'Comp222','222','2009ZEMD01','O\'Brien ''222'''),(4,'X','333','2009ZEMD01','has \'222\' in name');

    --
    -- Table structure for table `users`
    --

    CREATE TABLE `users` (
      `id` int NOT NULL
    ) ENGINE=InnoDB;
    INSERT INTO `users` VALUES (1);
  SQL

  def test_keeps_only_2x2_results_and_their_attempts
    Dir.mktmpdir do |dir|
      dump = File.join(dir, "dump.sql")
      File.write(dump, DUMP)
      out = File.join(dir, "tables")
      Dir.mkdir(out)
      filter = DumpFilter.new(dump, required_tables: %w(persons results result_attempts), keep_events: %w(222))
      files = filter.split(out)

      assert_equal %w(persons result_attempts results).sort, files.keys.sort
      assert_equal Set[1, 3], filter.kept_result_ids

      results = File.read(files["results"])
      assert_includes results, "(1,'Comp2026','222'"
      assert_includes results, "(3,'Comp222','222','2009ZEMD01','O\\'Brien ''222''')"
      refute_includes results, "'333'"
      # KEY definitions are moved to CREATE INDEX statements after the data.
      refute_match(/^\s*KEY /, results)
      assert_includes results, "CREATE INDEX `results_event` ON results (`event_id`);"
      assert_includes results, "CREATE INDEX `results_person` ON results (`person_id`,`event_id`);"
      assert_match(/PRIMARY KEY \(`id`\)\n\) ENGINE/, results)
      assert_operator results.index("INSERT INTO"), :<, results.index("CREATE INDEX")

      attempts = File.read(files["result_attempts"])
      assert_includes attempts, "INSERT INTO `result_attempts` VALUES (130,1,1),(108,2,1),(-1,1,3),(122,2,3);"
      refute_includes attempts, "900"
      refute_includes attempts, "777"

      persons = File.read(files["persons"])
      assert_includes persons, "'Ian (Cantius), Fredric'"
      assert_includes persons, "CREATE INDEX `index_persons_on_name` ON persons (`name`);"
      refute_includes persons, "sandbox"
      assert_includes persons, "SET NAMES utf8mb4"
      refute_includes persons, "result_attempts"

      assert_equal 2, filter.row_counts["results"]
      assert_equal 4, filter.row_counts["result_attempts"]
    end
  end
end

# The real WCA dump puts one row per line inside each INSERT statement,
# and result_attempts has id and timestamp columns.
class DumpFilterMultiLineTest < Minitest::Test
  DUMP = <<~'SQL'
    /*M!999999\- enable the sandbox mode */
    /*!40101 SET NAMES utf8mb4 */;
    --
    -- Table structure for table `result_attempts`
    --

    DROP TABLE IF EXISTS `result_attempts`;
    CREATE TABLE `result_attempts` (
      `id` bigint NOT NULL AUTO_INCREMENT,
      `attempt_number` tinyint NOT NULL,
      `created_at` datetime(6) NOT NULL,
      `result_id` bigint NOT NULL,
      `updated_at` datetime(6) NOT NULL,
      `value` int NOT NULL,
      PRIMARY KEY (`id`),
      KEY `index_result_attempts_on_result_id` (`result_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

    LOCK TABLES `result_attempts` WRITE;
    /*!40000 ALTER TABLE `result_attempts` DISABLE KEYS */;
    set autocommit=0;
    INSERT INTO `result_attempts` VALUES (1,1,'2025-05-06 05:21:04.199475',14167,'2025-05-06 05:21:04.199475',1438),
    (2,2,'2025-05-06 05:21:04.199475',14167,'2025-05-06 05:21:04.199475',1500),
    (3,1,'2025-05-06 05:21:04.199475',20001,'2025-05-06 05:21:04.199475',130),
    (4,2,'2025-05-06 05:21:04.199475',20001,'2025-05-06 05:21:04.199475',-1);
    INSERT INTO `result_attempts` VALUES (5,1,'2025-05-06 05:21:04.199475',20002,'2025-05-06 05:21:04.199475',99),
    (6,1,'2025-05-06 05:21:04.199475',14167,'2025-05-06 05:21:04.199475',1600);
    /*!40000 ALTER TABLE `result_attempts` ENABLE KEYS */;
    UNLOCK TABLES;
    commit;

    --
    -- Table structure for table `results`
    --

    DROP TABLE IF EXISTS `results`;
    CREATE TABLE `results` (
      `id` int NOT NULL AUTO_INCREMENT,
      `pos` smallint NOT NULL DEFAULT '0',
      `best` int NOT NULL DEFAULT '0',
      `competition_id` varchar(32) NOT NULL DEFAULT '',
      `person_country_id` varchar(50) DEFAULT NULL,
      `event_id` varchar(6) NOT NULL DEFAULT '',
      `format_id` char(1) NOT NULL DEFAULT '',
      `average` int NOT NULL DEFAULT '0',
      `person_id` varchar(10) NOT NULL DEFAULT '',
      `person_name` varchar(80) DEFAULT NULL,
      PRIMARY KEY (`id`),
      KEY `Results_fk_tournament` (`competition_id`),
      KEY `Results_eventAndAverage` (`event_id`,`average`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

    INSERT INTO `results` VALUES (14167,2128,1968,'LyonOpen2007','Cote d_Ivoire','333','a',15,'2007AMAN01','Etienne, (Jr.)'),
    (20001,1,108,'PNW2026','India','222','a',119,'2022FRED05','Ian Cantius Fredric'),
    (20002,2,99,'PNW2026','USA','222','a',125,'2020ABCD01','O\'Neil ''222'' (x)');
    --
    -- Table structure for table `round_types`
    --
    CREATE TABLE `round_types` (
      `id` varchar(1) NOT NULL
    ) ENGINE=InnoDB;
    INSERT INTO `round_types` VALUES ('1'),
    ('f');
  SQL

  def test_multi_line_inserts
    Dir.mktmpdir do |dir|
      dump = File.join(dir, "dump.sql")
      File.write(dump, DUMP)
      out = File.join(dir, "t")
      Dir.mkdir(out)
      filter = DumpFilter.new(dump, required_tables: %w(results result_attempts round_types), keep_events: %w(222))
      files = filter.split(out)

      assert_equal Set[20001, 20002], filter.kept_result_ids
      assert_equal 2, filter.row_counts["results"]
      assert_equal 3, filter.row_counts["result_attempts"]

      results = File.read(files["results"])
      assert_includes results, "INSERT INTO `results` VALUES (20001,1,108,'PNW2026','India','222'"
      assert_includes results, "'O\\'Neil ''222'' (x)');\n"
      refute_includes results, "LyonOpen2007"
      refute_includes results, "round_types"

      attempts = File.read(files["result_attempts"])
      refute_includes attempts, ",14167,"
      assert_includes attempts, "(3,1,'2025-05-06 05:21:04.199475',20001,'2025-05-06 05:21:04.199475',130),(4,"
      assert_includes attempts, "INSERT INTO `result_attempts` VALUES (5,1,"
      # Every INSERT statement in the output is complete on one line.
      attempts.lines.grep(/INSERT INTO/).each { |l| assert l.rstrip.end_with?(");"), l }
      refute_match(/^\(/, attempts)
      assert_includes attempts, "set autocommit=0;"
      assert_includes attempts, "CREATE INDEX `index_result_attempts_on_result_id` ON result_attempts (`result_id`);"

      round_types = File.read(files["round_types"])
      assert_includes round_types, "INSERT INTO `round_types` VALUES ('1'),\n('f');"
    end
  end
end
