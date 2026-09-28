CREATE TABLE IF NOT EXISTS `futuremind-rekru-proj.ops.pipeline_runs` (
  run_id STRING NOT NULL,
  source_table STRING,
  status STRING,
  started_at TIMESTAMP,
  finished_at TIMESTAMP,
  last_error STRING
);
