-- ============================================================================
-- CORRECTED ORACLE SQL QUERY - Membership Period Calculations
-- ============================================================================
-- 
-- PROBLEM: The original calculation used MONTHS_BETWEEN and ADD_MONTHS which
--          calculated 12-month periods incorrectly. It didn't properly preserve
--          the day/month from valid_from and determine the correct year.
--
-- SOLUTION: Extract day/month from valid_from, determine which annual period
--           the createdOn date falls into, and construct the correct dates.
--
-- LOGIC:
-- 1. Membership periods are annual chunks starting on the same day/month as valid_from
-- 2. For a given createdOn date, find which annual period it falls into
-- 3. Period start = (determined year) + (month from valid_from) + (day from valid_from)
-- 4. Period end = Period start + 1 year - 1 day (capped at effective_to)
--
-- EXAMPLE:
--   valid_from = 2020-03-15
--   createdOn = 2021-06-10
--   → Period start = 2021-03-15 (createdOn falls in the 2021-2022 period)
--   → Period end = 2022-03-14
--
--   valid_from = 2020-03-15
--   createdOn = 2021-02-20
--   → Period start = 2020-03-15 (createdOn falls in the 2020-2021 period)
--   → Period end = 2021-03-14
-- ============================================================================

-- CORRECTED Membership_ValidFrom calculation:
-- This finds the start of the annual period that contains createdOn
CASE
  WHEN mm.MEMBERSHIP_ID IS NOT NULL
       AND iui.CREATED_ON BETWEEN me.valid_from AND me.effective_to
  THEN 
    -- Construct date using createdOn's year + valid_from's month/day
    -- If that date is <= createdOn, it's the period start
    -- Otherwise, use previous year
    CASE
      WHEN TO_DATE(
             TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON), 'FM9999') || '-' ||
             TO_CHAR(EXTRACT(MONTH FROM me.valid_from), 'FM00') || '-' ||
             TO_CHAR(EXTRACT(DAY FROM me.valid_from), 'FM00'),
             'YYYY-MM-DD'
           ) <= iui.CREATED_ON
      THEN TO_DATE(
             TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON), 'FM9999') || '-' ||
             TO_CHAR(EXTRACT(MONTH FROM me.valid_from), 'FM00') || '-' ||
             TO_CHAR(EXTRACT(DAY FROM me.valid_from), 'FM00'),
             'YYYY-MM-DD'
           )
      ELSE TO_DATE(
             TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON) - 1, 'FM9999') || '-' ||
             TO_CHAR(EXTRACT(MONTH FROM me.valid_from), 'FM00') || '-' ||
             TO_CHAR(EXTRACT(DAY FROM me.valid_from), 'FM00'),
             'YYYY-MM-DD'
           )
    END
END AS "Membership_ValidFrom",

-- CORRECTED Membership_Period_End calculation:
-- Period end = Period start + 1 year - 1 day, capped at effective_to
CASE
  WHEN mm.MEMBERSHIP_ID IS NOT NULL
       AND iui.CREATED_ON BETWEEN me.valid_from AND me.effective_to
  THEN 
    LEAST(
      -- Calculate period end: add 1 year to period start, subtract 1 day
      ADD_MONTHS(
        CASE
          WHEN TO_DATE(
                 TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON), 'FM9999') || '-' ||
                 TO_CHAR(EXTRACT(MONTH FROM me.valid_from), 'FM00') || '-' ||
                 TO_CHAR(EXTRACT(DAY FROM me.valid_from), 'FM00'),
                 'YYYY-MM-DD'
               ) <= iui.CREATED_ON
          THEN TO_DATE(
                 TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON), 'FM9999') || '-' ||
                 TO_CHAR(EXTRACT(MONTH FROM me.valid_from), 'FM00') || '-' ||
                 TO_CHAR(EXTRACT(DAY FROM me.valid_from), 'FM00'),
                 'YYYY-MM-DD'
               )
          ELSE TO_DATE(
                 TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON) - 1, 'FM9999') || '-' ||
                 TO_CHAR(EXTRACT(MONTH FROM me.valid_from), 'FM00') || '-' ||
                 TO_CHAR(EXTRACT(DAY FROM me.valid_from), 'FM00'),
                 'YYYY-MM-DD'
               )
        END,
        12
      ) - 1,
      -- Cap at effective_to (membership end date)
      me.effective_to
    )
END AS "Membership_Period_End"

-- ============================================================================
-- ALTERNATIVE SIMPLIFIED VERSION (more efficient, avoids duplication):
-- ============================================================================
-- You can use a subquery or CTE to calculate the period start once, then reuse it:
--
-- WITH period_start AS (
--   SELECT 
--     CASE
--       WHEN TO_DATE(
--              TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON), 'FM9999') || '-' ||
--              TO_CHAR(EXTRACT(MONTH FROM me.valid_from), 'FM00') || '-' ||
--              TO_CHAR(EXTRACT(DAY FROM me.valid_from), 'FM00'),
--              'YYYY-MM-DD'
--            ) <= iui.CREATED_ON
--       THEN TO_DATE(
--              TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON), 'FM9999') || '-' ||
--              TO_CHAR(EXTRACT(MONTH FROM me.valid_from), 'FM00') || '-' ||
--              TO_CHAR(EXTRACT(DAY FROM me.valid_from), 'FM00'),
--              'YYYY-MM-DD'
--            )
--       ELSE TO_DATE(
--              TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON) - 1, 'FM9999') || '-' ||
--              TO_CHAR(EXTRACT(MONTH FROM me.valid_from), 'FM00') || '-' ||
--              TO_CHAR(EXTRACT(DAY FROM me.valid_from), 'FM00'),
--              'YYYY-MM-DD'
--            )
--     END AS period_start_date
--   FROM ...
-- )
-- SELECT
--   period_start_date AS "Membership_ValidFrom",
--   LEAST(ADD_MONTHS(period_start_date, 12) - 1, me.effective_to) AS "Membership_Period_End"
-- FROM period_start ...
