WITH selected AS (
 SELECT product_id FROM mart.order_item_enriched WHERE status='delivered'
 GROUP BY product_id ORDER BY count(DISTINCT price) DESC,product_id ASC LIMIT 1
)
SELECT purchased_at::date AS sale_date,price,count(*) AS unit_count
FROM mart.order_item_enriched JOIN selected USING(product_id) WHERE status='delivered'
GROUP BY purchased_at::date,price ORDER BY sale_date ASC,price ASC;
