-- =====================================================================
-- Staffing Gap Check: SQLite queries
-- Project: Smart Workforce & Resource Scheduling Optimization
-- Author:  Jihad Kashlan
--
-- Database: data/clean/call_center.db
-- Table:    call_center (loaded from data/clean/call_center_analysis.csv
--           in notebooks/03_sql_queries.ipynb, 9,970 rows, 34 columns)
--
-- Core metric: gap = active_agents - required_fte
--   gap < 0  Understaffed | gap = 0  Matched | gap > 0  Overstaffed
--
-- The 632 rows with zero_staff_flag = 1 have no staffing_status (NULL).
-- They are a rounding artifact (required_fte = 0) and are excluded
-- from the primary analysis with "WHERE staffing_status IS NOT NULL",
-- which leaves 9,338 rows.
--
-- Data is simulated. All results are descriptive, not causal.
-- Not computed in SQL (done in Python, notebooks 02 and 03):
--   margin of error (needs SQRT), median wait time (no MEDIAN in SQLite),
--   Chi-square tests (SciPy).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0. Load check
-- Expected: 9,970 rows | 632 rows without status | 632 flagged rows
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                     AS total_rows,
    SUM(staffing_status IS NULL) AS rows_without_status,
    SUM(zero_staff_flag = 1)     AS zero_staff_rows
FROM call_center;


-- ---------------------------------------------------------------------
-- Q1. How often is there understaffing or overstaffing?
-- Share of rows by staffing status.
-- Expected: Matched 56.8% | Overstaffed 23.3% | Understaffed 19.9%
-- ---------------------------------------------------------------------
SELECT
    staffing_status,
    COUNT(*) AS n_rows,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM call_center
WHERE staffing_status IS NOT NULL
GROUP BY staffing_status
ORDER BY n_rows DESC;


-- ---------------------------------------------------------------------
-- Q2a. Where is it concentrated? Workload size.
-- Mismatch share and average relative gap (mismatched rows only)
-- by workload band. The relative gap is |gap| / required_fte.
-- Expected mismatch: 18.8% | 38.3% | 61.9% | 78.2%
-- Expected relative gap: 50.0% | 26.3% | 16.0% | 13.2%
-- ---------------------------------------------------------------------
SELECT
    workload_band,
    MIN(required_fte) AS min_fte,
    MAX(required_fte) AS max_fte,
    COUNT(*)          AS n_rows,
    ROUND(100.0 * SUM(staffing_status <> 'Matched') / COUNT(*), 1)
        AS mismatch_pct,
    ROUND(AVG(CASE WHEN staffing_status <> 'Matched'
                   THEN 100.0 * ABS(gap) / required_fte
              END), 1)
        AS avg_relative_gap_pct
FROM call_center
WHERE staffing_status IS NOT NULL
GROUP BY workload_band
ORDER BY min_fte;


-- ---------------------------------------------------------------------
-- Q2b. Where is it concentrated? Queue, hour, weekday, site.
-- Understaffed share with N per group (N is shown in Tableau tooltips;
-- groups with fewer than 10 rows are hidden or faded).
-- Expected range of the understaffed share:
--   queue 17.2-22.2% | hour 17.2-23.2% | weekday 18.8-21.3% | site 13.4-31.5%
-- None of these differences is statistically detectable (Chi-square).
-- ---------------------------------------------------------------------

-- By queue (20 groups)
SELECT
    queue_name,
    COUNT(*)                              AS n_rows,
    SUM(staffing_status = 'Understaffed') AS n_understaffed,
    ROUND(100.0 * SUM(staffing_status = 'Understaffed') / COUNT(*), 1)
                                          AS understaffed_pct
FROM call_center
WHERE staffing_status IS NOT NULL
GROUP BY queue_name
ORDER BY queue_name;

-- By hour (24 groups)
SELECT
    hour,
    COUNT(*)                              AS n_rows,
    SUM(staffing_status = 'Understaffed') AS n_understaffed,
    ROUND(100.0 * SUM(staffing_status = 'Understaffed') / COUNT(*), 1)
                                          AS understaffed_pct
FROM call_center
WHERE staffing_status IS NOT NULL
GROUP BY hour
ORDER BY hour;

-- By weekday (7 groups, Monday first)
-- strftime('%w') gives 0 = Sunday ... 6 = Saturday; (+ 6) % 7 makes Monday = 0.
SELECT
    weekday,
    COUNT(*)                              AS n_rows,
    SUM(staffing_status = 'Understaffed') AS n_understaffed,
    ROUND(100.0 * SUM(staffing_status = 'Understaffed') / COUNT(*), 1)
                                          AS understaffed_pct
FROM call_center
WHERE staffing_status IS NOT NULL
GROUP BY weekday
ORDER BY MIN((CAST(strftime('%w', date) AS INTEGER) + 6) % 7);

-- By site (58 groups, small groups: median 172 rows)
SELECT
    site,
    COUNT(*)                              AS n_rows,
    SUM(staffing_status = 'Understaffed') AS n_understaffed,
    ROUND(100.0 * SUM(staffing_status = 'Understaffed') / COUNT(*), 1)
                                          AS understaffed_pct
FROM call_center
WHERE staffing_status IS NOT NULL
GROUP BY site
ORDER BY site;


-- ---------------------------------------------------------------------
-- Q3a. Does understaffing relate to service quality? All rows.
-- Expected abandonment: Understaffed 4.65% | Matched 7.53% | Overstaffed 5.20%
-- Understaffed rows also have the highest volume (352 vs 257 for Matched),
-- and the abandonment rate falls as volume grows: confounding by volume.
-- ---------------------------------------------------------------------
SELECT
    staffing_status,
    COUNT(*)                              AS n_rows,
    ROUND(AVG(abandon_rate_pct), 2)       AS avg_abandon_rate_pct,
    ROUND(AVG(wait_time_avg), 1)          AS mean_wait_s,
    ROUND(AVG(service_level_percent), 2)  AS avg_service_level_pct,
    ROUND(AVG(offered_volume), 0)         AS avg_offered_volume
FROM call_center
WHERE staffing_status IS NOT NULL
GROUP BY staffing_status
ORDER BY CASE staffing_status
             WHEN 'Understaffed' THEN 1
             WHEN 'Matched'      THEN 2
             ELSE 3
         END;


-- ---------------------------------------------------------------------
-- Q3b. Same comparison within the same workload (required_fte level).
-- Only levels with at least 30 rows in every status (2 to 12 FTE, 11 levels).
-- Each level has the same weight. Rounding happens only at the end.
-- Expected difference vs Matched:
--   abandonment   Understaffed -0.01 | Overstaffed +0.11 points
--   service level Understaffed -0.49 | Overstaffed -0.19 points
--   levels with higher service level than Matched: 5 and 4 of 11
-- ---------------------------------------------------------------------
WITH level_status AS (
    SELECT
        required_fte,
        staffing_status,
        COUNT(*)                   AS n_rows,
        AVG(abandon_rate_pct)      AS avg_abandon,
        AVG(service_level_percent) AS avg_service
    FROM call_center
    WHERE staffing_status IS NOT NULL
    GROUP BY required_fte, staffing_status
),
valid_levels AS (
    SELECT required_fte
    FROM level_status
    GROUP BY required_fte
    HAVING COUNT(*) = 3 AND MIN(n_rows) >= 30
),
level_wide AS (
    SELECT
        ls.required_fte,
        MAX(CASE WHEN staffing_status = 'Understaffed' THEN avg_abandon END) AS abandon_under,
        MAX(CASE WHEN staffing_status = 'Matched'      THEN avg_abandon END) AS abandon_matched,
        MAX(CASE WHEN staffing_status = 'Overstaffed'  THEN avg_abandon END) AS abandon_over,
        MAX(CASE WHEN staffing_status = 'Understaffed' THEN avg_service END) AS service_under,
        MAX(CASE WHEN staffing_status = 'Matched'      THEN avg_service END) AS service_matched,
        MAX(CASE WHEN staffing_status = 'Overstaffed'  THEN avg_service END) AS service_over
    FROM level_status AS ls
    JOIN valid_levels AS vl USING (required_fte)
    GROUP BY ls.required_fte
)
SELECT
    'Understaffed vs Matched'                         AS comparison,
    COUNT(*)                                          AS n_levels,
    ROUND(AVG(abandon_under - abandon_matched), 2)    AS abandon_diff_pts,
    ROUND(AVG(service_under - service_matched), 2)    AS service_level_diff_pts,
    SUM(service_under > service_matched)              AS levels_service_higher
FROM level_wide
UNION ALL
SELECT
    'Overstaffed vs Matched',
    COUNT(*),
    ROUND(AVG(abandon_over - abandon_matched), 2),
    ROUND(AVG(service_over - service_matched), 2),
    SUM(service_over > service_matched)
FROM level_wide;
