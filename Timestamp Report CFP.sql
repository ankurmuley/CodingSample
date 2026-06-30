Select     
CASE WHEN ia.FirstName = ' ' AND ia.LastName = ' ' THEN ia.DisplayName 
    ELSE ia.FirstName + ' ' + ia.MiddleName + ' ' + ia.LastName 
    END AS [Insured Name],
pv.PolicyNumber AS [Policy Number],
av.Product AS [Product Line],
FORMAT(TRY_CAST(pv.EffectiveDate AS DATETIME), 'MM/dd/yyyy') AS [Eff Date],
MIN(CASE WHEN pshv.NewStatus = 'Quote Indication' THEN TRY_CAST(pshv.ChangedDate AS DATETIME) ELSE NULL END) AS [Quote Indication Date],
MIN(CASE WHEN pshv.NewStatus = 'Submission' then TRY_CAST(pshv.ChangedDate AS DATETIME) ELSE NULL END) AS [Application Submitted Date],
MIN(CASE WHEN pshv.NewStatus = 'Quote Offered' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Quote Offered Date],
MIN(CASE WHEN pshv.NewStatus = 'Bind Request Awaiting UW Review' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Bind Request Date],
MIN(CASE WHEN pshv.NewStatus = 'Application Approved' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Application Approved Date],
MIN(CASE WHEN pshv.NewStatus = 'Submission Declined' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Submission Declined Date],
MIN(CASE WHEN pshv.NewStatus = 'Quote Expired' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Quote Expired Date],
MIN(CASE WHEN pshv.NewStatus = 'Policy In Force' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Policy Inforce Date],
MIN(CASE WHEN pshv.NewStatus = 'Endorsement Initiated' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Endorsement Initiated Date 1],
MIN(CASE WHEN pshv.NewStatus = 'Policy In Force-Endorsed' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Endorsement In-Force Date 1],
MIN(CASE WHEN pshv.NewStatus = 'Cancellation Initiated' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Cancellation Date 1],
MIN(CASE WHEN pshv.NewStatus = 'Policy In Force-ReInstated' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Reinstatement Date 1],
'Version' as type

    FROM 
        Transaction_versions tv
    JOIN InsuredAccount_versions ia ON tv.Policy_ref = ia.Policy_ref
    JOIN Policy_versions pv ON pv.Policy_ref = tv.Policy_ref
    JOIN PolicyStatusHistory_versions pshv ON tv.Policy_ref = pshv.Policy_ref
    JOIN Attributes_versions av ON tv.Policy_ref = av.Policy_ref
WHERE tv.Policy_ref = 'e26bd5ca-402e-4710-b041-88a403fbd723'


GROUP BY ia.FirstName, ia.MiddleName, ia.LastName,
ia.DisplayName,
 pv.PolicyNumber,
 pv.EffectiveDate,
 av.Product

UNION ALL     

Select     
CASE WHEN ia.FirstName = ' ' AND ia.LastName = ' ' THEN ia.DisplayName 
    ELSE ia.FirstName + ' ' + ia.MiddleName + ' ' + ia.LastName 
    END AS [Insured Name],
pv.PolicyNumber AS [Policy Number],
av.Product AS [Product Line],
FORMAT(TRY_CAST(pv.EffectiveDate AS DATETIME), 'MM/dd/yyyy') AS [Eff Date],
MIN(CASE WHEN pshv.NewStatus = 'Quote Indication' THEN TRY_CAST(pshv.ChangedDate AS DATETIME) ELSE NULL END) AS [Quote Indication Date],
MIN(CASE WHEN pshv.NewStatus = 'Submission' then TRY_CAST(pshv.ChangedDate AS DATETIME) ELSE NULL END) AS [Application Submitted Date],
MIN(CASE WHEN pshv.NewStatus = 'Quote Offered' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Quote Offered Date],
MIN(CASE WHEN pshv.NewStatus = 'Bind Request Awaiting UW Review' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Bind Request Date],
MIN(CASE WHEN pshv.NewStatus = 'Application Approved' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Application Approved Date],
MIN(CASE WHEN pshv.NewStatus = 'Submission Declined' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Submission Declined Date],
MIN(CASE WHEN pshv.NewStatus = 'Quote Expired' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Quote Expired Date],
MIN(CASE WHEN pshv.NewStatus = 'Policy In Force' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Policy Inforce Date],
MIN(CASE WHEN pshv.NewStatus = 'Endorsement Initiated' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Endorsement Initiated Date 1],
MIN(CASE WHEN pshv.NewStatus = 'Policy In Force-Endorsed' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Endorsement In-Force Date 1],
MIN(CASE WHEN pshv.NewStatus = 'Cancellation Initiated' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Cancellation Date 1],
MIN(CASE WHEN pshv.NewStatus = 'Policy In Force-ReInstated' then TRY_CAST(pshv.ChangedDate  AS DATETIME) ELSE NULL END) AS [Reinstatement Date 1],
'Policy' as type

    FROM 
        Transaction_policy tv
    JOIN InsuredAccount_policy ia ON tv.Policy_ref = ia.Policy_ref
    JOIN Policy_policy pv ON pv.Policy_ref = tv.Policy_ref
    JOIN PolicyStatusHistory_policy pshv ON tv.Policy_ref = pshv.Policy_ref
    JOIN Attributes_policy av ON tv.Policy_ref = av.Policy_ref
--WHERE tv.Policy_ref = 'c75b7c7e-8201-48eb-9e5c-b122426988e1'

GROUP BY ia.FirstName, ia.MiddleName, ia.LastName,
ia.DisplayName,
 pv.PolicyNumber,
 pv.EffectiveDate,
 av.Product

