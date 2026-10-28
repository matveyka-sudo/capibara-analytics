SELECT state,sum(delivered_orders)::bigint AS order_count,
       round(sum(delivery_days_sum)/nullif(sum(eligible_duration_orders),0),6) AS average_delivery_days,
       round(100.0*sum(late_orders)/nullif(sum(eligible_deliveries),0),6) AS late_rate_percent
FROM mart.city_delivery_kpi GROUP BY state HAVING sum(delivered_orders)>=500
ORDER BY state ASC NULLS LAST;
