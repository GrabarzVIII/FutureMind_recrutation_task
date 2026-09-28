-- Read the CSV staging table loaded by Workflows; never modify the staging source.
CREATE OR REPLACE PROCEDURE `futuremind-rekru-proj.ops.merge_revenue_batch`(
  p_run STRING,
  p_source STRING,
  p_source_file STRING
)
BEGIN
  ASSERT REGEXP_CONTAINS(
    p_source,
    r'^futuremind-rekru-proj\.staging\.revenue_[A-Za-z0-9_]+$'
  ) AS 'Invalid source table';

  EXECUTE IMMEDIATE FORMAT(
    """
    CREATE TEMP TABLE input_rows AS
    SELECT
      id,
      date raw_date,
      title,
      revenue raw_revenue,
      theaters raw_theaters,
      distributor
    FROM `%s`
    """,
    p_source
  );

  ASSERT (
    SELECT COUNT(*) > 0
    FROM input_rows
  ) AS 'Source is empty';

  ASSERT (
    SELECT COUNTIF(
      id IS NULL
      OR TRIM(id) = ''
      OR title IS NULL
      OR TRIM(title) = ''
      OR SAFE_CAST(raw_date AS DATE) IS NULL
      OR SAFE_CAST(raw_revenue AS NUMERIC) IS NULL
      OR (
        NULLIF(TRIM(raw_theaters), '') IS NOT NULL
        AND SAFE_CAST(raw_theaters AS INT64) IS NULL
      )
    ) = 0
    FROM input_rows
  ) AS 'Invalid source values';

  ASSERT (
    SELECT COUNT(*) = COUNT(DISTINCT id)
    FROM input_rows
  ) AS 'Duplicate revenue IDs';

  MERGE `futuremind-rekru-proj.bronze.revenue` T
  USING (
    SELECT
      id,
      SAFE_CAST(raw_date AS DATE) date,
      title,
      SAFE_CAST(raw_revenue AS NUMERIC) revenue,
      SAFE_CAST(NULLIF(TRIM(raw_theaters), '') AS INT64) theaters,
      distributor
    FROM input_rows
  ) S
    ON T.id = S.id

  WHEN MATCHED AND (
    T.date IS DISTINCT FROM S.date
    OR T.title IS DISTINCT FROM S.title
    OR T.revenue IS DISTINCT FROM S.revenue
    OR T.theaters IS DISTINCT FROM S.theaters
    OR T.distributor IS DISTINCT FROM S.distributor
  ) THEN UPDATE SET
    date = S.date,
    title = S.title,
    revenue = S.revenue,
    theaters = S.theaters,
    distributor = S.distributor,
    updated_at = CURRENT_TIMESTAMP(),
    run_id = p_run,
    source_file = p_source_file

  WHEN NOT MATCHED THEN
    INSERT (
      id,
      date,
      title,
      revenue,
      theaters,
      distributor,
      loaded_at,
      updated_at,
      run_id,
      source_file
    )
    VALUES (
      S.id,
      S.date,
      S.title,
      S.revenue,
      S.theaters,
      S.distributor,
      CURRENT_TIMESTAMP(),
      CURRENT_TIMESTAMP(),
      p_run,
      p_source_file
    );
END;
