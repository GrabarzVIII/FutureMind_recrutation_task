"""Load CSV directly from GCS into a run-specific BigQuery staging table."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re

import functions_framework
from google.cloud import bigquery

# Project configuration.
PROJECT_ID = "futuremind-rekru-proj"
BQ_LOCATION = "EU"


@functions_framework.http
def load_revenue_csv(request):
    body = request.get_json()
    run_id = body["run_id"]
    if not re.fullmatch(r"[A-Za-z0-9_]{1,60}", run_id):
        return {"error": "Invalid run_id"}, 400

    client = bigquery.Client(project=PROJECT_ID, location=BQ_LOCATION)
    table_id = f"{PROJECT_ID}.staging.revenue_{run_id}"
    schema_path = Path(__file__).with_name("revenue_load.json")
    schema = [bigquery.SchemaField.from_api_repr(field) for field in json.loads(schema_path.read_text())]

    table = bigquery.Table(table_id, schema=schema)
    table.expires = datetime.now(timezone.utc) + timedelta(days=7)
    client.create_table(table, exists_ok=True)
    job = client.load_table_from_uri(
        body["csv_uri"],
        table_id,
        job_config=bigquery.LoadJobConfig(
            schema=schema,
            source_format=bigquery.SourceFormat.CSV,
            skip_leading_rows=1,
            allow_quoted_newlines=True,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        ),
    )
    job.result(timeout=900)
    return {
        "status": "loaded",
        "source_table": table_id,
        "load_job_id": job.job_id,
        "row_count": job.output_rows,
    }
