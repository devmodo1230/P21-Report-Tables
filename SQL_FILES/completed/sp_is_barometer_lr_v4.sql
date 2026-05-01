SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[sp_is_barometer_lr]
	@start_location_id DECIMAL(19,0),
	@end_location_id DECIMAL(19,0),
	@company_id VARCHAR(10)
WITH ENCRYPTION
AS

SET NOCOUNT ON;
/*

DECLARE @start_location_id DECIMAL(19,0)
DECLARE @end_location_id DECIMAL(19,0)
DECLARE @company_id VARCHAR(10)

SET @start_location_id = 1001
SET @end_location_id = 1003
SET @company_id = 'SHEPENT'
*/
/*
	*****SUPPLIER PURCHASE BAROMETER*****
	This SQL generates a report that shows, realtime, how close a particular line is to requiring
	a purchase order.
	
	This version works with multiple locations at a time in a non-RDC environment. The RDC
	version is another barometer to be developed later (barometer_rdc).
*/

/*
	Set up the table to hold summary information for each supplier.
*/
DECLARE @tbl_summary_info TABLE
(
	location_id DECIMAL(19,0),
	supplier_id VARCHAR(10),
	value_to_buy NUMERIC(19,4),
	units_to_buy NUMERIC(19,4),
	weight_to_buy NUMERIC(19,4),
	volume_to_buy NUMERIC(19,4)
);

DECLARE @tbl_results TABLE
(
	location_id DECIMAL(19,0),
	supplier_id DECIMAL(19,0),
	supplier_name VARCHAR(50), 
	buyer_name VARCHAR(100),
	last_po_date DATETIME,
	avg_po_days NUMERIC(19,2),
	moct VARCHAR(30), --Minimum Order Control Type
	mocv NUMERIC(19,4), --Minimum Order Control Value
	fct VARCHAR(30), --Freight Control Type
	fcv NUMERIC(19,4), --Freight Control Value
	order_value NUMERIC(19,4),
	freight_value NUMERIC(19,4),
	control_type VARCHAR(30),
	target_value NUMERIC(19,4),
	actual_value NUMERIC(19,4),
	pct_of_order NUMERIC(19,4),
	est_po_date DATETIME,
	est_arrival_date DATETIME
);
/*
	Set up the CTE_inventory common table expression and gather item information into it.
	3/2/22: Discovered an issue with the code where non-stock items with a min and/or max artificially
			inflate the various values to buy even if the net stock is zero. The values need to consider
			net stock only when the item is non-stock.
	5/6/23: I think this is still an issue, but going the other direction now. Items with a negative net stock
			are negative in the CTE_inventory. That might be a problem.
*/ 
WITH CTE_inventory(location_id, inv_mast_uid, supplier_id, value_at_max, value_at_min, value_at_net_stock,
	weight_at_max, weight_at_min, weight_at_net_stock, units_at_max, units_at_min, units_at_net_stock,
	volume_at_max, volume_at_min, volume_at_net_stock)
AS
(
	SELECT L.location_id, M.inv_mast_uid, S.supplier_id, 
		--The quantity term for each value has to be wrapped as follows:
			--dbo.UDF_FindConvertedPurchaseQty(inv_mast_uid, qty) to determine the true qty.
		--value @ max
		dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
			CASE WHEN L.stockable = 'N' 
				THEN dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid) 
				ELSE L.inv_max 
			END) * 
		CASE WHEN L.moving_average_cost < S.cost / M.purchase_pricing_unit_size 
			THEN S.cost / M.purchase_pricing_unit_size ELSE L.moving_average_cost 
		END, 
		--value @ min
		dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid,
			CASE WHEN L.stockable = 'N' 
				THEN dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid) 
				ELSE L.inv_min 
			END) * 
		CASE WHEN L.moving_average_cost < S.cost / M.purchase_pricing_unit_size 
			THEN S.cost / M.purchase_pricing_unit_size ELSE L.moving_average_cost 
		END, 
		--value @ net stock
		CASE 
			WHEN L.moving_average_cost < S.cost / M.purchase_pricing_unit_size 
				THEN S.cost / M.purchase_pricing_unit_size 
			ELSE L.moving_average_cost 
		END * 
			dbo.UDF_FindConvertedPurchaseQty(
				M.inv_mast_uid, 
				dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid)
			), 
		--weight @ max and weight @ min
		dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
		CASE WHEN L.stockable = 'N' 
			THEN dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid) 
			ELSE L.inv_max
		END) * M.purchasing_weight, 
		dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
		CASE WHEN L.stockable = 'N' 
			THEN dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid) 
			ELSE L.inv_min
		END) * M.purchasing_weight, 
		--weight @ net stock
		M.purchasing_weight * 
		dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
		dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid)), 
		--units @ max, units @ min
		dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
		CASE WHEN L.stockable = 'N' 
			THEN dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid) 
			ELSE L.inv_max
		END) / U.unit_size, 
		dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
		CASE WHEN L.stockable = 'N' 
			THEN dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid) 
			ELSE L.inv_min
		END) / U.unit_size, 
		--units @ net stock
		dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
			dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid)) / U.unit_size,
		--volume @ max, volume @ min
		COALESCE(M.cube * 
			dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
				CASE WHEN L.stockable = 'N' 
					THEN dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid) 
					ELSE L.inv_max 
				END),
		0), 
		COALESCE(M.cube * 
		dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
			CASE WHEN L.stockable = 'N' 
				THEN dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid) 
				ELSE L.inv_min
			END),
		0),
		--volume @ net stock
		COALESCE(M.cube * 
			dbo.UDF_FindConvertedPurchaseQty(M.inv_mast_uid, 
				dbo.UDF_FindNetStock(@company_id, L.location_id, M.inv_mast_uid)), 0) 
	FROM p21_view_inv_mast M
		INNER JOIN p21_view_inv_loc L ON M.inv_mast_uid = L.inv_mast_uid
		INNER JOIN p21_view_inventory_supplier S ON M.inv_mast_uid = S.inv_mast_uid
		INNER JOIN p21_view_inventory_supplier_x_loc W 
			ON (S.inventory_supplier_uid = W.inventory_supplier_uid AND L.location_id = W.location_id)
		INNER JOIN p21_view_item_uom U 
			ON (M.inv_mast_uid = U.inv_mast_uid AND U.unit_of_measure = M.default_purchasing_unit)
	WHERE M.delete_flag = 'N'
		AND W.primary_supplier = 'Y'
		AND (L.stockable = 'Y' OR L.qty_backordered <> 0)
		AND L.location_id >= @start_location_id
		AND L.location_id <= @end_location_id
		AND L.company_id = @company_id
)
--Works to here.
--Update the supplier summary table set up above.
INSERT INTO @tbl_summary_info (location_id, supplier_id, value_to_buy, units_to_buy, weight_to_buy, volume_to_buy)
SELECT location_id, CAST(supplier_id AS DECIMAL(19,0)) AS 'supplier_id', 
	--Calculate value_to_buy; only buy if the value_at_net_stock is <= value_at_min
	--2023.05.06 We're not handling the case where the net stock is less than zero.
	SUM(CASE 
			WHEN value_at_net_stock < 0 
				THEN ABS(value_at_net_stock)
			WHEN value_at_max - value_at_net_stock < 0 OR value_at_min < value_at_net_stock
				THEN 0 
			ELSE value_at_max - value_at_net_stock 
		END), 
	--Calculate units_to_buy; only buy if the units_at_net_stock is <= units_at_min
	SUM(CASE
			WHEN units_at_net_stock < 0 
				THEN ABS(units_at_net_stock) 
			WHEN units_at_max - units_at_net_stock < 0 OR units_at_min < units_at_net_stock
				THEN 0 
			ELSE units_at_max - units_at_net_stock 
		END), 
	--Calculate weight_to_buy; only buy if the weight_at_net_stock is <= weight_at_min
	SUM(CASE 
			WHEN weight_at_net_stock < 0 
				THEN ABS(weight_at_net_stock)
			WHEN weight_at_max - weight_at_net_stock < 0 OR weight_at_min < weight_at_net_stock
				THEN 0 
			ELSE weight_at_max - weight_at_net_stock 
		END),
	--Calculate volume_to_buy; only buy if the volumn_at_net_stock is <= volumn_at_min
	SUM(CASE 
			WHEN volume_at_net_stock < 0
				THEN ABS(volume_at_net_stock)
			WHEN volume_at_max - volume_at_net_stock < 0 OR volume_at_min < volume_at_net_stock
				THEN 0 
			ELSE volume_at_max - volume_at_net_stock 
		END)  
FROM CTE_inventory
--The next line should be unnecessary with the addition of the min < net_stock comparison for each of the above types.
--WHERE units_at_net_stock <= units_at_min
GROUP BY location_id, supplier_id
--Works to here.
/*
	Get and insert the last PO date for each supplier and location.
	First, find the average days between POs.
*/
DECLARE @Data TABLE
(
	location_id DECIMAL(19,0),
	supplier_id DECIMAL(19,0),
	DateVal DATETIME,
	po_seq INT
)
	
INSERT INTO @Data (location_id, supplier_id, DateVal, po_seq)
SELECT *
FROM
(
	SELECT location_id, supplier_id, order_date, 
		ROW_NUMBER() OVER (PARTITION BY location_id, supplier_id ORDER BY order_date DESC) AS 'IDCode'
	FROM p21_view_po_hdr
) tmp
WHERE IDCode <= 5
ORDER BY location_id, supplier_id, IDCode;

DECLARE @tbl_avg TABLE
(
	location_id DECIMAL(19,0),
	supplier_id VARCHAR(10),
	po_seq INT,
	DateVal DATETIME,
	avg_po_days NUMERIC(19,4)
);

WITH CTE AS (SELECT ROW_NUMBER() OVER (ORDER BY location_id, supplier_id, po_seq DESC) AS 'RowNo', 
	po_seq, location_id, supplier_id, DateVal FROM @Data)
INSERT INTO @tbl_avg(location_id, supplier_id, po_seq, DateVal, avg_po_days)
SELECT t1.location_id, t1.supplier_id, t1.po_seq, t1.DateVal, ISNULL(DATEDIFF(d, t2.DateVal, t1.DateVal), 0) AS 'avgDays'
FROM CTE t1
	LEFT JOIN CTE t2 ON (t1.RowNo = t2.RowNo + 1 AND t1.supplier_id = t2.supplier_id AND t1.location_id = t2.location_id)
WHERE t1.po_seq <= 4
ORDER BY t1.location_id, t1.supplier_id, t1.po_seq

DECLARE @tbl_info TABLE
(
	location_id DECIMAL(19,0),
	supplier_id VARCHAR(10),
	avg_po_days NUMERIC(19,4)
)

INSERT INTO @tbl_info (location_id, supplier_id, avg_po_days)
SELECT location_id, supplier_id, AVG(avg_po_days)
FROM @tbl_avg
WHERE avg_po_days <> 0
GROUP BY location_id, supplier_id;

--Then, find the last PO date
WITH CTE_last_po (location_id, supplier_id, last_po_date, average_lead_time)
AS
(
	SELECT L.location_id, S.supplier_id, MAX(H.order_date) AS 'last_po_date', L.average_lead_time
	FROM p21_view_po_hdr H
		INNER JOIN p21_view_vendor V ON H.vendor_id = V.vendor_id
		INNER JOIN p21_view_vendor_supplier X ON V.vendor_id = X.vendor_id
		INNER JOIN p21_view_supplier S ON X.supplier_id = S.supplier_id
		INNER JOIN p21_view_location_supplier L ON (X.supplier_id = L.supplier_id 
			AND L.location_id >= @start_location_id AND L.location_id <= @end_location_id)
	WHERE H.po_type <> 'Q'
		AND H.delete_flag = 'N'
		AND L.company_id = @company_id
	GROUP BY L.location_id,  S.supplier_id, L.average_lead_time
),
/*
	Set up the common table expression that collects the supplier and buyer information including the
	minimum order and minimum freight requirements.
	If the Locations tab has information on control values then they override the Purchase tab values.
	Check for location-specific values first.
*/
cteLocationSupplier(location_id, supplier_id, supplier_name, buyer_id, buyer_name, min_order_control_type,
	min_order_control_value, freight_control_type, freight_control_value)
AS
(
	SELECT L.location_id, L.supplier_id, S.supplier_name, S.buyer_id, C.first_name + ' ' + C.last_name AS 'buyer_name',
	 L.control_value AS 'min_order_control_type', COALESCE(L.target_value,0) AS 'min_order_control_value', 
	 COALESCE(L.freight_control_value,'UNITS') AS 'freight_control_type',
	 L.freight_target_value AS 'freight_control_value'
	FROM p21_view_location_supplier L
	 INNER JOIN p21_view_supplier S ON L.supplier_id = S.supplier_id
	 LEFT JOIN p21_view_contacts C ON S.buyer_id = C.id
	WHERE S.delete_flag = 'N'
	GROUP BY L.location_id, L.supplier_id, S.supplier_name, L.control_value, L.target_value, L.freight_control_value,
	 L.freight_target_value, buyer_id, C.first_name + ' ' + C.last_name

),
CTE_supplier_info(supplier_id, supplier_name, buyer_id, buyer_name, min_order_control_type,
	min_order_control_value, freight_control_type, freight_control_value)
AS
(
	SELECT S.supplier_id, S.supplier_name, S.buyer_id, C.first_name + ' ' + C.last_name AS 'buyer_name',
		S.control_value AS 'min_order_control_type', COALESCE(S.target_value,0) AS 'min_order_control_value', 
		COALESCE(S.freight_control_value,'UNITS') AS 'freight_control_type',
		S.freight_target_value AS 'freight_control_value'
	FROM p21_view_supplier S
		INNER JOIN p21_view_inventory_supplier X ON S.supplier_id = X.supplier_id
		LEFT JOIN p21_view_contacts C ON S.buyer_id = C.id
	WHERE S.delete_flag = 'N'
	GROUP BY S.supplier_id, S.supplier_name, S.control_value, S.target_value, S.freight_control_value,
		S.freight_target_value, buyer_id, C.first_name + ' ' + C.last_name
)
/*
	Return the results using a nested SELECT statement into a temporary table that can be updated
	 with location-specific requirements.
*/

INSERT INTO @tbl_results (location_id, supplier_id, supplier_name, buyer_name,
	last_po_date, avg_po_days, moct, mocv, fct, fcv, order_value, freight_value,
	control_type, target_value, actual_value, pct_of_order, est_po_date, est_arrival_date)
SELECT tmp.location_id, tmp.supplier_id, tmp.supplier_name, tmp.buyer_name,
	tmp.last_po_date, tmp.avg_po_days, tmp.moct,
	tmp.mocv, tmp.fct, tmp.fcv,
	tmp.order_value, tmp.freight_value, tmp.control_type,
	tmp.target_value, tmp.actual_value,
	--Calculate the % of order based on actual and target values.
	CASE WHEN actual_value = 0 THEN 0 
		WHEN target_value = 0 THEN 1
		WHEN actual_value / target_value < 0 THEN 0 
		ELSE actual_value / target_value 
	END AS 'pct_of_order',
	 --Calculate the estimated PO date.
	CASE WHEN target_value = 0 THEN NULL
		WHEN actual_value / target_value > 1 THEN GETDATE()
		WHEN DAY(GETDATE() - last_po_date) < avg_po_days AND (actual_value / target_value) < 0.3 
			THEN DATEADD(d, avg_po_days, GETDATE())
		ELSE DATEADD(d, ABS(DATEDIFF(d, GETDATE(), last_po_date)) * (1 - (actual_value / target_value)), GETDATE())
	END AS 'est_po_date',
	CASE WHEN target_value = 0 THEN NULL
		WHEN actual_value / target_value > 1 THEN DATEADD(d, avg_lead_time_days + (avg_lead_time_days / 7), GETDATE())
		WHEN DAY(GETDATE() - last_po_date) < avg_po_days AND (actual_value / target_value) < 0.3 
			THEN DATEADD(d, avg_po_days + avg_lead_time_days  + (avg_lead_time_days / 7), GETDATE())
		ELSE DATEADD(d, avg_lead_time_days + (avg_lead_time_days / 7), 
			DATEADD(d, ABS(DATEDIFF(d, GETDATE(), last_po_date)) * (1 - (actual_value / target_value)), GETDATE()))
	END AS 'est_arrival_date'
FROM
(
	SELECT A.location_id AS 'location_id',
		B.supplier_id AS 'supplier_id',
		B.supplier_name AS 'supplier_name', 
		B.buyer_name AS 'buyer_name',
		P.last_po_date AS 'last_po_date',
		P.average_lead_time AS 'avg_lead_time_days',
		I.avg_po_days AS 'avg_po_days',
		B.min_order_control_type AS 'moct',
		B.min_order_control_value AS 'mocv',
		B.freight_control_type AS 'fct',
		B.freight_control_value AS 'fcv',
		--Determine order value based on the min_order_control_type
		CASE WHEN B.min_order_control_type = 'DOLLARS' THEN A.value_to_buy
			WHEN B.min_order_control_type = 'UNITS' THEN A.units_to_buy
			WHEN B.min_order_control_type = 'WEIGHT' THEN A.weight_to_buy
			WHEN B.min_order_control_type = 'VOLUME' THEN A.volume_to_buy
			ELSE 0
		END AS 'order_value',
		--Determin the freight value based on freight_control_type
		CASE WHEN B.freight_control_type = 'DOLLARS' THEN A.value_to_buy
			WHEN B.freight_control_type = 'UNITS' THEN A.units_to_buy
			WHEN B.freight_control_type = 'WEIGHT' THEN A.weight_to_buy
			WHEN B.freight_control_type = 'VOLUME' THEN A.volume_to_buy
			ELSE 0
		END AS 'freight_value',
		--Determine the Control Type to use
		CASE
			WHEN B.min_order_control_value >= B.freight_control_value
				THEN 'Min Order ' + CONVERT(VARCHAR(12), UPPER(SUBSTRING(B.min_order_control_type,1,1)) 
					+ LOWER(SUBSTRING(B.min_order_control_type,2,11)))
			ELSE 'Freight ' + CONVERT(VARCHAR(12), UPPER(SUBSTRING(B.freight_control_type,1,1)) 
				+ LOWER(SUBSTRING(B.freight_control_type,2,11)))
		END AS 'control_type',
		--Determine the target value
		CASE
			WHEN B.min_order_control_value >= B.freight_control_value
				THEN B.min_order_control_value
			ELSE B.freight_control_value
		END AS 'target_value',
		--Determine actual value; has to include both the min_order_control_value and the freight_control_value
		CASE
			WHEN B.min_order_control_value + B.freight_control_value = 0 THEN 0
			WHEN B.min_order_control_value >= B.freight_control_value AND B.min_order_control_type = 'DOLLARS' THEN A.value_to_buy
			WHEN B.min_order_control_value >= B.freight_control_value AND B.min_order_control_type = 'UNITS' THEN A.units_to_buy 
			WHEN B.min_order_control_value >= B.freight_control_value AND B.min_order_control_type = 'WEIGHT' THEN A.weight_to_buy 
			WHEN B.min_order_control_value >= B.freight_control_value AND B.min_order_control_type = 'VOLUME' THEN A.volume_to_buy
			WHEN B.min_order_control_value < B.freight_control_value AND B.freight_control_type = 'DOLLARS' THEN A.value_to_buy
			WHEN B.min_order_control_value < B.freight_control_value AND B.freight_control_type = 'UNITS' THEN A.units_to_buy
			WHEN B.min_order_control_value < B.freight_control_value AND B.freight_control_type = 'WEIGHT' THEN A.weight_to_buy
			WHEN B.min_order_control_value < B.freight_control_value AND B.freight_control_type = 'VOLUME' THEN A.volume_to_buy
			ELSE 0
		END AS 'actual_value'
	FROM @tbl_summary_info A
		INNER JOIN CTE_supplier_info B ON A.supplier_id = B.supplier_id
		LEFT JOIN CTE_last_po P ON (A.supplier_id = P.supplier_id AND A.location_id = P.location_id)
		LEFT JOIN @tbl_info I ON (A.supplier_id = I.supplier_id AND A.location_id = I.location_id)
) tmp
	INNER JOIN is_supplier_rules R ON (tmp.location_id = R.location_id AND tmp.supplier_id = R.supplier_id)
WHERE R.include_in_barometer = 'Y';

/*
	Collect information on specific locations.
*/
WITH cteLocationSupplierInfo(location_id, supplier_id, control_value, target_value, freight_control_value, 
	freight_target_value, control_type)
AS
(
	SELECT location_id, supplier_id, control_value, target_value, freight_control_value, freight_target_value,
		CASE
			WHEN control_value >= freight_control_value
				THEN 'Min Order ' + CONVERT(VARCHAR(12), UPPER(SUBSTRING(control_value,1,1)) 
					+ LOWER(SUBSTRING(control_value,2,11)))
			ELSE 'Freight ' + CONVERT(VARCHAR(12), UPPER(SUBSTRING(freight_control_value,1,1)) 
					+ LOWER(SUBSTRING(freight_control_value,2,11)))
		END AS 'control_type'
	FROM p21_view_location_supplier
	WHERE company_id = @company_id
		AND delete_flag = 'N'
		AND (COALESCE(target_value, 0) > 0 OR COALESCE(freight_target_value, 0) > 0)
)
UPDATE A
SET A.moct = B.control_value,
	A.mocv = B.target_value,
	A.fct = B.freight_control_value,
	A.fcv = B.freight_target_value,
	A.control_type = B.control_type
FROM @tbl_results A
	INNER JOIN cteLocationSupplierInfo B ON (A.location_id = B.location_id AND A.supplier_id = B.supplier_id)

--This little script updates the tracking table to see how frequently things are being run.
UPDATE is_last_run_dates SET last_run_date = CURRENT_TIMESTAMP, last_run_by = CURRENT_USER WHERE proc_name = 'sp_is_barometer_lr';

SELECT * 
FROM @tbl_results
ORDER BY CASE WHEN actual_value = 0 THEN 0 WHEN target_value = 0 THEN 1 ELSE actual_value / target_value END DESC




GO


/*
	2023.06.15 Added functionality to round quantities based on conversions in item maintenance.
	2023.05.06 After many years, Anthony Raimondi realized that when the barometer is updated, it excludes any backordered non-stock
	items in the % to buy calc.
*/