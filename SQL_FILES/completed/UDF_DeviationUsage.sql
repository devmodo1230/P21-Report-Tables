/****** Object:  UserDefinedFunction [dbo].[UDF_DeviationUsage]    Script Date: 4/22/2025 1:55:40 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


--GRANT EXECUTE ON OBJECT::dbo.UDF_DeviationUsage TO SheppardSpecialReports;

CREATE FUNCTION [dbo].[UDF_DeviationUsage] (
	@companyID VARCHAR(8),
	@locationID INT,
	@invMastUID INT)
RETURNS DECIMAL(19,0)
AS 
BEGIN

DECLARE @company_id VARCHAR(8) = @companyID;
DECLARE @location_id INT = @locationID;
DECLARE @inv_mast_uid INT = @invMastUID;
DECLARE @result DECIMAL(19,0);

/*
	This function calculates the average usage + standard deviation for an item in order to more accurately scale the 
	forecast of the item when attempting to meet high minimum orders or long lead times.
*/

SET @result = (
SELECT ROUND(0.5 + CASE WHEN prior_rows_avg >= with_curr_rows_avg THEN prior_rows_avg ELSE with_curr_rows_avg END +
	CASE WHEN prior_rows_avg >= with_curr_rows_avg THEN prior_rows_stdev ELSE with_curr_rows_stdev END, 0) AS 'dev_usage'
FROM (
	SELECT *,
		COALESCE(AVG(T1.inv_period_usage) OVER(ORDER BY T1.computed_year_period ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING), 0) AS 'prior_rows_avg',
		COALESCE(AVG(T1.inv_period_usage) OVER(ORDER BY T1.computed_year_period ROWS BETWEEN 2 PRECEDING AND 0 PRECEDING), 0) AS 'with_curr_rows_avg',
		STDEV(T1.inv_period_usage) OVER(ORDER BY T1.computed_year_period ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING) AS 'prior_rows_stdev',
		STDEV(T1.inv_period_usage) OVER(ORDER BY T1.computed_year_period ROWS BETWEEN 2 PRECEDING AND 0 PRECEDING) AS 'with_curr_rows_stdev'
	FROM (
		SELECT D.computed_year_period, U.inv_period_usage, COALESCE(L.purchase_class , 'C') AS 'purchase_class',
			ROW_NUMBER() OVER(ORDER BY D.computed_year_period DESC) AS 'row_num'
		FROM p21_view_inv_period_usage U
			INNER JOIN p21_view_demand_period D ON U.demand_period_uid = D.demand_period_uid 
			INNER JOIN p21_view_inv_loc L ON 
				(U.location_id = L.location_id 
					AND U.inv_mast_uid = L.inv_mast_uid
					AND D.company_id = L.company_id)
		WHERE U.inv_mast_uid = @inv_mast_uid
			AND U.location_id = @location_id
			AND D.company_id = @company_id
			AND D.computed_year_period >= 
				CASE 
					WHEN COALESCE(L.purchase_class, 'C') IN ('A', 'B') THEN dbo.UDF_PriorPeriod(-3)
					WHEN COALESCE(L.purchase_class, 'C') = 'C' THEN dbo.UDF_PriorPeriod(-4)
					WHEN COALESCE(L.purchase_class, 'C') = 'D' THEN dbo.UDF_PriorPeriod(-5)
					ELSE dbo.UDF_PriorPeriod(-3)
				END
			AND U.inv_period_usage > 0
	) T1
) T2
WHERE T2.row_num = 1);

RETURN @result

END;
GO


