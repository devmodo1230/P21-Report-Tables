USE [SheppardLive]
GO

/****** Object:  UserDefinedFunction [dbo].[UDF_AvgLeadTimeDays]    Script Date: 6/30/2023 9:34:16 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/*
	A UDF to calculate the average lead time days for an item with weighting on the most recent POs.
	--SELECT dbo.UDF_AvgLeadTimeDays('SHEPENT', 1001, 7465);
	--GRANT EXECUTE ON OBJECT::dbo.UDF_AvgLeadTimeDays TO SheppardSpecialReports;
*/
ALTER FUNCTION [dbo].[UDF_AvgLeadTimeDays] (@company_id VARCHAR(8), @location_id DECIMAL(19,0), @inv_mast_uid INT)
RETURNS NUMERIC(19,8)
AS BEGIN

	DECLARE @avgLeadTime NUMERIC(19,8) = 14;
	DECLARE @t_avg_lead_time_days AS TABLE
	(
		row_num INT,
		lead_time_days DECIMAL(19,0)
	);

	INSERT INTO @t_avg_lead_time_days (row_num, lead_time_days)
	SELECT row_rank, lead_time_days
	FROM (
		SELECT T1.po_date, T1.date_received, DATEDIFF(d, T1.po_date, T1.date_received) AS 'lead_time_days',
			RANK() OVER(ORDER BY T1.date_received DESC) AS 'row_rank'
		FROM (
			SELECT H.po_no, H.order_date AS 'po_date', V.date_created AS 'date_received',
				RANK() OVER(PARTITION BY H.po_no ORDER BY V.date_created DESC) AS 'po_line_count'
			FROM p21_view_inventory_receipts_line V
				INNER JOIN p21_view_inventory_receipts_hdr R 
					ON V.receipt_number = R.receipt_number
				INNER JOIN p21_view_po_hdr H
					ON R.po_number = H.po_no
				INNER JOIN p21_view_po_line L 
					ON (R.po_number = L.po_no AND V.po_line_number = L.line_no)
			WHERE COALESCE(R.delete_flag, 'N') = 'N' 
				AND H.po_type <> 'Q'
				AND V.inv_mast_uid = @inv_mast_uid
				AND H.company_no = @company_id
				AND H.location_id = @location_id
		) T1
		--Avoids the situation where an item might be received 2x in one day on the same PO.
		WHERE T1.po_line_count = 1
	) T2
	WHERE T2.row_rank <= 5
	ORDER BY T2.date_received DESC;

	DECLARE @max_row_num DECIMAL(19,4) = (SELECT MAX(row_num) FROM @t_avg_lead_time_days);
	DECLARE @sum_row_num DECIMAL(19,4);
	
	IF @max_row_num > 0
	BEGIN
		--Weight the lead_time_days based on its position in the list.
		SET @sum_row_num = (SELECT SUM(row_num) FROM @t_avg_lead_time_days);
	
		--The / 20 factor lessens the impact of older POs than newer.
		SET @avgLeadTime = (SELECT SUM(lead_time_days * (1 + (@max_row_num / row_num) / 20)) / @max_row_num
		FROM @t_avg_lead_time_days);
		IF @avgLeadTime = 0
		BEGIN
			SET @avgLeadTime = 14;
		END;
	END;
	
	RETURN @avgLeadTime
END

GO
