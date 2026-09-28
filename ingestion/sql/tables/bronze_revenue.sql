CREATE TABLE IF NOT EXISTS `futuremind-rekru-proj.bronze.revenue` (
  id STRING NOT NULL,
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
PARTITION BY date
CLUSTER BY id;
