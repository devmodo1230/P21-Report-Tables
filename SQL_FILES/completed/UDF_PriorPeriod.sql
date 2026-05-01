WITH params AS (
	True AS include_ma
),
base AS (
  SELECT DISTINCT D.line_number,
	to_char(D.order_date, 'YYYYMM')::int AS period_year,
	D.salesman_code,
	CASE WHEN P.product_line_code LIKE 'MA%' THEN TRUE ELSE FALSE END AS machine_item,
	D.order_number,
	D.net_price * D.quantity_ordered AS line_sales,
	D.net_gross_profit_dollars * D.quantity_ordered AS line_gp
  FROM sales_order_detail D
 	INNER JOIN product_pk P ON D.product_id = P.id
  WHERE D.quantity_ordered <> 0
    AND to_char(D.order_date, 'YYYYMM')::int IN (202508, 202408)
    AND D.salesman_code IS NOT NULL
),
orders AS (
	SELECT 
	FROM (
		SELECT salesman_code, period_year, machine_item, order_number,
			SUM(line_sales) AS order_sales,
			SUM(line_gp) AS order_gp
		GROUP BY salesman_code, period_year, 
	) 
)
SELECT * FROM base;


-- roll lines up to the order level per (period, rep, machine flag)
order_rollup AS (
  SELECT
    period_year,
    salesman_code,
    machine_item,
    order_number,
    SUM(line_sales) AS order_sales,
    SUM(line_gp) AS order_gp
  FROM base
  GROUP BY period_year, salesman_code, machine_item, order_number
)
SELECT
  period_year,  salesman_code,
  machine_item,

  /* Totals (same as your original) */
  SUM(order_sales)                         AS total_sales,
  SUM(order_gp)                            AS total_gp,
  COUNT(*)                                 AS num_orders,      -- orders that had sales in this slice
  /* Your old num_lines equivalent, if still needed: */
  -- (optional) SUM(num_lines) from another CTE if you really need it

  /* 1) Total GM% (sales-weighted) */
  SUM(order_gp) / NULLIF(SUM(order_sales), 0)            AS gm_pct_total,

  /* 2) Average GM% per order (unweighted across orders) */
  AVG( CASE WHEN order_sales > 0
            THEN order_gp / order_sales
            ELSE NULL
       END )                                             AS gm_pct_avg_order

FROM order_rollup
GROUP BY period_year, salesman_code, machine_item
HAVING COUNT(*) <> 0;


SELECT * FROM users;