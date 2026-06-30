
/*
Report : Commission Transaction 

Product	'HSKIMHOCA'
State	
Policy Number	
Insured Name	
Eff Date	
Agency	
New/Renewal	
Pay Plan	
Transaction Date
Transaction Type	
Premium
Commission %	Commission Amount	
Amount Paid	Payment Date

*/

select 


'Product' =	'HSKIMHOCA'
,'State' = STATE_SECOND_DESC
,'Policy Number' = COMMISSIONS_POLICYNUMBER
,'Insured Name' = COMMISSIONS_INSURED_NAME
,'Eff Date' = COMMISSIONS_EFFECTIVE_DATE
,'Agency' = RTRIM(AGENT_NAME1 + ' ' + AGENT_NAME2)
,'New/Renewal' = case when isnull(IsRenewed,0) = 1 then 'Renewal' else 'New' end	
,'Pay Plan' = FREQUENCY_DESCRIPTION

,'Transaction Date' = '?????'
,'Transaction Type' = '?????'

,'Premium' = COMMISSIONS_PAID_PREMIUM
,'Commission %' = COMMISSIONS_COMMISSION_PERCENT
,'Commission Amount' = COMMISSIONS_COMMISSION_AMOUNT
,'Amount Paid' = TotalPayments
,'Payment Date' = COMMISSIONS_DATE_PAID

--select *
from [dbo].[PR1_COMMISSIONS]
join pr1_accountd on accountd_number =  COMMISSIONS_ACCOUNTNUMBER
join gn2_state on state_code = AccountD__BRANCH
join GN2_AGENT on agent_code = COMMISSIONS_AGENT_CODE
join PR1_POLICY on POL_NUMBER = COMMISSIONS_POLICYNUMBER and POL_EFFECTIVE_DATE = COMMISSIONS_EFFECTIVE_DATE
join PR2_FREQUENCY on FREQUENCY_CODE = POL_PAY_PLAN
outer apply(
	select top 1 IsRenewed = 1
	from UW1_POLICY_INTERFACE
	where POLICY_INTERFACE_POLICY_NUM = COMMISSIONS_POLICYNUMBER
	and POLICY_INTERFACE_STATUS = 3  and POLICY_INTERFACE_STATUS_REASON = 5 --Renewal
) renewal_tran
outer apply(
	select  TotalPayments = SUM(BILLABD_AMOUNT_PAID)
	from PR1_BILLABD 
	where 1=1
	and BILLABD_BATCH_TYPE in('ACH','LB','ET','CFR','EPX','MTV','ORS','ASW','CAP','RDS')
	and BILLABD_UPDATED = 1
	and BILLABD_ACCOUNTING_DATE = COMMISSIONS_DATE_PAID
	and BILLABD_ACCOUNT_NUMBER = COMMISSIONS_ACCOUNTNUMBER
) payments

