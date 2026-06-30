--Tabled Definition Header
select * from gn2_tablem
--Tabled Definitions
select * from gn2_tabled where TABLED_name ='DBPOLBILLSTAT' and TABLED_LINGO=2

select * from UW2_STATUS_TYPE

--Pay plans
select * from PR2_FREQUENCY
--Pay Plan Installments
select * from PR2_FREQUENCYI

--Statement status and status reason
select * from [dbo].[PR2_ACCOUNT_STATUS]
select * from [dbo].[PR2_ACCOUNT_STATUS_TYPE]

--Account creating (Downpayment process)
select * from pr1_accountc

--Account Header (Main table)
select * from pr1_accountd 

--Account Policy Link (policy header)
select * from [dbo].[PR1_ACCOUNTP]

--Policy Terms
select * from PR1_POLICY

--Account Address info
select * from pr1_accounti

--account with latest POLICY TERM
select * from pr1_accountd 
join [dbo].[PR1_ACCOUNTP] on accountd_number = accountp_number
outer apply(
	select top 1 * from PR1_POLICY 
	where pol_number = ACCOUNTP_POLICY_NUM
	order by POL_EFFECTIVE_DATE desc
) last_term


--Policy transactions (New Business, Renewal, endorsement, Cancellation, Reinstate)
select * from [dbo].[UW1_POLICY_INTERFACE]


--Agents
select * from GN2_AGENT


