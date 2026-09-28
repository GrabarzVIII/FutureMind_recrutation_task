"""Fetch the assigned movies and save one NDJSON file per batch."""
from datetime import datetime, timezone
import json
import os
from uuid import uuid4

import functions_framework
import requests
from google.cloud import bigquery, storage

# Project configuration.
PROJECT_ID = "futuremind-rekru-proj"
BQ_LOCATION = "EU"
OMDB_API_KEY = os.getenv("OMDB_API_KEY")


def fetch_movie(movie, api_key, session=None):
    session = session or requests.Session()
    attempts = []
    for year in (movie["estimated_release_year"], movie["estimated_release_year"] - 1):
        row = {
            "attempt_id": str(uuid4()),
            "source_movie_id": movie["source_movie_id"],
            "requested_title": movie["source_title"],
            "requested_year": year,
            "requested_at": datetime.now(timezone.utc).isoformat(),
            "http_status": None, "error_message": None, "payload": None,
            "outcome": "retry_pending", "is_final": True,
        }
        try:
            response = session.get(
                "https://www.omdbapi.com/",
                params={"apikey": api_key, "t": movie["source_title"], "y": year, "type": "movie"},
                timeout=(5, 20),
            )
            row["http_status"] = response.status_code
            try:
                payload = response.json()
            except ValueError:
                payload = None
            if isinstance(payload, dict):
                # Never persist the credential, even if an upstream error echoes it.
                payload = json.loads(json.dumps(payload).replace(api_key, "[REDACTED]"))
                row["payload"] = payload
            else:
                payload = {}
            error = str(payload.get("Error", ""))
            row["error_message"] = error or None
            if response.status_code == 429 or "limit" in error.lower():
                row["outcome"] = "quota_exceeded"
            elif response.status_code in (401, 403) or "api key" in error.lower():
                row["outcome"] = "configuration_error"
            elif response.status_code != 200:
                row["error_message"] = error or f"HTTP {response.status_code}"
            elif payload.get("Response") == "True":
                if payload.get("imdbID") and payload.get("Type") == "movie" and str(payload.get("Year")) == str(year):
                    row["outcome"] = "succeeded"
                else:
                    row["outcome"] = "needs_review"
            elif error.lower().strip() == "movie not found!":
                row["outcome"] = "not_found"
            else:
                row["error_message"] = error or "Invalid OMDb response"
        except requests.RequestException:
            # Exception strings may contain the URL and API key.
            row["error_message"] = "OMDb connection failure or timeout"
        attempts.append(row)
        if row["outcome"] != "not_found":
            break
        if year == movie["estimated_release_year"]:
            row["is_final"] = False
    return attempts


@functions_framework.http
def fetch_omdb(request):
    batch_id = request.get_json()["batch_id"]
    if not OMDB_API_KEY:
        return {"error": "OMDB_API_KEY is empty"}, 500
    bq = bigquery.Client(project=PROJECT_ID, location=BQ_LOCATION)
    parameters = [bigquery.ScalarQueryParameter("batch", "STRING", batch_id)]
    config = bigquery.QueryJobConfig(query_parameters=parameters)

    batch = next(iter(bq.query(
        f"SELECT * FROM `{PROJECT_ID}.ops.omdb_batches` WHERE batch_id=@batch",
        job_config=config,
    ).result()), None)
    if batch is None:
        return {"error": "Batch does not exist"}, 404

    bucket_name, object_name = batch["file_uri"].removeprefix("gs://").split("/", 1)
    blob = storage.Client(project=PROJECT_ID).bucket(bucket_name).blob(object_name)
    if blob.exists():
        rows = [json.loads(line) for line in blob.download_as_text().splitlines() if line.strip()]
    else:
        if batch["status"] != "creating":
            return {"error": "Previously saved batch file is missing"}, 409
        movies = bq.query(f"""
            SELECT source_movie_id, source_title, estimated_release_year
            FROM `{PROJECT_ID}.ops.movie_fetch_control`
            WHERE active_batch_id = @batch
              AND status = 'in_progress'
              AND last_success_at IS NULL
            ORDER BY source_movie_id
        """, job_config=config).result()
        rows = []
        with requests.Session() as session:
            for movie in movies:
                attempts = fetch_movie(movie, OMDB_API_KEY, session)
                for attempt in attempts:
                    attempt.update(batch_id=batch_id, run_id=batch["run_id"])
                rows.extend(attempts)
                if attempts[-1]["outcome"] in ("quota_exceeded", "configuration_error"):
                    break
        if not rows:
            return {"error": "No movies assigned to this batch"}, 409
        blob.upload_from_string(
            "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
            content_type="application/x-ndjson",
            if_generation_match=0,
        )

    stop = any(row["outcome"] in ("quota_exceeded", "configuration_error") for row in rows)
    parameters += [
        bigquery.ScalarQueryParameter("count", "INT64", len(rows)),
        bigquery.ScalarQueryParameter("stop", "BOOL", stop),
    ]
    bq.query(f"""
        UPDATE `{PROJECT_ID}.ops.omdb_batches`
        SET status = 'ready',
            requests_used = @count, stop_requested = @stop
        WHERE batch_id = @batch AND status != 'loaded'
    """, job_config=bigquery.QueryJobConfig(query_parameters=parameters)).result()
    return {
        "batch_id": batch_id,
        "file_uri": batch["file_uri"],
        "file_name": object_name.rsplit("/", 1)[-1],
        "requests_used": len(rows),
        "stop_requested": stop,
    }
