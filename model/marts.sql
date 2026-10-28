-- Aggregate independent facts before joining: one row per order, all statuses.
CREATE OR REPLACE VIEW mart.order_totals AS
WITH items AS (
 SELECT order_id,count(*) AS item_count,count(*) AS unit_count,
        sum(price)::numeric(18,2) AS items_subtotal,sum(freight_value)::numeric(18,2) AS freight_total
 FROM core.order_item GROUP BY order_id
), payments AS (
 SELECT order_id,count(*) AS payment_count,sum(payment_value)::numeric(18,2) AS payment_value
 FROM core.order_payment GROUP BY order_id
), reviews AS (
 SELECT order_id,count(*) AS review_count FROM core.order_review GROUP BY order_id
), facts AS (
 SELECT o.order_id,o.customer_id,c.buyer_id,o.status,o.purchased_at,
        c.city AS customer_city,c.state AS customer_state,
        o.delivered_to_carrier_at,o.delivered_to_customer_at,o.estimated_delivery_at,
        coalesce(i.item_count,0) AS item_count,coalesce(i.unit_count,0) AS unit_count,
        i.items_subtotal,i.freight_total,(i.items_subtotal+i.freight_total)::numeric(18,2) AS order_total,
        coalesce(p.payment_count,0) AS payment_count,p.payment_value,
        coalesce(r.review_count,0) AS review_count,
        i.order_id IS NOT NULL AS has_items,p.order_id IS NOT NULL AS has_payments,
        o.status='delivered' AND o.purchased_at IS NOT NULL AND o.delivered_to_customer_at IS NOT NULL AS is_duration_eligible,
        o.status='delivered' AND o.delivered_to_customer_at IS NOT NULL AND o.estimated_delivery_at IS NOT NULL AS is_late_eligible
 FROM core.orders o JOIN core.customer_snapshot c USING(customer_id)
 LEFT JOIN items i USING(order_id) LEFT JOIN payments p USING(order_id) LEFT JOIN reviews r USING(order_id)
)
SELECT order_id,customer_id,buyer_id,status,purchased_at,customer_city,customer_state,
       delivered_to_carrier_at,delivered_to_customer_at,estimated_delivery_at,
       item_count,unit_count,items_subtotal,freight_total,order_total,payment_count,payment_value,
       review_count,has_items,has_payments,
       CASE WHEN is_duration_eligible THEN extract(epoch FROM (delivered_to_customer_at-purchased_at))/86400.0 END AS delivery_days,
       CASE WHEN is_late_eligible THEN delivered_to_customer_at::date>estimated_delivery_at::date END AS is_late,
       is_duration_eligible,is_late_eligible
FROM facts;

CREATE OR REPLACE VIEW mart.order_item_enriched AS
SELECT i.order_item_id,i.order_id,i.item_number,i.product_id,i.seller_id,
       c.buyer_id,o.customer_id,o.status,o.purchased_at,i.shipping_limit_at,
       i.price,i.freight_value,p.category_id,k.category_name_pt,k.category_name_en,
       coalesce(k.category_name_en,k.category_name_pt,'Unknown') AS category_label,
       s.zip_code_prefix AS seller_zip_code_prefix,s.city AS seller_city,s.state AS seller_state,
       c.zip_code_prefix AS customer_zip_code_prefix,c.city AS customer_city,c.state AS customer_state
FROM core.order_item i JOIN core.orders o USING(order_id)
JOIN core.customer_snapshot c USING(customer_id) JOIN core.product p USING(product_id)
JOIN core.category k USING(category_id) JOIN core.seller s USING(seller_id);

CREATE OR REPLACE VIEW mart.buyer_kpi AS
SELECT c.buyer_id,count(DISTINCT o.order_id) AS ordered_orders_count,
       count(DISTINCT o.order_id) FILTER(WHERE o.status='delivered') AS delivered_orders_count,
       count(DISTINCT o.order_id)>=2 AS is_repeat_buyer,
       min(o.purchased_at) AS first_order_at,max(o.purchased_at) AS last_order_at
FROM core.orders o JOIN core.customer_snapshot c USING(customer_id) GROUP BY c.buyer_id;

CREATE OR REPLACE VIEW mart.seller_kpi AS
SELECT s.seller_id,count(DISTINCT i.order_id) AS ordered_orders_count,
       count(DISTINCT i.order_id) FILTER(WHERE o.status='delivered') AS delivered_orders_count,
       count(i.order_item_id) AS ordered_units_count,
       count(i.order_item_id) FILTER(WHERE o.status='delivered') AS delivered_units_count,
       coalesce(sum(i.price) FILTER(WHERE o.status='delivered'),0.00)::numeric(18,2) AS delivered_revenue,
       count(DISTINCT i.order_id) FILTER(WHERE o.status='canceled') AS canceled_orders_count,
       count(DISTINCT i.order_id) FILTER(WHERE o.status='unavailable') AS unavailable_orders_count
FROM core.seller s LEFT JOIN core.order_item i USING(seller_id)
LEFT JOIN core.orders o USING(order_id) GROUP BY s.seller_id;

CREATE OR REPLACE VIEW mart.city_delivery_kpi AS
SELECT customer_city AS city,customer_state AS state,
       count(*) FILTER(WHERE status='delivered') AS delivered_orders,
       count(*) FILTER(WHERE is_duration_eligible) AS eligible_duration_orders,
       coalesce(sum(delivery_days),0) AS delivery_days_sum,
       avg(delivery_days) AS average_delivery_days,
       count(*) FILTER(WHERE is_late_eligible) AS eligible_deliveries,
       count(*) FILTER(WHERE is_late) AS late_orders,
       100.0*count(*) FILTER(WHERE is_late)/nullif(count(*) FILTER(WHERE is_late_eligible),0) AS late_rate_percent
FROM mart.order_totals GROUP BY customer_state,customer_city;

CREATE OR REPLACE VIEW mart.order_review_selected AS
SELECT order_id,review_id,score,created_at,submitted_at FROM (
 SELECT r.*,row_number() OVER(PARTITION BY order_id ORDER BY submitted_at DESC NULLS LAST,
        created_at DESC NULLS LAST,review_id ASC) AS position
 FROM core.order_review r
) ranked WHERE position=1;

-- A product contributes once per delivered basket, regardless of units purchased.
CREATE OR REPLACE VIEW mart.product_recommendation AS
WITH baskets AS MATERIALIZED (
 SELECT DISTINCT order_id,product_id FROM mart.order_item_enriched WHERE status='delivered'
), product_orders AS (
 SELECT product_id,count(*) AS orders FROM baskets GROUP BY product_id
), pairs AS (
 SELECT a.product_id,b.product_id AS recommended_product_id,count(*) AS shared_orders
 FROM baskets a JOIN baskets b ON a.order_id=b.order_id AND a.product_id<b.product_id
 GROUP BY a.product_id,b.product_id HAVING count(*)>=2
), scored AS (
 SELECT p.product_id,p.recommended_product_id,p.shared_orders,
        p.shared_orders::numeric/(a.orders+b.orders-p.shared_orders) AS score
 FROM pairs p JOIN product_orders a ON a.product_id=p.product_id
 JOIN product_orders b ON b.product_id=p.recommended_product_id
), directed AS (
 SELECT product_id,recommended_product_id,shared_orders,score FROM scored
 UNION ALL
 SELECT recommended_product_id,product_id,shared_orders,score FROM scored
), ranked AS (
 SELECT *,row_number() OVER(PARTITION BY product_id ORDER BY score DESC,shared_orders DESC,recommended_product_id) AS position
 FROM directed
)
SELECT product_id,recommended_product_id,shared_orders,
       score::numeric(12,6) AS recommendation_score,'co_purchase_jaccard'::text AS method,
       NULL::timestamptz AS calculated_at
FROM ranked WHERE position<=5;
