SELECT replace(seller_id::text,'-','') AS seller_id,seller_city,seller_state,
       count(DISTINCT order_id) AS order_count,count(*) AS item_unit_count,sum(price) AS revenue
FROM mart.order_item_enriched WHERE status='delivered'
GROUP BY seller_id,seller_city,seller_state ORDER BY revenue DESC,seller_id ASC LIMIT 10;
