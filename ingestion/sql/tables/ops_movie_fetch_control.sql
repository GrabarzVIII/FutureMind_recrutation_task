CREATE TABLE IF NOT EXISTS `futuremind-rekru-proj.ops.movie_fetch_control` (
  source_movie_id INT64 NOT NULL,
  source_title STRING NOT NULL,
  first_revenue_date DATE,
  first_distributor STRING,
  estimated_release_year INT64,
  last_requested_year INT64,
  matched_imdb_id STRING,
  status STRING,
  attempt_count INT64,
  last_attempt_at TIMESTAMP,
  last_success_at TIMESTAMP,
  http_status INT64,
  last_error STRING,
  next_retry_at TIMESTAMP,
  last_attempt_id STRING,
  active_batch_id STRING,
  claimed_at TIMESTAMP
)
CLUSTER BY status;
