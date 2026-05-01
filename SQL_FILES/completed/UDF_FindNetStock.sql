USE [SheppardLive]
GO

/****** Object:  UserDefinedFunction [dbo].[UDF_FindNetStock]    Script Date: 08/12/2016 18:31:26 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER FUNCTION [dbo].[UDF_FindNetStock] (@company_id VARCHAR(8), @location_id DECIMAL(19,0), @inv_mast_uid INT)
RETURNS NUMERIC(19,8)
AS BEGIN

	DECLARE @netStock NUMERIC(19,8)
	
	/*
		2023.06.28 ALP
		Removed COALESCE(L.protected_stock_qty, 0) from the @netStock calc since it seems to have invalid data.

		2023.09.16 ALP
		Added the CASE logic to the qty_in_transit because it appears that some double dipping happens when the current on hand and allocated is >= 0.
	*/
	SET @netStock = (SELECT L.qty_on_hand - L.qty_allocated - L.qty_backordered + L.order_quantity + L.qty_in_process - 
	  (CASE WHEN L.qty_on_hand - L.qty_allocated >= 0 THEN 0 ELSE COALESCE(L.qty_in_transit, 0) END) - COALESCE(L.qty_reserved_due_in, 0)
	FROM p21_view_inv_loc L
	WHERE L.company_id = @company_id
	 AND L.location_id = @location_id
	 AND L.inv_mast_uid = @inv_mast_uid)
	
	RETURN @netStock
END

GO


