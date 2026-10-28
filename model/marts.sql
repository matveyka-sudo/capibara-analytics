-- Aggregate independent child facts before joining; keep all statuses.
CREATE OR REPLACE VIEW mart.order_totals AS
WITH items AS (
 SELECT order_id,count(*) AS item_count,count(*) AS unit_count,
        sum(price) AS item_revenue,sum(freight_value) AS freight_value
 FROM core.order_item GROUP BY order_id
), payments AS (
 SELECT order_id,count(*) AS payment_count,sum(payment_value) AS payment_value
 FROM core.order_payment GROUP BY order_id
), reviews AS (
 SELECT order_id,count(*) AS review_count FROM core.order_review GROUP BY order_id
)
SELECT o.order_id,c.buyer_id,o.status,o.purchased_at,
       coalesce(i.item_count,0) AS item_count,coalesce(i.unit_count,0) AS unit_count,
       i.item_revenue,i.freight_value,i.item_revenue+i.freight_value AS order_value,
       coalesce(p.payment_count,0) AS payment_count,p.payment_value,
       coalesce(r.review_count,0) AS review_count,
       i.order_id IS NOT NULL AS has_items,p.order_id IS NOT NULL AS has_payments
FROM core.orders o JOIN core.customer_snapshot c USING(customer_id)
LEFT JOIN items i USING(order_id) LEFT JOIN payments p USING(order_id) LEFT JOIN reviews r USING(order_id);

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

CREATE OR REPLACE VIEW mart.buyer_order_counts AS
SELECT c.buyer_id,count(DISTINCT o.order_id) AS order_count,min(o.purchased_at) AS first_order_at,
       max(o.purchased_at) AS last_order_at,count(DISTINCT o.order_id)>=2 AS is_repeat
FROM core.orders o JOIN core.customer_snapshot c USING(customer_id) GROUP BY c.buyer_id;
