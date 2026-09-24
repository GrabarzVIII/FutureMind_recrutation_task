import os
from pprint import pprint

import pandas as pd
import requests
from dotenv import load_dotenv

load_dotenv()
CSV_PATH = "revenues_per_day.csv"

df = pd.read_csv(CSV_PATH)
title = df.iloc[0]["title"]
year = pd.to_datetime(df.loc[df["title"] == title, "date"]).min().year

response = requests.get(
    "https://www.omdbapi.com/",
    params={"apikey": os.getenv("OMDB_API_KEY"), "t": title, "y": year, "type": "movie"},
    timeout=30,
)

print(title, year, response.status_code)
pprint(response.json())
