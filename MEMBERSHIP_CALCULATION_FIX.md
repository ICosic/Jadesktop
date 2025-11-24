# Membership Period Calculation Fix

## Problem Description

The original SQL query incorrectly calculated membership valid periods because it used linear month counting instead of **anniversary-based date logic**.

### Original Broken Logic

```sql
-- INCORRECT: Uses linear month calculation
ADD_MONTHS(
  me.valid_from,
  12 * FLOOR(MONTHS_BETWEEN(iui.CREATED_ON, me.valid_from))
)
```

**Why this fails:**
- `MONTHS_BETWEEN` counts total months between dates
- `FLOOR` rounds down to nearest year
- **Ignores the actual anniversary day/month** from the original `valid_from`

## Understanding the Requirements

For a membership with a **100-year duration** that renews annually:

1. **Take the day and month** from the original `VALID_FROM` date
2. **Find which year chunk** the case's `CREATED_ON` falls into
3. Each chunk runs from the anniversary date to one day before the next anniversary

### Example Scenario

**Membership Details:**
- `VALID_FROM`: **2020-03-15** (March 15, 2020)
- Duration: 100 years (renews annually on March 15)

**Case Created:** **2023-05-20** (May 20, 2023)

**Annual Chunks:**
- 2020-03-15 to 2021-03-14 (Year 1)
- 2021-03-15 to 2022-03-14 (Year 2)
- 2022-03-15 to 2023-03-14 (Year 3)
- **2023-03-15 to 2024-03-14** ← Case falls here!
- 2024-03-15 to 2025-03-14 (Year 5)
- ...

**Expected Result:**
- `Membership_ValidFrom`: **2023-03-15**
- `Membership_Period_End`: **2024-03-14**

## The Corrected Solution

### Step 1: Calculate the Anniversary Date in CREATED_ON's Year

```sql
TO_DATE(
  TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON)) ||  -- Get year from CREATED_ON
  TO_CHAR(me.valid_from, 'MMDD'),                -- Get MMDD from VALID_FROM
  'YYYYMMDD'
)
```

This constructs a date like: `2023` + `0315` = `2023-03-15`

### Step 2: Determine Which Anniversary Period

```sql
CASE
  -- If CREATED_ON is on or after this year's anniversary
  WHEN iui.CREATED_ON >= [anniversary in CREATED_ON's year]
  THEN
    [Use this year's anniversary]
  
  -- If CREATED_ON is before this year's anniversary
  ELSE
    [Use previous year's anniversary]
END
```

### Step 3: Calculate Period Start (Membership_ValidFrom)

```sql
CASE
  WHEN mm.MEMBERSHIP_ID IS NOT NULL
       AND iui.CREATED_ON BETWEEN me.valid_from AND me.effective_to
  THEN
    CASE
      WHEN iui.CREATED_ON >= TO_DATE(
             TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON)) || 
             TO_CHAR(me.valid_from, 'MMDD'),
             'YYYYMMDD'
           )
      THEN
        -- Use current year's anniversary
        TO_DATE(
          TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON)) || 
          TO_CHAR(me.valid_from, 'MMDD'),
          'YYYYMMDD'
        )
      ELSE
        -- Use previous year's anniversary
        TO_DATE(
          TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON) - 1) || 
          TO_CHAR(me.valid_from, 'MMDD'),
          'YYYYMMDD'
        )
    END
END
```

### Step 4: Calculate Period End (Membership_Period_End)

The period end is **one day before the next anniversary**, capped at the membership's `effective_to` date.

```sql
CASE
  WHEN mm.MEMBERSHIP_ID IS NOT NULL
       AND iui.CREATED_ON BETWEEN me.valid_from AND me.effective_to
  THEN
    LEAST(
      CASE
        WHEN iui.CREATED_ON >= TO_DATE(
               TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON)) || 
               TO_CHAR(me.valid_from, 'MMDD'),
               'YYYYMMDD'
             )
        THEN
          -- Next anniversary is in the following year, minus 1 day
          TO_DATE(
            TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON) + 1) || 
            TO_CHAR(me.valid_from, 'MMDD'),
            'YYYYMMDD'
          ) - 1
        ELSE
          -- Next anniversary is in the same year, minus 1 day
          TO_DATE(
            TO_CHAR(EXTRACT(YEAR FROM iui.CREATED_ON)) || 
            TO_CHAR(me.valid_from, 'MMDD'),
            'YYYYMMDD'
          ) - 1
      END,
      me.effective_to  -- Don't exceed the membership's closure date
    )
END
```

## Testing the Fix

### Test Case 1: Case created AFTER anniversary in same year

**Input:**
- `valid_from`: 2020-03-15
- `CREATED_ON`: 2023-05-20

**Expected:**
- `Membership_ValidFrom`: 2023-03-15
- `Membership_Period_End`: 2024-03-14

✅ **Result:** Case falls in period starting at current year's anniversary

### Test Case 2: Case created BEFORE anniversary in same year

**Input:**
- `valid_from`: 2020-03-15
- `CREATED_ON`: 2023-01-10

**Expected:**
- `Membership_ValidFrom`: 2022-03-15
- `Membership_Period_End`: 2023-03-14

✅ **Result:** Case falls in period starting at previous year's anniversary

### Test Case 3: Case created ON anniversary date

**Input:**
- `valid_from`: 2020-03-15
- `CREATED_ON`: 2023-03-15

**Expected:**
- `Membership_ValidFrom`: 2023-03-15
- `Membership_Period_End`: 2024-03-14

✅ **Result:** Case falls at the start of current year's period

## Summary

The fix ensures that:

1. ✅ The **day and month** from `VALID_FROM` are preserved across all years
2. ✅ The **year** is calculated based on which anniversary period contains `CREATED_ON`
3. ✅ Membership periods are **one full year** (anniversary to day before next anniversary)
4. ✅ Periods are **capped** at the membership's `effective_to` date

## Files

- `corrected_membership_query.sql` - Full corrected query with comments
- This document - Detailed explanation of the fix
