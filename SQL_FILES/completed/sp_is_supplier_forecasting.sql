ALTER PROCEDURE sp_is_supplier_forecasting
	@locationID INT,
	@supplierID INT,
	@reviewCycle INT,
	@diagInvMastUID INT = 0,
	@diagFlag VARCHAR(1) = 'N'
AS

SET NOCOUNT ON;

DECLARE @location_id INT = @locationID;
DECLARE @supplier_id INT = @supplierID;
DECLARE @review_cycle DECIMAL(4,0) = @reviewCycle;
DECLARE @diag_flag VARCHAR(1) = @diagFlag;
DECLARE @diag_inv_mast_uid INT = @diagInvMastUID;

DECLARE @class_params AS TABLE (
	location_id INT INDEX idx_cp_li NONCLUSTERED,
	item_class VARCHAR(1) INDEX idx_cp_ic NONCLUSTERED,
	periods_to_supply DECIMAL(8,4),
	target_service_level DECIMAL(8,4),
	safety_stock_factor DECIMAL(8,4)
);
INSERT INTO @class_params (location_id, item_class, periods_to_supply, target_service_level, safety_stock_factor) VALUES (1001, 'A', 1.33, 0.98, 1.5);
INSERT INTO @class_params (location_id, item_class, periods_to_supply, target_service_level, safety_stock_factor) VALUES (1001, 'B', 1.50, 0.965, 1.35);
INSERT INTO @class_params (location_id, item_class, periods_to_supply, target_service_level, safety_stock_factor) VALUES (1001, 'C', 1.71, 0.95, 1.15);
INSERT INTO @class_params (location_id, item_class, periods_to_supply, target_service_level, safety_stock_factor) VALUES (1001, 'D', 2, 0.94, 1);
INSERT INTO @class_params (location_id, item_class, periods_to_supply, target_service_level, safety_stock_factor) VALUES (1001, 'Z', 0, 0.0, 0);

DECLARE @item_forecast AS TABLE (
	location_id INT INDEX idx_if_li NONCLUSTERED,
	inv_mast_uid INT INDEX idx_if_imu NONCLUSTERED,
	current_forecast DECIMAL(19,4),
	rmse DECIMAL(19,4)
)
INSERT INTO @item_forecast (location_id, inv_mast_uid, current_forecast, rmse)
SELECT location_id, inv_mast_uid, current_forecast, root_mean_square_error
FROM (
	SELECT location_id, inv_mast_uid, current_forecast, root_mean_square_error,
		RANK() OVER(PARTITION BY location_id, inv_mast_uid ORDER BY forecast_history_uid DESC) AS 'row_rank'
	FROM is_item_forecast_history
) T1
WHERE row_rank = 1;

/* 
	For diagnostic purposes, I'm going to return the results to a table then run the select statements based on the flag.
*/
DECLARE @t_results AS TABLE (
	inv_mast_uid INT INDEX idx_tr_imu NONCLUSTERED,
	item_id VARCHAR(100),
	item_desc VARCHAR(100),
	stockable VARCHAR(1),
	purchase_class VARCHAR(12) DEFAULT 'C',
	periods_to_supply DECIMAL(19,8),
	safety_stock_factor DECIMAL(19,8),
	target_service_level DECIMAL(19,8),
	avg_lead_time_days DECIMAL(19,8),
	avg_daily_usage DECIMAL(19,8),
	inv_min DECIMAL(19,8),
	inv_max DECIMAL(19,8),
	qty_on_hand DECIMAL(19,8),
	net_stock DECIMAL(19,8),
	current_forecast DECIMAL(19,8),
	rmse DECIMAL(19,8),
	rec_min DECIMAL(19,8),
	rec_max DECIMAL(19,8),
	days_to_stockout DECIMAL(19,8),
	stockout_potential VARCHAR(20),
	last_review_date DATETIME
)
INSERT INTO @t_results (inv_mast_uid, item_id, item_desc, stockable, purchase_class, periods_to_supply, safety_stock_factor,
	target_service_level, avg_lead_time_days, avg_daily_usage, inv_min, inv_max, qty_on_hand, net_stock, current_forecast,
	rmse, rec_min, rec_max, days_to_stockout, stockout_potential, last_review_date)
SELECT T2.inv_mast_uid, T2.item_id, T2.item_desc, T2.stockable, T2.purchase_class, T2.periods_to_supply, T2.safety_stock_factor,
	T2.target_service_level, T2.avg_lead_time_days, T2.avg_daily_usage, T2.inv_min, T2.inv_max, T2.qty_on_hand, T2.net_stock,
	T2.current_forecast, T2.rmse, 
	/*RECOMMENDED MINIMUM CALCULATION*/
	CASE 
		WHEN T2.current_forecast = 0 THEN 0
		ELSE ROUND(0.5 + (T2.current_forecast / 22) * (T2.avg_lead_time_days + @review_cycle) * T2.safety_stock_factor, 0) 
	END AS 'rec_min',
	/*RECOMMENDED MAXIMUM CALCULATION*/
	CASE 
		WHEN T2.current_forecast = 0 THEN 0
		WHEN ROUND(0.5 + (T2.current_forecast / 22) * (T2.avg_lead_time_days + @review_cycle) * T2.safety_stock_factor, 0) >=
			T2.periods_to_supply * T2.current_forecast
			THEN ROUND(0.5 + (T2.current_forecast / 22) * (T2.avg_lead_time_days + @review_cycle) * T2.safety_stock_factor, 0) 
		ELSE ROUND(0.5 + T2.periods_to_supply * T2.current_forecast, 0)
	END AS 'rec_max', 
	CASE 
		WHEN T2.stockable = 'N' THEN 0 
		ELSE dbo.UDF_DaysToStockout(T2.net_stock, T2.avg_daily_usage, T2.avg_lead_time_days, @review_cycle) 
	END AS 'days_to_stockout',
	CASE 
		WHEN T2.stockable = 'N' THEN 'Non-Stock'
		WHEN dbo.UDF_DaysToStockout(T2.net_stock, T2.avg_daily_usage, T2.avg_lead_time_days, @review_cycle) = 0 
			OR dbo.UDF_DaysToStockout(T2.net_stock, T2.avg_daily_usage, T2.avg_lead_time_days, @review_cycle) > T2.safety_stock_factor * (T2.avg_lead_time_days + @review_cycle)
			THEN 'Low'
		WHEN dbo.UDF_DaysToStockout(T2.net_stock, T2.avg_daily_usage, T2.avg_lead_time_days, @review_cycle) < T2.avg_lead_time_days + @review_cycle
			THEN 'Imminent'
		ELSE 'Probable'
	END AS 'stockout_potential', T2.last_review_date
FROM (
	SELECT M.inv_mast_uid, M.item_id, M.item_desc, L.stockable, L.purchase_class, L.inv_min, L.inv_max, L.qty_on_hand,
		dbo.UDF_FindNetStock(L.company_id, L.location_id, L.inv_mast_uid) AS 'net_stock',
		COALESCE(F.current_forecast, 0) AS 'current_forecast', COALESCE(F.rmse, 0) AS 'rmse',
		C.periods_to_supply, C.safety_stock_factor, C.target_service_level,
		ROUND(0.5 + dbo.UDF_AvgLeadTimeDays(L.company_id, L.location_id, L.inv_mast_uid), 0) AS 'avg_lead_time_days',
		COALESCE(dbo.UDF_AvgDailyUsageNew(L.company_id, L.location_id, L.inv_mast_uid, 3), 0) AS 'avg_daily_usage',
		COALESCE(dbo.UDF_DeviationUsage(L.company_id, L.location_id, L.inv_mast_uid), 0) AS 'deviation_usage',
		P.last_review_date
	FROM p21_view_inv_mast M
		INNER JOIN p21_view_inv_loc L ON M.inv_mast_uid = L.inv_mast_uid
		INNER JOIN p21_view_inventory_supplier X ON M.inv_mast_uid = X.inv_mast_uid
		INNER JOIN p21_view_inventory_supplier_x_loc W ON
			(L.location_id = W.location_id
				AND W.primary_supplier = 'Y'
				AND X.inventory_supplier_uid = W.inventory_supplier_uid)
		LEFT JOIN @item_forecast F ON (L.location_id = F.location_id AND L.inv_mast_uid = F.inv_mast_uid)
		LEFT JOIN @class_params C ON (L.location_id = C.location_id AND COALESCE(L.purchase_class, 'C') = C.item_class)
		LEFT JOIN is_inv_params P ON (L.location_id = P.location_id AND L.inv_mast_uid = P.inv_mast_uid)
	WHERE X.supplier_id = @supplier_id
		AND L.location_id = @location_id
) T2
ORDER BY T2.stockable DESC, T2.purchase_class, T2.item_id;

IF @diag_flag = 'Y'
BEGIN
	SELECT * FROM @t_results WHERE inv_mast_uid = @diag_inv_mast_uid ORDER BY stockable DESC, purchase_class, item_id;
END;
IF @diag_flag = 'N'
BEGIN
	SELECT inv_mast_uid, item_id, stockable, purchase_class, inv_min, inv_max, qty_on_hand, net_stock, current_forecast, rmse,
		rec_min, rec_max, days_to_stockout, stockout_potential, last_review_date
	FROM @t_results
	ORDER BY stockable DESC, purchase_class, item_id;
END;


/*
	GRANT EXECUTE ON OBJECT::dbo.sp_is_supplier_forecasting TO SheppardSpecialReports;
	EXECUTE sp_is_supplier_forecasting 1001, 15424, 3; --Without diagnostics
	EXECUTE sp_is_supplier_forecasting 1001, 15424, 3, 11338, Y; --With diagnostics

	This stored procedure determine the recommended min and max for each item in a supply line along with the days to stockout
	and stockout potential. This is used in concert with the Mock Purchase Order program to get a wholistic view of inventory
	for a supplier.
*/