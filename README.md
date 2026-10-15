# Staffing Gap Check

Capstone project for the WBS Data Analytics bootcamp: Smart Workforce and Resource Scheduling Optimization.

Author: Jihad Kashlan

## Why I did this

Before the bootcamp I worked in workforce management, first in real time and later as a scheduler analyst. In real time I moved agents every day to the queues with a backlog, and I always asked myself the same thing: is this queue short because of bad luck today, or because the schedule is wrong?

If it is a pattern, the scheduler should fix the plan. If it is noise, real time can handle it during the day. This project tries to answer that question with data.

## The idea

One metric, one question.

```
gap = active_agents - required_fte
```

- gap below 0: understaffed
- gap equal to 0: matched
- gap above 0: overstaffed

I ask three questions:

1. How often is there understaffing or overstaffing?
2. Where is it concentrated: queue, site, hour or weekday?
3. Does understaffing relate to service level and abandonment?

## Data

Simulated call center data from Kaggle: `komalkomal7/call-center-workforce-dataset-wfo-aht-kpi` (file `call_center_operations_wfo_dataset.csv`, 10,000 rows, 30 columns).

Real staffing data is almost never public, so I used this dataset. It is complete, but it is not realistic, and the results should be read with that in mind.

Cleaning notes:

- 632 rows have `required_fte = 0` (less than 8 hours of workload). The gap has no useful meaning there, so I removed them from the main analysis. 9,338 rows are left.
- `required_fte` is workload divided by 8 hours. It is not a head count.
- Some queue names look like duplicates (for example `*_CORE_EMAIL_T2` and `*_CORE_EMAIL_TIER2`). I cannot confirm this, so I kept all 20 queue groups as they are.
- The `channel` column does not match the queue names, so I did not use it.

## What I found

- 56.8% of the rows match the plan, 23.3% are overstaffed and 19.9% are understaffed. 94.4% are within one FTE.
- I found no clear pattern by queue, hour, weekday or site. The understaffed share is about 20% almost everywhere. With this sample size, only differences of about 4 points or more could be seen, so I say "not detected", not "random".
- Workload size is the only clear difference. Small workloads (1 to 2 FTE) miss the plan in 19% of the rows, large ones (9 to 15 FTE) in 78%. When a small team misses, the gap is bigger compared to its size: 50% of the plan against 13%. My first idea is that staff come in whole numbers, but I did not test this.
- Understaffed rows have a lower abandonment rate (4.65%) than matched rows (7.53%). This is because they also have more calls. At the same workload the three groups look the same.

## Limits

- The data is simulated. I cannot rule out a pattern in real data.
- All comparisons are descriptive. They show averages, not causes.
- When required FTE is 1, the plan always matches in this data.
- I trust the method more than these exact numbers.

## Project structure

```
data/clean/     cleaned data used for the analysis
notebooks/      01_data_cleaning, 02_gap_analysis, 03_sql_queries
sql/            queries.sql (SQLite)
tableau/        staffing_gap_check.twb
reports/        figures
```

The raw data and the SQLite database are not in the repository (see below).

## How to run it

1. Install Python 3 and the packages in `requirements.txt`.
2. Download the dataset from Kaggle and save it as `data/raw/call_center_operations_wfo_dataset.csv`.
3. Run the notebooks in order: `01_data_cleaning`, `02_gap_analysis`, `03_sql_queries`.
4. Notebook 03 creates `data/clean/call_center.db`. Then you can run `sql/queries.sql` on it.

## Dashboard

Tableau Public: https://public.tableau.com/app/profile/j.k1470/viz/staffing_gap_check/StaffingGapCheck

The dashboard has three parts: how often, where, and service quality. Chart titles say what each chart shows, and small groups are marked so nobody reads a small difference as a pattern.

## Tools

Python (Pandas, NumPy, Matplotlib, Seaborn, SciPy), SQLite, Tableau Public, Git and GitHub.
