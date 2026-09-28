CREATE TABLE IF NOT EXISTS `futuremind-rekru-proj.bronze.omdb_responses` (
  attempt_id STRING NOT NULL,
  batch_id STRING NOT NULL,
  run_id STRING NOT NULL,
  source_movie_id INT64 NOT NULL,
  requested_title STRING,
  requested_year INT64,
  requested_at TIMESTAMP,
  http_status INT64,
  error_message STRING,
  payload JSON,
  outcome STRING,
  is_final BOOL,
  loaded_at TIMESTAMP,
  source_uri STRING
)
PARTITION BY DATE(loaded_at)
CLUSTER BY source_movie_id, attempt_id;
