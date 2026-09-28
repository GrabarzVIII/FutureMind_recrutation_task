-- Use the earliest revenue row per title; break date ties by the source row ID.
CREATE OR REPLACE PROCEDURE `futuremind-rekru-proj.ops.register_movies`()
BEGIN
  CREATE TEMP TABLE source_movies AS
    SELECT
      FARM_FINGERPRINT(TO_JSON_STRING(STRUCT(
        title AS title,
        date AS first_revenue_date,
        distributor AS first_distributor
      ))) source_movie_id,
      title source_title,
      date first_revenue_date,
      distributor first_distributor
    FROM `futuremind-rekru-proj.bronze.revenue`
    QUALIFY ROW_NUMBER() OVER (PARTITION BY title ORDER BY date, id) = 1;

  -- Check new and existing identities before merging by the numeric key.
  ASSERT NOT EXISTS (
    SELECT source_movie_id
    FROM (
      SELECT source_movie_id, source_title, first_revenue_date, first_distributor
      FROM source_movies
      UNION ALL
      SELECT source_movie_id, source_title, first_revenue_date, first_distributor
      FROM `futuremind-rekru-proj.ops.movie_fetch_control`
    )
    GROUP BY source_movie_id
    HAVING COUNT(DISTINCT TO_JSON_STRING(STRUCT(
      source_title, first_revenue_date, first_distributor
    ))) > 1
  ) AS 'Movie ID hash collision: different source identities share the same ID';

  MERGE `futuremind-rekru-proj.ops.movie_fetch_control` T
  USING source_movies S
    ON T.source_movie_id = S.source_movie_id

  WHEN NOT MATCHED THEN
    INSERT (
      source_movie_id,
      source_title,
      first_revenue_date,
      first_distributor,
      estimated_release_year,
      status,
      attempt_count
    )
    VALUES (
      S.source_movie_id,
      S.source_title,
      S.first_revenue_date,
      S.first_distributor,
      EXTRACT(YEAR FROM S.first_revenue_date),
      'pending',
      0
    )

  WHEN MATCHED
    AND T.status = 'pending'
    AND T.attempt_count = 0
  THEN UPDATE SET
    first_revenue_date = S.first_revenue_date,
    estimated_release_year = EXTRACT(YEAR FROM S.first_revenue_date);
END;
