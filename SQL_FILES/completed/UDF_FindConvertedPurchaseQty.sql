USE [SheppardLive]
GO

/****** Object:  UserDefinedFunction [dbo].[UDF_FindConvertedPurchaseQty]    Script Date: 6/16/2023 12:18:12 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

--SELECT dbo.UDF_FindConvertedPurchaseQty(123456, 58.125);
ALTER FUNCTION [dbo].UDF_FindConvertedPurchaseQty (
	@invMastUID INT,
	@nonConvertedQty DECIMAL(19,8))
RETURNS NUMERIC(19,8)
AS 
BEGIN

DECLARE @inv_mast_uid INT = @invMastUID;
DECLARE @non_converted_qty DECIMAL(19,8) = @nonConvertedQty
/*
	Name: dbo.UDF_FindConvertedPurchaseQty
	Description: This user-defined function calculates the adjusted order quantity based
	on the conversion factor set in Item Maintenance.
	Inputs:	inv_mast_uid from any number of tables
			non_converted_qty is the raw value that needs to be converted
	This PROC only works with purchase quantity conversions though could be easily
	extended to work with sales quantity conversions.
	Created: 2023.06.15 ALP
	Last Updated: 2023.06.15 ALP
*/
DECLARE @converted_qty NUMERIC(19,8)

SET @converted_qty = 
	(SELECT 
		ROUND(CASE 
			WHEN round_type = 'S' THEN ROUND(decimal_order_qty, 0)
			WHEN round_type = 'D' THEN ROUND(decimal_order_qty - 0.5, 0)
			WHEN round_type = 'U' THEN ROUND(decimal_order_qty + 0.5, 0)
			ELSE decimal_order_qty
		END * to_unit_size / from_unit_size, 8) AS 'converted_order_qty'
	FROM (
		SELECT V.from_uom, FU.unit_size AS 'from_unit_size', 
			V.to_uom, TU.unit_size AS 'to_unit_size',
			V.[round] AS 'round_type',
			@non_converted_qty * FU.unit_size / TU.unit_size AS 'decimal_order_qty'
		FROM p21_view_item_conversion V
			--The From Unit
			INNER JOIN p21_view_item_uom FU ON
				(V.inv_mast_uid = FU.inv_mast_uid
					AND V.from_uom = FU.unit_of_measure)
			--The To Unit
			INNER JOIN p21_view_item_uom TU ON
				(V.inv_mast_uid = TU.inv_mast_uid
					AND V.to_uom = TU.unit_of_measure)
		WHERE V.inv_mast_uid = @inv_mast_uid
			AND V.convert_at_po = 'Y'
			AND V.delete_flag = 'N'
	) T)

RETURN COALESCE(@converted_qty, @non_converted_qty)

END

GO