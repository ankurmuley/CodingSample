-- Daily Transactiom Report
Select 
p.PolicyNumber, 
'Expiration' AS Transaction_Type, 
CONCAT(
    UPPER(LEFT(JSON_VALUE(p.InsuredAccount, '$.FirstName'), 1)),
    LOWER(SUBSTRING(JSON_VALUE(p.InsuredAccount, '$.FirstName'), 2, LEN(JSON_VALUE(p.InsuredAccount, '$.FirstName')))),
    ' ',
    UPPER(LEFT(JSON_VALUE(p.InsuredAccount, '$.LastName'), 1)),
    LOWER(SUBSTRING(JSON_VALUE(p.InsuredAccount, '$.LastName'), 2, LEN(JSON_VALUE(p.InsuredAccount, '$.LastName'))))
) AS NamedInsured,
CAST(p.EffectiveDate AS DATE) AS [PolicyEffectiveDate],
CAST(JSON_VALUE(p.[Transaction], '$.EffectiveDate') AS DATE) AS [TransactionEffectiveDate],
NULL AS PayPlan,
JSON_VALUE(p.TotalPremium, '$.EffectivePremium') AS Premium,
NULL AS DownPayment,
NULL AS Installment,
NULL AS RevisedTermPremium,
NULL AS AdditionalPremiumCredit,
JSON_VALUE(p.[Transaction], '$.Reason') as Reason,
JSON_VALUE(p.Audit, '$.LastUpdatedOn') as LastUpdatedOn,
NULL AS PremiumNeeded,
NULL AS Status,
 -- Agency and Agent info from JSON
    CONCAT(JSON_VALUE(p.Agency, '$.Name'), ' (', JSON_VALUE(p.Agency, '$.Code'), ')') AS AgencyName,
    CONCAT(JSON_VALUE(p.Agent, '$.LocationName'), ' (', JSON_VALUE(p.Agent, '$.Code'), ')') AS AgencyLocation,
    JSON_VALUE(p.Agency, '$.Code') AS AgencyCode,

    CONCAT(
        JSON_VALUE(p.Agency, '$.Code'), '-', 
        JSON_VALUE(p.Agency, '$.Name'), '-', 
        JSON_VALUE(p.Agent, '$.LocationName')
    ) AS Agency,

    REPLACE(CONVERT(VARCHAR(10), JSON_VALUE(p.Audit, '$.LastUpdatedOn'), 101), '-', '') AS DateID,

    -- Master Agency info
    Case WHEN am.LegalName is NULL or am.BrokerCode is NULL then CONCAT(JSON_VALUE(p.Agency, '$.Name'), ' (', JSON_VALUE(p.Agency, '$.Code'), ')') 
    ELSE CONCAT(am.LegalName, ' (', am.BrokerCode, ')') 
    END AS MasterAgencyNameCode,
    Case WHEN loc.City is NULL or loc.BrokerCode is NULL then CONCAT(JSON_VALUE(p.Agency, '$.Name'), ' (', JSON_VALUE(p.Agency, '$.Code'), ')') 
    ELSE CONCAT(loc.City, ' (', loc.BrokerCode, ')') 
    END AS MasterAgencyLocationCode

FROM [pos].[pos].[policy] p
JOIN (
    SELECT bp.id AS Policy_ref
    FROM (
        SELECT 
            p.id,
            p.PolicyNumber,   -- include raw PolicyNumber here
            CASE 
                WHEN CHARINDEX('-', p.PolicyNumber) > 0 
                THEN LEFT(p.PolicyNumber, CHARINDEX('-', p.PolicyNumber) - 1)
                ELSE p.PolicyNumber
            END AS BasePolicyNumber,
            CASE 
                WHEN CHARINDEX('-', p.PolicyNumber) > 0 
                THEN CAST(RIGHT(p.PolicyNumber, LEN(p.PolicyNumber) - CHARINDEX('-', p.PolicyNumber)) AS INT)
                ELSE 0
            END AS PolicyVersion,
            p.PolicyStatus
        FROM [pos].[pos].[policy] p
        WHERE JSON_VALUE(p.Attributes, '$.Client') = 'IH'
          AND LEN(p.PolicyNumber) >= 13
    ) bp
    CROSS APPLY (
        SELECT MAX(PolicyVersion) AS MaxVer
        FROM (
            SELECT 
                bp.BasePolicyNumber,
                bp.PolicyVersion
        ) b2
        WHERE b2.BasePolicyNumber = bp.BasePolicyNumber
    ) mv
    WHERE bp.PolicyVersion = mv.MaxVer
      AND bp.PolicyStatus = 'Expired'
) FS ON FS.Policy_ref = p.id

-- Join for master agency details
LEFT JOIN [TEST_IHDDM].[dbo].[agency-management] am
    ON JSON_VALUE(p.Agency, '$.Code') = am.BrokerCode

LEFT JOIN [TEST_IHDDM].[dbo].[am_locations_Locations] loc 
    ON am.id = loc.AgencyId

OUTER APPLY (
    SELECT JSON_VALUE(value,'$.PPDescription') AS PayPlan,
     JSON_VALUE(value, '$.DownPaymentAmount') AS DownPayment,
     JSON_QUERY(value,'$.Installments') as Installments
     FROM OPENJSON(p.Payplan)
    WHERE JSON_VALUE(value, '$.IsSelected') = 'true'
) AS pp
OUTER APPLY( 
    SELECT TOP 1 
    JSON_VALUE(value, '$.DownPay') as Installment,
    TRY_CAST(JSON_VALUE(value,'$.Date') AS DATE) AS InstallmentDate
    FROM OPENJSON(pp.Installments)
    ORDER BY CAST(JSON_VALUE(value,'$.Date') AS DATE) DESC
) AS i
WHERE 
    JSON_VALUE(p.Attributes, '$.Client') = 'IH'
UNION ALL
Select v.PolicyNumber,
 CASE 
    WHEN JSON_VALUE(v.[Transaction], '$.Status')= 'Committed' THEN
        CASE 
            WHEN JSON_VALUE(v.[Transaction], '$.Type') IN ('Policy', 'NEW') THEN 'New Business' 
            WHEN JSON_VALUE(v.[Transaction], '$.Type') = 'Endorsement' THEN 'Endorsement'
            WHEN JSON_VALUE(v.[Transaction], '$.Type') ='Renewal' THEN 'Renewal'
            WHEN JSON_VALUE(v.[Transaction], '$.Type') = 'Reinstate' THEN 'Reinstatement'
            WHEN JSON_VALUE(v.[Transaction], '$.Type') = 'Cancellation' THEN 'Cancellation'
            ELSE JSON_VALUE(v.[Transaction], '$.Type') 
        END
    WHEN JSON_VALUE(v.[Transaction], '$.Status') = 'Voided' THEN 
        CASE
            WHEN JSON_VALUE(v.[Transaction], '$.Type') = 'Reinstate' AND v.PolicyStatus = 'Rescind' THEN 'Reinstatement'
            WHEN JSON_VALUE(v.[Transaction], '$.Type') = 'Cancellation' THEN 'Pending Cancellation'
            WHEN JSON_VALUE(v.[Transaction], '$.Type') ='Renewal' AND TRY_CAST(v.EffectiveDate AS DATE) >= DATEADD(DAY, -30, CAST(GETDATE() AS DATE)) THEN 'Renewal Offered'
            ELSE JSON_VALUE(v.[Transaction], '$.Type')
        END
    WHEN v.PolicyStatus = 'Pending Cancellation-Signed Application' THEN 'Cancellation Notice'     
    ELSE JSON_VALUE(v.[Transaction], '$.Type')     
END as Transaction_Type,
 CONCAT(
    UPPER(LEFT(JSON_VALUE(v.InsuredAccount, '$.FirstName'), 1)),
    LOWER(SUBSTRING(JSON_VALUE(v.InsuredAccount, '$.FirstName'), 2, LEN(JSON_VALUE(v.InsuredAccount, '$.FirstName')))),
    ' ',
    UPPER(LEFT(JSON_VALUE(v.InsuredAccount, '$.LastName'), 1)),
    LOWER(SUBSTRING(JSON_VALUE(v.InsuredAccount, '$.LastName'), 2, LEN(JSON_VALUE(v.InsuredAccount, '$.LastName'))))
) AS NamedInsured,
CAST(v.EffectiveDate AS DATE) AS [PolicyEffectiveDate],
CAST(JSON_VALUE(v.[Transaction], '$.EffectiveDate') AS DATE) AS [TransactionEffectiveDate],
pp.PayPlan AS PayPlan,
JSON_VALUE(v.TotalPremium, '$.EffectivePremium') AS Premium,
pp.DownPayment AS DownPayment,
i.Installment AS Installment,
JSON_VALUE(v.TotalPremium, '$.AnnualPremium') AS RevisedTermPremium,
JSON_VALUE(v.TotalPremium, '$.EffectivePremium')  AS AdditionalPremiumCredit,
JSON_VALUE(v.[Transaction], '$.Reason') as Reason,
JSON_VALUE(v.Audit, '$.LastUpdatedOn') as LastUpdatedOn,
        CASE 
            WHEN v.PolicyStatus = 'Pending Cancellation' THEN 0
            WHEN v.PolicyStatus = 'Policy Cancelled' THEN JSON_VALUE(v.TotalPremium, '$.EffectivePremium')
            ELSE NULL
        END AS PremiumNeeded,  
        CASE 
            WHEN PolicyStatus IN ('Pending Cancellation', 'Policy Cancelled') and DATEDIFF(DAY, v.EffectiveDate, GETDATE()) <= 15 THEN 'Eligible for Reinstatement'
            WHEN PolicyStatus IN ('Pending Cancellation', 'Policy Cancelled') THEN 'Not Eligible for Reinstatement'
            ELSE NULL
        END AS Status,
 -- Agency and Agent info from JSON
    CONCAT(JSON_VALUE(v.Agency, '$.Name'), ' (', JSON_VALUE(v.Agency, '$.Code'), ')') AS AgencyName,
    CONCAT(JSON_VALUE(v.Agent, '$.LocationName'), ' (', JSON_VALUE(v.Agent, '$.Code'), ')') AS AgencyLocation,
    JSON_VALUE(v.Agency, '$.Code') AS AgencyCode,

    CONCAT(
        JSON_VALUE(v.Agency, '$.Code'), '-', 
        JSON_VALUE(v.Agency, '$.Name'), '-', 
        JSON_VALUE(v.Agent, '$.LocationName')
    ) AS Agency,

    REPLACE(CONVERT(VARCHAR(10), JSON_VALUE(v.Audit, '$.LastUpdatedOn'), 101), '-', '') AS DateID,

    -- Master Agency info
    Case WHEN am.LegalName is NULL or am.BrokerCode is NULL then CONCAT(JSON_VALUE(v.Agency, '$.Name'), ' (', JSON_VALUE(v.Agency, '$.Code'), ')') 
    ELSE CONCAT(am.LegalName, ' (', am.BrokerCode, ')') 
    END AS MasterAgencyNameCode,
    Case WHEN loc.City is NULL or loc.BrokerCode is NULL then CONCAT(JSON_VALUE(v.Agency, '$.Name'), ' (', JSON_VALUE(v.Agency, '$.Code'), ')') 
    ELSE CONCAT(loc.City, ' (', loc.BrokerCode, ')') 
    END AS MasterAgencyLocationCode

FROM [pos].[pos].[versions] v

-- Join for master agency details
LEFT JOIN [TEST_IHDDM].[dbo].[agency-management] am
    ON JSON_VALUE(v.Agency, '$.Code') = am.BrokerCode

LEFT JOIN [TEST_IHDDM].[dbo].[am_locations_Locations] loc 
    ON am.id = loc.AgencyId

OUTER APPLY (
    SELECT JSON_VALUE(value,'$.PPDescription') AS PayPlan,
     JSON_VALUE(value, '$.DownPaymentAmount') AS DownPayment,
     JSON_QUERY(value,'$.Installments') as Installments
     FROM OPENJSON(v.Payplan)
    WHERE JSON_VALUE(value, '$.IsSelected') = 'true'
) AS pp
OUTER APPLY( 
    SELECT TOP 1 
    JSON_VALUE(value, '$.DownPay') as Installment,
    CAST(JSON_VALUE(value,'$.Date') AS DATE) AS InstallmentDate
    FROM OPENJSON(pp.Installments)
    ORDER BY CAST(JSON_VALUE(value,'$.Date') AS DATE) DESC
) AS i
WHERE 
    JSON_VALUE(v.Attributes, '$.Client') = 'IH'
   and v.PolicyNumber in ('GAPA007711009', 'GAPA007711004', 'GAPA007710107-1')
