-- Pending e-Signature
SELECT  
    v.PolicyNumber,
    CAST(v.EffectiveDate AS DATE) AS [PolicyEffectiveDate],
    CAST(JSON_VALUE(v.[Transaction], '$.EffectiveDate') AS DATE) As TransactionEffectiveDate,
    pp.PayPlan,
    v.PolicyStatus,

    -- Full Name from JSON
    CONCAT(
        JSON_VALUE(v.InsuredAccount, '$.FirstName'), ' ',
        JSON_VALUE(v.InsuredAccount, '$.LastName')
    ) AS NamedInsured,

    -- Agency and Agent info from JSON
    CONCAT(JSON_VALUE(v.Agency, '$.Name'), ' (', JSON_VALUE(v.Agency, '$.Code'), ')') AS AgencyName,
    CONCAT(JSON_VALUE(v.Agent, '$.LocationName'), ' (', JSON_VALUE(v.Agent, '$.Code'), ')') AS AgencyLocation,
    JSON_VALUE(v.Agency, '$.Code') AS AgencyCode,

    CONCAT(
        JSON_VALUE(v.Agency, '$.Code'), '-', 
        JSON_VALUE(v.Agency, '$.Name'), '-', 
        JSON_VALUE(v.Agent, '$.LocationName')
    ) AS Agency,

    REPLACE(CONVERT(VARCHAR(10), v.EffectiveDate, 101), '-', '') AS DateID,

    -- Master Agency info
    Case WHEN am.LegalName is NULL or am.BrokerCode is NULL then CONCAT(JSON_VALUE(v.Agency, '$.Name'), ' (', JSON_VALUE(v.Agency, '$.Code'), ')') 
    ELSE CONCAT(am.LegalName, ' (', am.BrokerCode, ')') 
    END AS MasterAgencyNameCode,
    Case WHEN loc.City is NULL or loc.BrokerCode is NULL then CONCAT(JSON_VALUE(v.Agency, '$.Name'), ' (', JSON_VALUE(v.Agency, '$.Code'), ')') 
    ELSE CONCAT(loc.City, ' (', loc.BrokerCode, ')') 
    END AS MasterAgencyLocationCode,

    -- ✅ PolicyCancelledFlag logic using inline join
    CASE 
        WHEN flagged.PolicyNumber IS NOT NULL THEN 1
        ELSE 0
    END AS PolicyCancelledFlag

FROM [pos].[pos].[versions] v

OUTER APPLY (
    SELECT TOP 1  
        JSON_VALUE(value, '$.PPDescription') AS PayPlan
    FROM OPENJSON(v.Payplan)
    WHERE JSON_VALUE(value, '$.IsSelected') = 'true'
) AS pp

-- Get primary phone number
OUTER APPLY (
    SELECT STRING_AGG(Value, ', ') AS [Phone Number]
    FROM (
        SELECT DISTINCT Value
        FROM OPENJSON(v.InsuredAccount, '$.Communications')
        WITH (
            Type NVARCHAR(50),
            SubType NVARCHAR(50),
            Value NVARCHAR(100)
        )
        WHERE Type = 'PhNo' AND SubType = 'Primary'
    ) AS cleanPhones
) AS ph

-- Get primary email address
OUTER APPLY (
    SELECT STRING_AGG(Value, ', ') AS [Email Address]
    FROM (
        SELECT DISTINCT Value
        FROM OPENJSON(v.InsuredAccount, '$.Communications')
        WITH (
            Type NVARCHAR(50),
            SubType NVARCHAR(50),
            Value NVARCHAR(100)
        )
        WHERE Type = 'Email' AND SubType = 'Primary'
    ) AS cleanEmails
) AS em

-- ✅ LEFT JOIN with deduplicated agency + location
LEFT JOIN [TEST_IHDDM].[dbo].[agency-management] am
    ON JSON_VALUE( v.Agency, '$.Code') = am.BrokerCode

LEFT JOIN [TEST_IHDDM].[dbo].[am_locations_Locations] loc 
    ON am.id = loc.AgencyId

-- ✅ Inline subquery for PolicyCancelledFlag
LEFT JOIN (
    SELECT DISTINCT PolicyNumber
    FROM [pos].[pos].[policy]
    WHERE PolicyStatus IN ('Policy Cancelled', 'Active Policy')
) AS flagged
    ON v.PolicyNumber = flagged.PolicyNumber

WHERE 
    JSON_VALUE(v.Attributes, '$.Client') = 'IH'
    AND v.PolicyNumber <> ' '
/*  AND CONCAT(aml.LegalName, ' (', aml.BrokerCode, ')') like 'DDM Agency One (10010-GA-001)'
    AND v.PolicyNumber NOT LIKE '${policyNumber}'
    AND CONCAT(aml.LegalName, ' (', aml.BrokerCode, ')') NOT LIKE ' ()'
    AND CONCAT(aml.City, ' (', aml.BrokerCode, ')') NOT LIKE ' ()'
    AND v.PolicyStatus IN (
        'Active Policy',
        'Active Policy - Bind Signature Pending',
        'Pending Cancellation-Signed Application',
        'Policy Cancelled',
        'Renewal Offered - Signature Pending',
        'Endorsement Signature Pending',
        'Pending Cancellation - Endorsement Signature Pending',
        'Renewal Offered Expired - Signature Pending',
        'Reinstatement Signature Pending'
    );
*/