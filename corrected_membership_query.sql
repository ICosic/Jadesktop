WITH
/* ---- Services in the case (only valid, non-storned) ---- */
case_services AS (
  SELECT /*+ MATERIALIZE */
         s.UC_INTERVENTION_ID,
         s.UC_SERVICE_ID,
         s.PRODUCT_SERVICE_ID
  FROM ODYSSEY.INT_UC_SERVICE s
  WHERE s.DELETED = 0
    AND s.CBK_STATUS_ID <> 'INTERVENTION_SERVICE.STORNED'
),

/* ---- Product names per case (pre-aggregated once) ---- */
product_agg AS (
  SELECT /*+ MATERIALIZE */
         x.UC_INTERVENTION_ID,
         LISTAGG(prod.NAME, ', ') WITHIN GROUP (ORDER BY prod.NAME) AS PROIZVOD
  FROM (
    SELECT DISTINCT cs.UC_INTERVENTION_ID, cs.PRODUCT_SERVICE_ID
    FROM case_services cs
    WHERE cs.PRODUCT_SERVICE_ID IS NOT NULL
  ) x
  JOIN ODYSSEY.PCG_PRODUCT_SERVICE pps
    ON pps.PRODUCT_SERVICE_ID = x.PRODUCT_SERVICE_ID
   AND pps.DELETED = 0
  JOIN ODYSSEY.PCG_PRODUCT prod
    ON prod.PRODUCT_ID = pps.PRODUCT_ID
   AND prod.DELETED = 0
  GROUP BY x.UC_INTERVENTION_ID
),

/* ---- Memberships actually used in cases ---- */
mem_in_case AS (
  SELECT /*+ MATERIALIZE */ DISTINCT iui.MEMBERSHIP_ID
  FROM ODYSSEY.INT_UC_INTERVENTION iui
  WHERE iui.MEMBERSHIP_ID IS NOT NULL
),

/* ---- Effective membership window (only for those in cases) ---- */
membership_effective AS (
  SELECT /*+ MATERIALIZE */
         mm.MEMBERSHIP_ID,
         TRUNC(mm.VALID_FROM) AS valid_from,
         TRUNC(COALESCE(mm.DATE_OF_PREMATURE_CLOSURE, mm.VALID_TO)) AS effective_to,
         COALESCE(mm.PACKAGE_COMPOSITE_ID, mm.PACKAGE_ID) AS PACKAGE_ID_EFF,
         mm.PACKAGE_ID,
         mm.PACKAGE_COMPOSITE_ID
  FROM ODYSSEY.MEM_MEMBERSHIP mm
  WHERE mm.DELETED = 0
    AND EXISTS (SELECT 1
                FROM mem_in_case mic
                WHERE mic.MEMBERSHIP_ID = mm.MEMBERSHIP_ID)
)

SELECT
  iui.UC_INTERVENTION_ID                           AS "Case_Number",
  iui.CALL_CENTER_CBK_COUNTRY_ID                   AS "Client_Country",
  iui.CREATED_ON                                   AS "CreatedOn",

  sc.NAME                                          AS "Partner__Name",
  sc.CODE                                          AS "Partner_Code",

  mm.MEMBERSHIP_ID                                 AS "Membership_ID",

  /* CORRECTED: Find the anniversary-based period start (LEAP-YEAR SAFE) */
  CASE
    WHEN mm.MEMBERSHIP_ID IS NOT NULL
         AND iui.CREATED_ON BETWEEN me.valid_from AND me.effective_to
    THEN
      -- Calculate years difference, then use ADD_MONTHS to handle leap years
      CASE
        -- Calculate anniversary in CREATED_ON's year
        WHEN iui.CREATED_ON >= ADD_MONTHS(
               me.valid_from,
               12 * (EXTRACT(YEAR FROM iui.CREATED_ON) - EXTRACT(YEAR FROM me.valid_from))
             )
        THEN
          -- Use current year's anniversary
          ADD_MONTHS(
            me.valid_from,
            12 * (EXTRACT(YEAR FROM iui.CREATED_ON) - EXTRACT(YEAR FROM me.valid_from))
          )
        ELSE
          -- Use previous year's anniversary
          ADD_MONTHS(
            me.valid_from,
            12 * (EXTRACT(YEAR FROM iui.CREATED_ON) - EXTRACT(YEAR FROM me.valid_from) - 1)
          )
      END
  END                                              AS "Membership_ValidFrom",

  /* CORRECTED: Period end is 1 day before next anniversary, capped at effective_to (LEAP-YEAR SAFE) */
  CASE
    WHEN mm.MEMBERSHIP_ID IS NOT NULL
         AND iui.CREATED_ON BETWEEN me.valid_from AND me.effective_to
    THEN
      LEAST(
        -- Next anniversary minus 1 day (using ADD_MONTHS for leap year safety)
        CASE
          -- If CREATED_ON is on/after the anniversary in its year
          WHEN iui.CREATED_ON >= ADD_MONTHS(
                 me.valid_from,
                 12 * (EXTRACT(YEAR FROM iui.CREATED_ON) - EXTRACT(YEAR FROM me.valid_from))
               )
          THEN
            -- Next anniversary is in the following year
            ADD_MONTHS(
              me.valid_from,
              12 * (EXTRACT(YEAR FROM iui.CREATED_ON) - EXTRACT(YEAR FROM me.valid_from) + 1)
            ) - 1
          ELSE
            -- Next anniversary is in the same year
            ADD_MONTHS(
              me.valid_from,
              12 * (EXTRACT(YEAR FROM iui.CREATED_ON) - EXTRACT(YEAR FROM me.valid_from))
            ) - 1
        END,
        me.effective_to
      )
  END                                              AS "Membership_Period_End",

  NVL(me.PACKAGE_ID_EFF, -1)                      AS "Package_ID",
  COALESCE(sp2.NAME, sp.NAME, 'NoPackage')        AS "Package_Name",

  bs_case.NAME                                     AS "Case_Status_Name",
  27.375                                           AS "Case_Callcenter",

  pa.PROIZVOD                                      AS "Product",
  pce.NAME                                         AS "Event_Type"

FROM ODYSSEY.INT_UC_INTERVENTION iui

/* Membership (keep NULLs) */
LEFT JOIN membership_effective me
  ON me.MEMBERSHIP_ID = iui.MEMBERSHIP_ID
LEFT JOIN ODYSSEY.MEM_MEMBERSHIP mm
  ON mm.MEMBERSHIP_ID = me.MEMBERSHIP_ID
 AND mm.DELETED = 0

/* Packages */
LEFT JOIN ODYSSEY.SLS_PACKAGE sp
  ON sp.PACKAGE_ID = mm.PACKAGE_ID
 AND sp.DELETED = 0
LEFT JOIN ODYSSEY.SLS_PACKAGE sp2
  ON sp2.PACKAGE_ID = mm.PACKAGE_COMPOSITE_ID
 AND sp2.DELETED = 0

/* Sales channel */
LEFT JOIN ODYSSEY.SLS_SALES_CHANNEL sc
  ON sc.SALES_CHANNEL_ID = iui.SALES_CHANNEL_ID

/* Case status & event */
LEFT JOIN ODYSSEY.BPM_CBK_STATUS bs_case
  ON bs_case.CBK_STATUS_ID = iui.CBK_STATUS_ID
 AND bs_case.DELETED = 0
LEFT JOIN ODYSSEY.PCG_CBK_COVERED_EVENT pce
  ON pce.CBK_COVERED_EVENT_ID = iui.CBK_COVERED_EVENT_ID
 AND pce.DELETED = 0

/* Aggregated product names per case */
LEFT JOIN product_agg pa
  ON pa.UC_INTERVENTION_ID = iui.UC_INTERVENTION_ID

WHERE iui.DELETED = 0
    --AND iui.UC_INTERVENTION_ID = '542820'
ORDER BY "Case_Number"
