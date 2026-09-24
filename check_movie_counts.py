from pathlib import Path

import pandas as pd

CSV_PATH = "revenues_per_day.csv"


def main() -> None:
    df = pd.read_csv(
        CSV_PATH,
        encoding="utf-8-sig",
    )

    print(f"{df['title'].isna().sum()} NA titles")
    print(f"{df['date'].isna().sum()} NA dates")
    print(f"{df['revenue'].isna().sum()} NA revenues")
    print(f"{df['theaters'].isna().sum()} NA theaters")
    print(f"{df['distributor'].isna().sum()} NA distributors")


    df["date"] = pd.to_datetime(df["date"], format="%Y-%m-%d", errors="raise")

    first_dates = df.groupby("title", as_index=False)["date"].min()
    first_dates["first_year"] = first_dates["date"].dt.year
    first_year_pairs = first_dates[["title", "first_year"]].drop_duplicates()

    print(f"row num: {len(df)}")
    print(f"uniq titles: {df['title'].nunique()}")
    print(f"uniq title-first year: {len(first_year_pairs)}")

if __name__ == "__main__":
    main()
