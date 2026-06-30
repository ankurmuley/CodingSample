--drop view VW_ZeroBalanceReport_MH
create view VW_ZeroBalanceReport_MH
as
Select  'KGEMMHCA' AS [Product],  
last_p_term.POL_NUMBER AS [Policy Number],
last_p_term.POL_ACCOUNT as [Account Number],
CONVERT(varchar, (ISNULL(last_p_term.POL_EFFECTIVE_DATE, CAST(last_p_term.POL_EFFECTIVE_DATE AS DATE))), 101) AS [Effective Date],
last_pol_interface.POLICY_INTERFACE_INSURED_FULLNAME as [Insured Name],
fq.PayPlan AS [Pay Plan],
CASE last_pol_interface.POLICY_INTERFACE_STATUS_REASON WHEN 5 THEN 'Renewal' ELSE 'New' END as [New/Renewal],
ACCOUNTP_BILLING_STATUS_TEXT as [Policy Status],
balance.CurrentBalance as [Current Balance],
ISNULL(suspense.SUSPENSE_BALANCE,0) as [Suspense Amount]
FROM (SELECT 1 AS dummy) AS src 
OUTER APPLY (
		SELECT POL_NUMBER, POL_EFFECTIVE_DATE, POL_PAY_PLAN, POL_ACCOUNT
		--, POL_BILLING_STATUS_TEXT
		FROM (SELECT POL_NUMBER,POL_ACCOUNT, POL_EFFECTIVE_DATE, POL_PAY_PLAN, 
					 --POL_BILLING_STATUS_TEXT =  ( select top 1 TABLED_DESIGNATION from gn2_tabled where tabled_name = 'DBPOLBILLSTAT' and tabled_lingo = 2 and tabled_code = POL_BILLING_STATUS ),  
					 ROW_NUMBER() OVER (PARTITION BY p.POL_NUMBER ORDER BY p.POL_EFFECTIVE_DATE DESC) AS rn
				FROM PR1_POLICY p
			 ) t
		WHERE t.rn = 1
	) last_p_term
OUTER APPLY (
		SELECT TOP 1 POLICY_INTERFACE_AGENTMASTER_CODE, POLICY_INTERFACE_INSURED_FULLNAME,POLICY_INTERFACE_STATUS_REASON
		FROM UW1_POLICY_INTERFACE
		WHERE last_p_term.POL_NUMBER = POLICY_INTERFACE_POLICY_NUM 
			  AND last_p_term.POL_EFFECTIVE_DATE = POLICY_INTERFACE_EFFECTIVE_DATE
		ORDER BY POLICY_INTERFACE_ENDORSEMENT_DATE DESC, POLICY_INTERFACE_ENDORSEMENT DESC
	) last_pol_interface
OUTER APPLY (
		SELECT TOP 1 ACCOUNTP_BILLING_STATUS,
		ACCOUNTP_BILLING_STATUS_TEXT = ( select top 1 TABLED_DESIGNATION from gn2_tabled where tabled_name = 'DBPOLBILLSTAT' and tabled_lingo = 2 and tabled_code = ACCOUNTP_BILLING_STATUS)
		FROM PR1_ACCOUNTP
		WHERE last_p_term.POL_ACCOUNT = ACCOUNTP_NUMBER
		) account_interface
OUTER APPLY
	 (SELECT FREQUENCY_DESCRIPTION as PayPlan , FREQUENCY_CODE as PayPlanCode
     FROM [dbo].[PR2_FREQUENCY] 
     WHERE FREQUENCY_CODE = last_p_term.POL_PAY_PLAN
	 ) as fq
OUTER APPLY
	(Select ISNULL((select dbo.F_GET_ACCOUNT_BALANCE(last_p_term.POL_ACCOUNT)),0) as CurrentBalance) as balance
OUTER APPLY
	(select top 1 (sus.SUSPENSE_BALANCE * -1) as SUSPENSE_BALANCE
		from PR1_SUSPENSE sus
		where sus.SUSPENSE_ACC_NUM = last_p_term.POL_ACCOUNT
		order by sus.SUSPENSE_SEQUENCE desc
	) as suspense
WHERE fq.PayPlanCode != 1 -- not 'Full-Pay'
	       and balance.CurrentBalance <=0
	       and suspense.SUSPENSE_BALANCE < 0
