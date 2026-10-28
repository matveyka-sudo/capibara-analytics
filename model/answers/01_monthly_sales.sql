WITH months AS (
 SELECT generate_series(timestamp '2016-09-01',timestamp '2018-08-01',interval '1 month')::date AS month
), sales AS (
 SELECT date_trunc('month',purchased_at)::date AS month,count(*) AS order_count,sum(items_subtotal) AS revenue
 FROM mart.order_totals
 WHERE status='delivered' AND purchased_at>=timestamp '2016-09-01' AND purchased_at<timestamp '2018-09-01'
 GROUP BY 1
)
SELECT m.month,coalesce(s.order_count,0) AS order_count,coalesce(s.revenue,0.00) AS revenue
FROM months m LEFT JOIN sales s USING(month) ORDER BY m.month;
