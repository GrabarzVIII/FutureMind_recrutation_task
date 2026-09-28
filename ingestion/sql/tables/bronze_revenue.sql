CREATE TABLE IF NOT EXISTS `futuremind-rekru-proj.bronze.revenue` (
  id STRING NOT NULL,
  source_movie_id INT64,
  date DATE NOT NULL,
  title STRING NOT NULL,
  revenue NUMERIC NOT NULL,
  theaters INT64,
  distributor STRING,
  loaded_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  run_id STRING,
  source_file STRING
)
PARTITION BY DATE_TRUNC(date, MONTH)
CLUSTER BY id;
