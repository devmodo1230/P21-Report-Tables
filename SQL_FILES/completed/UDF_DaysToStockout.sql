/****** Object:  UserDefinedFunction [dbo].[UDF_DaysToStockout]    Script Date: 4/22/2025 1:55:33 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE FUNCTION [dbo].[UDF_DaysToStockout] (
	@NetStock DECIMAL(19,8),
	@AvgDailyUsage DECIMAL(19,8),
	@AvgLeadTimeDays DECIMAL(19,8),
	@ReviewCycleDays DECIMAL(19,8))
RETURNS NUMERIC(19,1)
AS 
BEGIN

DECLARE @net_stock DECIMAL(19,8) = @NetStock;
DECLARE @avg_daily_usage DECIMAL(19,8) = @AvgDailyUsage;
DECLARE @avg_lead_time_days DECIMAL(19,8) = @AvgLeadTimeDays;
DECLARE @review_cycle_days DECIMAL(19,8) = @ReviewCycleDays;
/*
	Name: dbo.UDF_DaysToStockout
	Description: This user-defined function calculates the number of days until
	an item stocks out based on the current net stock, average daily usage,
	average lead time days, and review cycle days.
	Created: (2024.04.06 10:01 PM ALP)
	Last Updated: (2024.04.06 10:01 PM ALP)
*/
DECLARE @days_to_stockout NUMERIC(19,4);

SET @days_to_stockout = (ROUND(
	CASE 
		WHEN @avg_daily_usage = 0 THEN 0
		ELSE (@net_stock / @avg_daily_usage) - (@avg_lead_time_days + @review_cycle_days)
	END, 1)
);

RETURN @days_to_stockout

END

GO


