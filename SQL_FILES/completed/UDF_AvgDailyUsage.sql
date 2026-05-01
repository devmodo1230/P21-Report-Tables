USE [P21]
GO

/****** Object:  UserDefinedFunction [dbo].[UDF_AvgDailyUsage]    Script Date: 1/12/2018 4:21:04 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[UDF_AvgDailyUsage] (@company_id VARCHAR(8), @location_id DECIMAL(19,0), @inv_mast_uid INT)
RETURNS NUMERIC(19,4)
AS 
BEGIN

/*
	Name: dbo.UDF_AvgDailyUsage
	Description: This user-defined function calculates the average daily usage based
	 on actual usage for the most recently completed period or the current period
	 depending on which is greater. It takes into consideration the number of work
	 days for the company being reviewed.
	Created: (2016.05.19 12:31 PM ALP)
	Last Updated: (2016.05.19 12:31 PM ALP)
*/
DECLARE @avg_daily_usage NUMERIC(19,4)

SET @avg_daily_usage = 
(SELECT ROUND(CASE WHEN previous_usage / dbo.UDF_WorkingDays(@company_id, CONVERT(VARCHAR(25),DATEADD(dd,-(DAY(GETDATE())),GETDATE()),101)) 
   > current_usage / dbo.UDF_WorkingDays(@company_id, GETDATE())
  THEN previous_usage / dbo.UDF_WorkingDays(@company_id, CONVERT(VARCHAR(25),DATEADD(dd,-(DAY(GETDATE())),GETDATE()),101))
  ELSE current_usage / dbo.UDF_WorkingDays(@company_id, GETDATE()) 
 END, 4) AS 'avg_daily_usage' 
FROM
(
	SELECT D.company_id, U.location_id, U.inv_mast_uid,
	 SUM(CASE WHEN D.computed_year_period = dbo.icon_prior_period('-1') THEN U.inv_period_usage ELSE 0 END) AS 'previous_usage',
	 SUM(CASE WHEN D.computed_year_period = dbo.icon_prior_period('-0') THEN U.inv_period_usage ELSE 0 END) AS 'current_usage'
	FROM p21_view_inv_period_usage U
	 INNER JOIN p21_view_demand_period D ON U.demand_period_uid = D.demand_period_uid
	WHERE D.computed_year_period >= dbo.icon_prior_period('-1')
	 AND D.company_id = @company_id
	 AND U.location_id = @location_id
	 AND U.inv_mast_uid = @inv_mast_uid
	GROUP BY D.company_id, U.location_id, U.inv_mast_uid
) tmp)

RETURN @avg_daily_usage

END

GO


