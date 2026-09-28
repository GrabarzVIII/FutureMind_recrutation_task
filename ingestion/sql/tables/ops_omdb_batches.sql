CREATE TABLE IF NOT EXISTS `futuremind-rekru-proj.ops.omdb_batches` (
  batch_id STRING NOT NULL,
  run_id STRING NOT NULL,
  file_uri STRING,
  file_name STRING,
  status STRING,
  requests_used INT64,
  reserved_requests INT64,
  stop_requested BOOL,
  created_at TIMESTAMP,
  loaded_at TIMESTAMP,
  load_job_id STRING,
  last_error STRING,
  error_stage STRING
);
