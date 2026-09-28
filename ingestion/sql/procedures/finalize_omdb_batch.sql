-- Atomically store attempts and publish movie/batch status. Repeated finalization is a no-op.
CREATE OR REPLACE PROCEDURE `futuremind-rekru-proj.ops.finalize_omdb_batch`(
  p_batch STRING,
  p_stage STRING
)
BEGIN
  DECLARE expected_count INT64;
  DECLARE uri STRING;

  ASSERT REGEXP_CONTAINS(
    p_stage,
    r'^futuremind-rekru-proj\.staging\.omdb_[A-Za-z0-9_]+$'
  ) AS 'Invalid staging table';

  IF (
    SELECT status
    FROM `futuremind-rekru-proj.ops.omdb_batches`
    WHERE batch_id = p_batch
  ) != 'loaded' THEN
    SET (expected_count, uri) = (
      SELECT AS STRUCT
        requests_used,
        file_uri
      FROM `futuremind-rekru-proj.ops.omdb_batches`
      WHERE batch_id = p_batch
    );

    EXECUTE IMMEDIATE FORMAT(
      'CREATE TEMP TABLE attempts AS SELECT * FROM `%s`',
      p_stage
    );

    ASSERT (
      SELECT
        COUNT(*) = expected_count
        AND COUNT(*) = COUNT(DISTINCT attempt_id)
        AND COUNTIF(batch_id != p_batch) = 0
      FROM attempts
    ) AS 'Batch contents do not match manifest';

    ASSERT (
      SELECT COUNT(*) = 0
      FROM attempts A
      LEFT JOIN `futuremind-rekru-proj.ops.movie_fetch_control` M
        USING (source_movie_id)
      WHERE M.source_movie_id IS NULL
        OR M.active_batch_id IS DISTINCT FROM p_batch
    ) AS 'Unassigned movie';

    ASSERT (
      SELECT COUNT(*) = 0
      FROM (
        SELECT source_movie_id
        FROM attempts
        GROUP BY source_movie_id
        HAVING COUNTIF(is_final) != 1
      )
    ) AS 'Expected one final outcome per processed movie';

    BEGIN TRANSACTION;

    MERGE `futuremind-rekru-proj.bronze.omdb_responses` T
    USING attempts S
      ON T.attempt_id = S.attempt_id
    WHEN NOT MATCHED THEN
      INSERT (
        attempt_id,
        batch_id,
        run_id,
        source_movie_id,
        requested_title,
        requested_year,
        requested_at,
        http_status,
        error_message,
        payload,
        outcome,
        is_final,
        loaded_at,
        source_uri
      )
      VALUES (
        S.attempt_id,
        S.batch_id,
        S.run_id,
        S.source_movie_id,
        S.requested_title,
        S.requested_year,
        S.requested_at,
        S.http_status,
        S.error_message,
        S.payload,
        S.outcome,
        S.is_final,
        CURRENT_TIMESTAMP(),
        uri
      );

    MERGE `futuremind-rekru-proj.ops.movie_fetch_control` T
    USING (
      SELECT
        A.*,
        COUNT(*) OVER (PARTITION BY source_movie_id) batch_attempts
      FROM attempts A
      QUALIFY is_final
    ) S
      ON T.source_movie_id = S.source_movie_id
    WHEN MATCHED THEN UPDATE SET
      status = CASE
        WHEN S.outcome IN ('quota_exceeded', 'configuration_error')
          THEN 'retry_pending'
        ELSE S.outcome
      END,
      attempt_count = T.attempt_count + S.batch_attempts,
      last_requested_year = S.requested_year,
      last_attempt_at = S.requested_at,
      last_attempt_id = S.attempt_id,
      http_status = S.http_status,
      last_error = S.error_message,
      matched_imdb_id = IF(
        S.outcome = 'succeeded',
        JSON_VALUE(S.payload, '$.imdbID'),
        T.matched_imdb_id
      ),
      last_success_at = IF(
        S.outcome = 'succeeded',
        S.requested_at,
        T.last_success_at
      ),
      next_retry_at = CASE
        WHEN S.outcome IN ('quota_exceeded', 'configuration_error')
          THEN TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
        WHEN S.outcome = 'retry_pending'
          THEN TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
        ELSE NULL
      END,
      active_batch_id = NULL,
      claimed_at = NULL;

    -- API quota/configuration errors can stop a batch before all assigned movies are visited.
    UPDATE `futuremind-rekru-proj.ops.movie_fetch_control`
    SET
      status = 'retry_pending',
      active_batch_id = NULL,
      claimed_at = NULL,
      next_retry_at = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
    WHERE active_batch_id = p_batch;

    UPDATE `futuremind-rekru-proj.ops.omdb_batches`
    SET
      status = 'loaded',
      loaded_at = CURRENT_TIMESTAMP(),
      last_error = NULL,
      error_stage = NULL
    WHERE batch_id = p_batch;

    COMMIT TRANSACTION;
  END IF;
END;
