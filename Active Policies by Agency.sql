CREATE OR ALTER VIEW [dbo].[ActivePolicyAgencyListing] AS

WITH RankedPolicies AS (

    SELECT DISTINCT

        a.Policy_ref,

        a.PolicyNumber,

        LEFT(a.PolicyNumber, PATINDEX('%[0-9]%', a.PolicyNumber) - 1) AS Prefix,

        SUBSTRING(a.PolicyNumber, PATINDEX('%[0-9]%', a.PolicyNumber), LEN(a.PolicyNumber)) AS TrimmedPolicyNumber,

        a.PolicyStatus,

        TRY_CAST(a.EffectiveDate AS DATE) AS EffectiveDate,

        TRY_CAST(a.ExpirationDate AS DATE) AS ExpirationDate,

        b.Type,

        b.Status,

        b.Number,

        tpp.AnnualPremium,

        iap.FirstName,

        iap.LastName,

        CASE

    WHEN ISNUMERIC(LTRIM(iap.[Address.Street])) = 1 THEN NULL

    WHEN PATINDEX('[0-9]%', iap.[Address.Street]) = 1 THEN

        LTRIM(SUBSTRING(iap.[Address.Street], CHARINDEX(' ', iap.[Address.Street]) + 1, LEN(iap.[Address.Street])))

    ELSE iap.[Address.Street]

END AS StreetWithoutNumbers



,

iap.[Address.Street],

        iap.[Address.City],

        iap.[Address.State],

        iap.[Address.Postalcode],

        iap.[Address.PoBox],

        acp.Code AS AgencyCode,

        acp.Name AS AgencyName,

        anp.Code AS AgentCode,

        anp.Name AS AgentLocation,

        CASE

       /* WHEN

        iap.[Address.Street] LIKE 'po box%' OR

        iap.[Address.Street] LIKE 'Po box%' OR

        iap.[Address.Street] LIKE 'PO box%' OR

        iap.[Address.Street] LIKE 'PO Box%' OR

        iap.[Address.Street] LIKE 'PO BOX%' OR

        iap.[Address.Street] LIKE 'Po Box%' OR

        iap.[Address.Street] LIKE ' po box%' OR

        iap.[Address.Street] LIKE ' Po box%' OR

        iap.[Address.Street] LIKE ' PO box%' OR

        iap.[Address.Street] LIKE ' PO Box%' OR

        iap.[Address.Street] LIKE ' PO BOX%' OR

        iap.[Address.Street] LIKE ' Po Box%'

        THEN iap.[Address.Street] */

        WHEN PATINDEX('[0-9]%', iap.[Address.Street]) = 1 THEN LEFT(iap.[Address.Street], CHARINDEX(' ', iap.[Address.Street] + ' ') - 1)

    END AS BuildingNumber

    FROM

        Policy_policy a

    JOIN

         Transaction_policy b ON a.Policy_ref = b.Policy_ref AND LEN(a.PolicyNumber) >= 12

    JOIN

       Agency_policy acp ON a.Policy_ref = acp.Policy_ref

    JOIN

       Agent_policy anp ON a.Policy_ref = anp.Policy_ref

    JOIN

       InsuredAccount_policy iap ON a.Policy_ref = iap.Policy_ref

    JOIN

       TotalPremium_policy tpp ON a.Policy_ref = tpp.Policy_ref

     

),



MaxEffectiveDates AS (

    SELECT

        Policy_ref,

        PolicyNumber,

        MAX(CAST(rp.EffectiveDate AS DATETIME)) AS MaxEffectiveDate,

        Number

    FROM

        RankedPolicies rp

    WHERE

        CAST(rp.EffectiveDate AS DATETIME) <= GETDATE()

    GROUP BY

        PolicyNumber, Policy_ref, Number

),



/*Above CTE is to get Max Date of Transaction Effective Date & it shouldn't be effective in future*/

MaxPolicyRefs AS (

    SELECT

        rp.Policy_ref,

        rp.PolicyNumber,

        rp.Number,

        CAST(rp.EffectiveDate AS DATETIME) AS EffectiveDate,

        ROW_NUMBER() OVER (PARTITION BY rp.PolicyNumber ORDER BY rp.EffectiveDate DESC, rp.Policy_ref DESC) AS rn

    FROM

        RankedPolicies rp

    JOIN MaxEffectiveDates med ON rp.PolicyNumber = med.PolicyNumber

                              AND rp.EffectiveDate = med.MaxEffectiveDate

)



SELECT

        rp.Policy_ref,

        rp.PolicyNumber,

        rp.Prefix,

        rp.TrimmedPolicyNumber,

        rp.PolicyStatus,

        rp.EffectiveDate,

        rp.ExpirationDate,

        rp.Type,

        rp.Status,

        rp.Number,

        rp.AnnualPremium,

        rp.FirstName,

        rp.LastName,

        rp.[Address.City],

        rp.[Address.State],

        rp.[Address.Postalcode],

        rp.[Address.PoBox],

        rp.AgencyCode,

        rp.AgencyName,

        rp.AgentCode,

        rp.AgentLocation,

        rp.BuildingNumber,

        rp.StreetWithoutNumbers,

        rp.[Address.Street]

FROM

    RankedPolicies rp

JOIN MaxPolicyRefs mpr ON rp.Policy_ref = mpr.Policy_ref

WHERE

    mpr.rn = 1  

    AND rp.PolicyNumber IN (

        SELECT PolicyNumber

        FROM [Policy_policy] PP

        WHERE PP.PolicyStatus NOT IN (

        'Policy Cancelled',

        'Renewed',

        'Expired',

        'Renewal-Offered',

        'Policy In Force-Renewal',

        'Reinstatement Request Pending Approval',

        'Application',

        'Rescind Request Pending Approval',

        'Reinstate Initiated',

        'Reinstatement Request Pending Approval',

        'Reinstatement Request Rejected',

        'Reinstatement Request On Hold',

        'Reinstatement Signature Pending',

        'Reinstatement Signature Completed',

        'Reinstatement Initiated - Payment Pending',

        'Reinstatement Initiated - Payment Received',

        'Renewal Expired',

        'Renewal Offered - Payment Pending',

        'Renewal-Offered Expired',

        'Renewal Offered - Pending Approval',

        'Renewal-Offered Initiated'

                )

        AND NOT EXISTS (

    SELECT 1

    FROM [Policy_policy] PP

    WHERE PP.PolicyNumber = rp.PolicyNumber

    AND PP.PolicyStatus = 'Policy Cancelled'

                       )

)

