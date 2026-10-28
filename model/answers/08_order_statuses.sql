SELECT status,count(o.order_id) AS order_count,
       round(100.0*count(o.order_id)/nullif((SELECT count(*) FROM core.orders),0),6) AS order_share_percent,
       count(o.order_id) FILTER(WHERE NOT has_items) AS orders_without_items
FROM unnest(enum_range(NULL::core.order_status)) AS statuses(status)
LEFT JOIN mart.order_totals o USING(status) GROUP BY status ORDER BY status;
