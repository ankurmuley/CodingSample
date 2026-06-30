CREATE OR ALTER VIEW [dbo].[Vw_CAT_Reinsurance] AS
WITH RankedPolicies AS (
    SELECT DISTINCT
        a.Policy_ref,
        b.PolicyNumber,
        b.PolicyStatus,
        CASE 
            WHEN a.Status = 'Voided' AND a.Type IN ('Cancellation', 'Reinstate') THEN 'Voided'
            ELSE a.Status
        END AS status,
        rvv.Status AS VehicleStatus,
        a.Type,
        a.Number,
        rvpf.Premium,  
        rvpf.Description,  
        CASE 
            WHEN rvra.CollDeductible = 'NoCov' THEN 0 
            ELSE rvra.CollDeductible 
        END AS CollDeductible,  
        CASE 
            WHEN rvra.OTCDeductible = 'NoCov' THEN 0 
            ELSE rvra.OTCDeductible 
        END AS OTCDeductible,    
        rvra.Year,               
        av.Code,               
        CAST(a.EffectiveDate AS DATETIME) AS EffectiveDate, 
        g.County,              
        g.City,                
        g.Postalcode,          
        g.Street,
        rvra.UnitId,
        rvra.IsNonOwnerPolicy,
        rvv.IsDeleted,
        rvra.SymbolOTC,
        rvra.SymbolColl
    FROM [Transaction_versions] a
    JOIN [Policy_versions] b 
        ON a.Policy_ref = b.Policy_ref 
       AND LEN(b.PolicyNumber) >= 13 
    JOIN (
        SELECT DISTINCT
            rvv.Policy_ref,
            rvv.UnitId,
            rvv.Status,
            rvv.IsNewlyAdded,
            rvv.IsDeleted
        FROM [Risks_Vehicles_versions] rvv
        GROUP BY 
            rvv.Policy_ref,
            rvv.UnitId,
            rvv.Status,
            rvv.IsNewlyAdded,
            rvv.IsDeleted
    ) AS rvv 
        ON rvv.Policy_ref = b.Policy_ref 
       AND rvv.Status = 'Valid' 
       AND rvv.IsDeleted = '0'
    JOIN [Risks_Vehicles_PremiumFactors_versions] rvpf 
        ON rvv.Policy_ref = rvpf.Policy_ref 
       AND rvv.UnitId = rvpf.UnitId 
    JOIN [Risks_Vehicles_VehicleRiskAttributes_versions] rvra 
        ON rvv.Policy_ref = rvra.Policy_ref 
       AND rvpf.UnitId = rvra.UnitId
    JOIN [Agent_versions] av 
        ON a.Policy_ref = av.Policy_ref  
    JOIN [Risks_Vehicles_VehicleRiskAttribute_PrimaryGaragingLocation_versions] g 
        ON rvpf.Policy_ref = g.Policy_ref 
       AND rvpf.UnitId = g.UnitId
    WHERE 
        (
            a.Status = 'Committed' 
            OR (
                a.Status = 'Voided' 
                AND a.Type IN ('Cancellation', 'Reinstate')
            )
        )
        AND ROUND(TRY_CAST(rvpf.Premium AS FLOAT), 2) <> 0                     
        -- AND b.PolicyStatus NOT IN (
        --     'Policy Cancelled',
        --     'Renewed',
        --     'Expired',
        --     'Renewal-Offered',
        --     'Policy In Force-Renewal'
        -- )   
        AND rvpf.Description IN ('COMP', 'COLL') 
        AND rvra.OTCDeductible <> 'NoCov'   
),

MaxEffectiveDates AS (
    SELECT 
        Policy_ref,
        PolicyNumber,
        MAX(CAST(rp.EffectiveDate AS DATETIME)) AS MaxEffectiveDate,
        Number
    FROM RankedPolicies rp
    WHERE CAST(rp.EffectiveDate AS DATETIME) <= GETDATE()
    GROUP BY 
        PolicyNumber, 
        Policy_ref, 
        Number
)
,

MaxPolicyRefs AS (
    SELECT 
        rp.Policy_ref,
        rp.PolicyNumber,
        rp.Number,
        CAST(rp.EffectiveDate AS DATETIME) AS EffectiveDate, 
        ROW_NUMBER() OVER (
            PARTITION BY rp.PolicyNumber 
            ORDER BY rp.EffectiveDate DESC, rp.Policy_ref DESC
        ) AS rn
    FROM RankedPolicies rp
    JOIN MaxEffectiveDates med 
        ON rp.PolicyNumber = med.PolicyNumber 
       AND rp.EffectiveDate = med.MaxEffectiveDate 
)--,

--FinalRows AS (
    SELECT
        rp.Policy_ref,
        rp.PolicyNumber,
        rp.PolicyStatus,
        rp.status,
        rp.VehicleStatus,
        rp.Type,          
        rp.Premium,
        rp.Description,
        rp.CollDeductible,  
        rp.OTCDeductible,   
        rp.Year,            
        rp.Code,            
        rp.EffectiveDate,   
        rp.County,          
        rp.City,            
        rp.Postalcode,      
        rp.UnitId,
        rp.IsNonOwnerPolicy,
        rp.Number,
        LEFT(rp.Street, CHARINDEX(' ', rp.Street + ' ') - 1) AS StreetNumber,
        LTRIM(SUBSTRING(rp.Street, CHARINDEX(' ', rp.Street + ' ') + 1, LEN(rp.Street))) AS TrimmedStreet,
        rp.IsDeleted,
        rp.SymbolOTC,
        rp.SymbolColl
    FROM RankedPolicies rp
    JOIN MaxPolicyRefs mpr 
        ON rp.Policy_ref = mpr.Policy_ref
    WHERE 
        mpr.rn = 1  
        AND EXISTS (
            SELECT 1
            FROM [Attributes_versions] av
            WHERE av.Policy_ref = rp.Policy_ref
        )
        AND rp.PolicyNumber IN (
            SELECT PP.PolicyNumber 
            FROM [Policy_policy] PP
            JOIN [Attributes_policy] AP 
                ON PP.Policy_ref = AP.Policy_ref
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
            AND AP.IsNonOwnerPolicy <> '1'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM [Policy_policy] PP
            WHERE PP.PolicyNumber = rp.PolicyNumber
              AND PP.PolicyStatus = 'Policy Cancelled'
        )
)

SELECT
    Policy_ref,
    PolicyNumber,
    PolicyStatus,
    status,
    VehicleStatus,
    Type,

    SUM(TRY_CAST(Premium AS DECIMAL(18,2))) AS Premium,

    CASE 
        WHEN COUNT(DISTINCT Description) > 1 THEN 'COMP+COLL'
        ELSE MAX(Description)
    END AS Description,

    MAX(TRY_CAST(CollDeductible AS DECIMAL(18,2))) AS CollDeductible,
    MAX(TRY_CAST(OTCDeductible AS DECIMAL(18,2))) AS OTCDeductible,

    Year,            
    Code,            
    EffectiveDate,   
    County,          
    City,            
    Postalcode,      
    UnitId,
    UnitId AS Unit,
    IsNonOwnerPolicy,
    Number,
    StreetNumber,
    TrimmedStreet,
    IsDeleted,
    SymbolOTC,
    SymbolColl
FROM FinalRows
GROUP BY
    Policy_ref,
    PolicyNumber,
    PolicyStatus,
    status,
    VehicleStatus,
    Type,
    Year,
    Code,
    EffectiveDate,
    County,
    City,
    Postalcode,
    UnitId,
    IsNonOwnerPolicy,
    Number,
    StreetNumber,
    TrimmedStreet,
    IsDeleted,
    SymbolOTC,
    SymbolColl;