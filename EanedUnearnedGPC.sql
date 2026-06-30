--DROP PROC [dbo].[sp_GPC_earned_unearned_premium]
CREATE OR ALTER               PROC [dbo].[sp_GPC_Earned_Unearned_Premium]
(
@StartDate DATE
)
AS

BEGIN
--DECLARE @StartDate Date = '02-24-2026';
-- DECLARE @Month INT = 4;


WITH PolicyGroup AS
(
    SELECT DISTINCT
        PolicyNumber,
        Policy_ref,
        EffectiveDate,
        ExpirationDate,
        PolicyStatus
    FROM dbo.Policy_versions
),

-- ✅ STEP 2: Latest transaction per PolicyNumber
LatestTransaction AS
(
    SELECT *
    FROM
    (
        SELECT
            pg.PolicyNumber,
            t.Policy_ref,
            t.Number,
            t.Type AS TransactionType,
            t.EffectiveDate AS TransactionEffectiveDate,
            ROW_NUMBER() OVER (
                PARTITION BY pg.PolicyNumber
                ORDER BY t.Number DESC
            ) rn
        FROM PolicyGroup pg
        JOIN dbo.Transaction_versions t
            ON pg.Policy_ref = t.Policy_ref
        WHERE 
            LTRIM(RTRIM(ISNULL(t.Status,''))) = 'Committed'
            AND t.EffectiveDate < @StartDate   -- ✅ ADD THIS LINE
    ) x
    WHERE rn = 1
),
Cancellation AS
(
    SELECT
        Policy_ref,

        MAX(CAST(EffectiveDate AS DATE)) AS CancellationEffectiveDate

    FROM dbo.Transaction_versions

    WHERE 
        LTRIM(RTRIM(Status)) = 'Committed'
        AND Type IN ('Cancellation','Cancel')

    GROUP BY Policy_ref
),

-- ✅ STEP 3: Final Policy snapshot
PolicyBase AS
(
    SELECT
        lt.PolicyNumber,
        lt.Policy_ref,
         lt.TransactionType,
        lt.TransactionEffectiveDate,
        pg.EffectiveDate,
        pg.ExpirationDate,
        pg.PolicyStatus

    FROM LatestTransaction lt
    JOIN PolicyGroup pg
        ON lt.Policy_ref = pg.Policy_ref
),

-- ✅ Billing
BillingPlan AS
(
    SELECT
        b.Policy_ref,
        CASE
            WHEN MAX(CASE WHEN bt.PayplanName = 'Settlement Deduction' THEN 1 END) = 1
                THEN 'Settlement Deduction'
            WHEN MAX(CASE WHEN bt.PayplanName IN ('Monthly','Weekly')
                          OR bt.PayplanName LIKE '%Direct Bill%' THEN 1 END) = 1
                THEN 'Direct Bill'
            ELSE ''
        END AS BillingType
    FROM dbo.Billing_versions b
    JOIN dbo.Billing_Terms_versions_segment bt
        ON b.segmentId = bt.segment_Id
    GROUP BY b.Policy_ref
),

-- ✅ Address
Address AS
(
    SELECT
        ia.Policy_ref,
        addr.City,
        addr.CityCode AS State,
        ROW_NUMBER() OVER (
            PARTITION BY ia.Policy_ref
            ORDER BY addr.segment_Id DESC
        ) rn
    FROM dbo.InsuredAccount_versions ia
    JOIN dbo.InsuredAccount_Address_versions_segment addr
        ON ia.segmentId = addr.segment_Id
    WHERE ia.segmentType = 'InsuredAccount'
      AND addr.Description = 'Company Address'
),
LatestPremium AS
(
    SELECT
        tp.Policy_ref,
        tp.AnnualPremium,
        tp.EffectivePremiumWithFeesAndTaxes
    FROM dbo.TotalPremium_versions tp
),

-- ✅ Vehicle
Vehicle AS
(
    SELECT
        p.Policy_ref,

        COUNT(*) *
        (
            DATEDIFF
            (
                DAY,

                CASE
                    WHEN p.TransactionType = 'Endorsement'
                         AND ISNULL(prem.EffectivePremiumWithFeesAndTaxes,0) <> 0
                    THEN p.TransactionEffectiveDate

                    ELSE p.EffectiveDate
                END,

                CASE
                    WHEN canc.CancellationEffectiveDate IS NOT NULL
                    THEN canc.CancellationEffectiveDate

                    WHEN @StartDate < p.ExpirationDate
                    THEN @StartDate

                    ELSE p.ExpirationDate
                END
            ) * 1.0

            /

            NULLIF
            (
                DATEDIFF
                (
                    DAY,
                    p.EffectiveDate,
                    p.ExpirationDate
                ),
                0
            )
        ) AS TruckCountProrated

    FROM PolicyBase p

    LEFT JOIN LatestPremium prem
        ON p.Policy_ref = prem.Policy_ref

    LEFT JOIN Cancellation canc
        ON p.Policy_ref = canc.Policy_ref

    JOIN dbo.Risks_Vehicles_versions rv
        ON p.Policy_ref = rv.Policy_ref

    JOIN dbo.Risks_Vehicles_versions_segment v
        ON rv.segmentId = v.segment_Id

    WHERE v.Status IN ('Active','Valid')

    GROUP BY
        p.Policy_ref,
        p.TransactionType,
        p.TransactionEffectiveDate,
        p.EffectiveDate,
        p.ExpirationDate,
        canc.CancellationEffectiveDate,
        prem.EffectivePremiumWithFeesAndTaxes
),

-- ✅ Premium (latest only)


-- ✅ Coverage (FINAL FIX — components only + PIP included)
Coverage AS
(
    SELECT
        Policy_ref,

        -- AL (includes PIP)
        SUM(CASE WHEN Name IN (
            'AutoLiability','HiredAuto','NonOwnedAuto',
            'MedicalPayments','UM-UIM'
        ) THEN AnnualPremium ELSE 0 END) AS AL,

        -- PD
        SUM(CASE WHEN Name IN ('Collision','Comp','HiredPD')
            THEN AnnualPremium ELSE 0 END) AS PD,

        -- GL
        SUM(CASE WHEN Name IN ('GeneralLiability','WarehouseGL')
            THEN AnnualPremium ELSE 0 END) AS GL,

        -- CG
        SUM(CASE WHEN Name = 'Cargo'
            THEN AnnualPremium ELSE 0 END) AS IM,

        -- PIP separate
        SUM(CASE WHEN Name = 'PIP'
            THEN AnnualPremium ELSE 0 END) AS PIP

    FROM dbo.PremiumFactors_versions
    GROUP BY Policy_ref
),
 ThreePL_Logistics AS
(
    SELECT
        tpl.Policy_ref,
        STRING_AGG(
            CAST(
                COALESCE(
                    CASE
                        WHEN UPPER(LTRIM(RTRIM(ISNULL(tpl.[Name], N'')))) = N'OTHER'
                        THEN NULLIF(LTRIM(RTRIM(tpl.OtherThreePLName)), N'')
                    END,
                    tpl.[Name]
                ) AS NVARCHAR(500)
            ),
            N', '
        ) WITHIN GROUP (ORDER BY tpl.[Name]) AS LogisticsProviderNames
    FROM [dbo].[PolicyRiskAttributes_ThreePLLogistics_versions] AS tpl
    GROUP BY tpl.Policy_ref
),
AgencyCommission AS
(
    SELECT
        ac.Policy_ref,

        CASE
            WHEN lt.TransactionType = 'Renewal'
                THEN ac.RenewalCommissionRate
            ELSE ac.NewBusinessCommissionerate
        END AS CommissionRate

    FROM dbo.Agency_Commissions_versions ac
    JOIN LatestTransaction lt
        ON ac.Policy_ref = lt.Policy_ref
),
-- ✅ FINAL CALC
FinalCalc AS
(
    SELECT
        p.PolicyNumber,
        p.Policy_ref,
        p.EffectiveDate,
        p.ExpirationDate,
        canc.CancellationEffectiveDate,
        p.PolicyStatus,
        bp.BillingType,
        addr.City,
        addr.State,
        logi.LogisticsProviderNames,
        ISNULL(v.TruckCountProrated,0) AS TruckCountProrated,
        prem.AnnualPremium,
        prem.EffectivePremiumWithFeesAndTaxes,
   
        comm.CommissionRate,
        cov.AL,
        cov.PD,
        cov.PIP,
        cov.GL,
        cov.IM,

        DATEDIFF(DAY,p.EffectiveDate,
            CASE WHEN @StartDate < p.ExpirationDate THEN @StartDate ELSE p.ExpirationDate END
        ) AS EarnedDays,

        DATEDIFF(DAY,p.EffectiveDate,p.ExpirationDate) AS TotalDays

    FROM PolicyBase p
    LEFT JOIN BillingPlan bp ON p.Policy_ref = bp.Policy_ref
    LEFT JOIN Address addr ON p.Policy_ref = addr.Policy_ref AND addr.rn = 1
    LEFT JOIN Vehicle v ON p.Policy_ref = v.Policy_ref
    LEFT JOIN LatestPremium prem ON p.Policy_ref = prem.Policy_ref
    LEFT JOIN AgencyCommission comm
    ON p.Policy_ref = comm.Policy_ref
    LEFT JOIN Coverage cov ON p.Policy_ref = cov.Policy_ref
    LEFT JOIN Cancellation canc
    ON p.Policy_ref = canc.Policy_ref
      LEFT JOIN ThreePL_Logistics logi
        ON p.Policy_ref = logi.Policy_ref
)

-- ✅ FINAL OUTPUT
SELECT
    PolicyNumber,
    MAX(BillingType) AS BillingPlan_CHOICE,
    MIN(EffectiveDate) AS EffectiveDate,
    MAX(ExpirationDate) AS ExpirationDate,

    CAST( MAX(CancellationEffectiveDate) as Date)
 AS CancellationDate,

    CONCAT(YEAR(MIN(EffectiveDate)),' - ',YEAR(MAX(ExpirationDate))) AS [Policy Term Group],

    MAX(City) AS City,
    MAX(State) AS State,
    COALESCE(MAX(LogisticsProviderNames), N'') AS LogisticsProviderName,
    CAST(MAX(TruckCountProrated) AS DECIMAL(18,2)) AS [Truck Count (Prorated)],

    -- Commission
CASE
    WHEN MAX(TRY_CAST(CommissionRate AS DECIMAL(18,2))) IS NULL
    THEN ''
    ELSE CONVERT(
            VARCHAR(20),
            CAST(
                MAX(TRY_CAST(CommissionRate AS DECIMAL(18,2))) / 100.0
                AS DECIMAL(18,2)
            )
         )
END AS CommissionRate,


CASE
    WHEN SUM(AnnualPremium * ISNULL(CommissionRate,0) / 100) IS NULL
         OR SUM(AnnualPremium * ISNULL(CommissionRate,0) / 100) = 0
    THEN ''
    ELSE FORMAT(
            CAST(
                SUM(AnnualPremium * ISNULL(CommissionRate,0) / 100)
            AS DECIMAL(18,2)
         ),
         'C2',
         'en-US'
    )
END AS Commission,
    -- Earned
   FORMAT(CAST(SUM(AnnualPremium * EarnedDays * 1.0 / NULLIF(TotalDays,0)) AS DECIMAL(18,2)),'C2','en-US') AS [Earned Premium],

    FORMAT(CAST(SUM(AL * EarnedDays * 1.0 / NULLIF(TotalDays,0)) AS DECIMAL(18,2)),'C2','en-US') AS [Earned Premium Auto Liability Group],
    FORMAT(CAST(SUM(PD * EarnedDays * 1.0 / NULLIF(TotalDays,0)) AS DECIMAL(18,2)),'C2','en-US') AS [Earned Premium PhysDam Group],
    FORMAT(CAST(SUM(PIP * EarnedDays * 1.0 / NULLIF(TotalDays,0)) AS DECIMAL(18,2)),'C2','en-US') AS [Earned Premium PIP],
    FORMAT(CAST(SUM(GL * EarnedDays * 1.0 / NULLIF(TotalDays,0)) AS DECIMAL(18,2)),'C2','en-US') AS [Earned Premium General Liability],
    FORMAT(CAST(SUM(IM * EarnedDays * 1.0 / NULLIF(TotalDays,0)) AS DECIMAL(18,2)),'C2','en-US') AS [Earned Premium Inland Marine],

    -- ✅ WRITTEN (FIXED — NO SUM ISSUE)
    FORMAT(CAST(MAX(AnnualPremium) AS DECIMAL(18,2)),'C2','en-US') AS [Total Written Premium],
    FORMAT(CAST(MAX(AL) AS DECIMAL(18,2)),'C2','en-US') AS [Written AL],
    FORMAT(CAST(MAX(PD) AS DECIMAL(18,2)),'C2','en-US') AS [Written PD],
    FORMAT(CAST(MAX(PIP) AS DECIMAL(18,2)),'C2','en-US') AS [Written PIP],
    FORMAT(CAST(MAX(GL) AS DECIMAL(18,2)),'C2','en-US') AS [Written GL],
    FORMAT(CAST(MAX(IM) AS DECIMAL(18,2)),'C2','en-US') AS [Written IM],

    -- Unearned
FORMAT(CAST(SUM(
    AnnualPremium * ((TotalDays - EarnedDays) * 1.0 / NULLIF(TotalDays,0))
) AS DECIMAL(18,2)),'C2','en-US') AS [Total Unearned],

FORMAT(CAST(SUM(
    AL * ((TotalDays - EarnedDays) * 1.0 / NULLIF(TotalDays,0))
) AS DECIMAL(18,2)),'C2','en-US') AS [Unearned AL],

FORMAT(CAST(SUM(
    PD * ((TotalDays - EarnedDays) * 1.0 / NULLIF(TotalDays,0))
) AS DECIMAL(18,2)),'C2','en-US') AS [Unearned PD],

FORMAT(CAST(SUM(
    PIP * ((TotalDays - EarnedDays) * 1.0 / NULLIF(TotalDays,0))
) AS DECIMAL(18,2)),'C2','en-US') AS [Unearned PIP],

FORMAT(CAST(SUM(
    GL * ((TotalDays - EarnedDays) * 1.0 / NULLIF(TotalDays,0))
) AS DECIMAL(18,2)),'C2','en-US') AS [Unearned GL],

FORMAT(CAST(SUM(
    IM * ((TotalDays - EarnedDays) * 1.0 / NULLIF(TotalDays,0))
) AS DECIMAL(18,2)),'C2','en-US') AS [Unearned IM],
	MAX(EarnedDays) AS [Earned Days]

FROM FinalCalc
GROUP BY PolicyNumber

END