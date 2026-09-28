-- Allocate another batch within the run and UTC-day request budgets.
CREATE OR REPLACE PROCEDURE `futuremind-rekru-proj.ops.claim_omdb_batch`(
  p_run STRING,
  p_batch STRING,
  p_uri STRING,
  p_size INT64,
  p_daily_budget INT64,
  p_run_budget INT64
)
BEGIN
  DECLARE remaining INT64;
  DECLARE movie_limit INT64;

  ASSERT p_size BETWEEN 1 AND 100
    AS 'Batch size must be between 1 and 100';
  ASSERT p_daily_budget BETWEEN 2 AND 1000
    AS 'Daily budget must be between 2 and 1000';

  ASSERT p_run_budget BETWEEN 2 AND 900
    AS 'Run budget must be between 2 and 900';

  BEGIN TRANSACTION;

  IF NOT EXISTS (
    SELECT 1
    FROM `futuremind-rekru-proj.ops.omdb_batches`
    WHERE batch_id = p_batch
  ) THEN
    -- Completed batches use actual request counts; unfinished batches retain reservations.
    SET remaining = LEAST(
      p_daily_budget - (
        SELECT COALESCE(SUM(IF(status = 'loaded', requests_used, reserved_requests)), 0)
        FROM `futuremind-rekru-proj.ops.omdb_batches`
        WHERE DATE(created_at) = CURRENT_DATE()
      ),
      p_run_budget - (
        SELECT COALESCE(SUM(IF(status = 'loaded', requests_used, reserved_requests)), 0)
        FROM `futuremind-rekru-proj.ops.omdb_batches`
        WHERE run_id = p_run
      )
    );
    SET movie_limit = LEAST(p_size, GREATEST(DIV(remaining, 2), 0));

    CREATE TEMP TABLE selected AS
    SELECT source_movie_id
    FROM `futuremind-rekru-proj.ops.movie_fetch_control`
    WHERE status IN ('pending', 'retry_pending')
      AND last_success_at IS NULL
      AND (
        next_retry_at IS NULL
        OR next_retry_at <= CURRENT_TIMESTAMP()
      )
    ORDER BY source_movie_id
    LIMIT movie_limit;

    INSERT `futuremind-rekru-proj.ops.omdb_batches` (
      batch_id,
      run_id,
      file_uri,
      file_name,
      status,
      requests_used,
      reserved_requests,
      stop_requested,
      created_at
    )
    SELECT
      p_batch,
      p_run,
      p_uri,
      REGEXP_EXTRACT(p_uri, r'([^/]+)$'),
      IF(COUNT(*) = 0, 'loaded', 'creating'),
      0,
      COUNT(*) * 2,
      FALSE,
      CURRENT_TIMESTAMP()
    FROM selected;

    UPDATE `futuremind-rekru-proj.ops.movie_fetch_control`
    SET
      status = 'in_progress',
      active_batch_id = p_batch,
      claimed_at = CURRENT_TIMESTAMP()
    WHERE source_movie_id IN (
      SELECT source_movie_id
      FROM selected
    );

  END IF;

  COMMIT TRANSACTION;
END;
