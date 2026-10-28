-- Compare every mapped field and every row, including preserved source metadata.
DO $$ BEGIN IF EXISTS ((SELECT * FROM core.buyer EXCEPT ALL SELECT * FROM stage_buyer) UNION ALL (SELECT * FROM stage_buyer EXCEPT ALL SELECT * FROM core.buyer)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: buyer'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT * FROM core.customer_snapshot EXCEPT ALL SELECT * FROM stage_customer_snapshot) UNION ALL (SELECT * FROM stage_customer_snapshot EXCEPT ALL SELECT * FROM core.customer_snapshot)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: customer_snapshot'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT * FROM core.orders EXCEPT ALL SELECT * FROM stage_orders) UNION ALL (SELECT * FROM stage_orders EXCEPT ALL SELECT * FROM core.orders)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: orders'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT * FROM core.category EXCEPT ALL SELECT * FROM stage_category) UNION ALL (SELECT * FROM stage_category EXCEPT ALL SELECT * FROM core.category)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: category'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT * FROM core.product EXCEPT ALL SELECT * FROM stage_product) UNION ALL (SELECT * FROM stage_product EXCEPT ALL SELECT * FROM core.product)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: product'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT * FROM core.seller EXCEPT ALL SELECT * FROM stage_seller) UNION ALL (SELECT * FROM stage_seller EXCEPT ALL SELECT * FROM core.seller)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: seller'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT * FROM core.order_item EXCEPT ALL SELECT * FROM stage_order_item) UNION ALL (SELECT * FROM stage_order_item EXCEPT ALL SELECT * FROM core.order_item)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: order_item'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT * FROM core.order_payment EXCEPT ALL SELECT * FROM stage_order_payment) UNION ALL (SELECT * FROM stage_order_payment EXCEPT ALL SELECT * FROM core.order_payment)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: order_payment'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT * FROM core.order_review EXCEPT ALL SELECT * FROM stage_order_review) UNION ALL (SELECT * FROM stage_order_review EXCEPT ALL SELECT * FROM core.order_review)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: order_review'; END IF; END $$;
DO $$ BEGIN
 IF (SELECT count(*) FROM mart.order_totals)<>(SELECT count(*) FROM core.orders)
 OR (SELECT count(*) FROM mart.order_item_enriched)<>(SELECT count(*) FROM core.order_item)
 OR (SELECT sum(price) FROM mart.order_item_enriched) IS DISTINCT FROM (SELECT sum(price) FROM core.order_item)
 OR (SELECT sum(freight_value) FROM mart.order_item_enriched) IS DISTINCT FROM (SELECT sum(freight_value) FROM core.order_item)
 OR (SELECT sum(item_revenue) FROM mart.order_totals) IS DISTINCT FROM (SELECT sum(price) FROM core.order_item)
 OR (SELECT sum(payment_value) FROM mart.order_totals) IS DISTINCT FROM (SELECT sum(payment_value) FROM core.order_payment)
 OR (SELECT sum(review_count) FROM mart.order_totals)<>(SELECT count(*) FROM core.order_review) THEN
  RAISE EXCEPTION 'Mart cardinality or money conservation failed'; END IF;
 IF (SELECT count(*) FROM core.category WHERE category_name_pt IS NULL AND category_name_en IS NULL
     AND category_id='e241560a-82de-55d7-ae54-22be2eb37541')<>1 THEN
  RAISE EXCEPTION 'Reserved unknown category mismatch'; END IF;
END $$;
-- Inspect actual rewrite dependencies, recursively; no mart may reach raw or other schemas.
DO $$ BEGIN
 IF EXISTS (
  WITH RECURSIVE dependencies(oid) AS (
   SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='mart' AND c.relname IN ('order_totals','order_item_enriched','buyer_order_counts')
   UNION
   SELECT d.refobjid FROM dependencies v JOIN pg_rewrite r ON r.ev_class=v.oid
   JOIN pg_depend d ON d.classid='pg_rewrite'::regclass AND d.objid=r.oid
   WHERE d.refclassid='pg_class'::regclass AND d.refobjid<>v.oid
  ) SELECT FROM dependencies d JOIN pg_class c ON c.oid=d.oid JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname NOT IN ('core','mart')
 ) THEN RAISE EXCEPTION 'Unexpected mart relation dependency outside core/mart'; END IF;
END $$;

\if :reviewed_snapshot
-- Optional acceptance controls, not permanent constraints or answer inputs.
DO $$
DECLARE counts jsonb; q3 record; q4 record; top_seller record; category_total numeric; share_total numeric;
BEGIN
 SELECT jsonb_object_agg(name,rows) INTO counts FROM (
  SELECT 'buyer' name,count(*) rows FROM core.buyer
  UNION ALL SELECT 'customer_snapshot',count(*) FROM core.customer_snapshot
  UNION ALL SELECT 'orders',count(*) FROM core.orders
  UNION ALL SELECT 'category',count(*) FROM core.category
  UNION ALL SELECT 'product',count(*) FROM core.product
  UNION ALL SELECT 'seller',count(*) FROM core.seller
  UNION ALL SELECT 'order_item',count(*) FROM core.order_item
  UNION ALL SELECT 'order_payment',count(*) FROM core.order_payment
  UNION ALL SELECT 'order_review',count(*) FROM core.order_review) c;
 IF counts <> '{"buyer":96096,"customer_snapshot":99441,"orders":99441,"category":74,"product":32951,"seller":3095,"order_item":112650,"order_payment":103886,"order_review":99224}'::jsonb THEN
  RAISE EXCEPTION 'Snapshot differs from reviewed source: %',counts; END IF;
 SELECT count(*) n,sum(item_count) items,sum(item_revenue) revenue,sum(freight_value) freight,
        sum(order_value) value,round(avg(order_value),12) aov,round(avg(item_count),12) aitems
 INTO q3 FROM mart.order_totals WHERE status='delivered';
 IF (q3.n,q3.items,q3.revenue,q3.freight,q3.value,q3.aov,q3.aitems) IS DISTINCT FROM
    (96478::bigint,110197::numeric,13221498.11,2202965.54,15424463.65,159.875449843488,1.142198221356) THEN
  RAISE EXCEPTION 'Reviewed Q3 control differs: %',q3; END IF;
 IF (SELECT count(*) FROM mart.order_totals WHERE status='delivered' AND purchased_at>=timestamp '2016-09-01' AND purchased_at<timestamp '2018-09-01')<>96478
 OR (SELECT coalesce(sum(item_revenue),0) FROM mart.order_totals WHERE status='delivered' AND purchased_at>=timestamp '2016-11-01' AND purchased_at<timestamp '2016-12-01')<>0 THEN
  RAISE EXCEPTION 'Reviewed Q1 date window control differs'; END IF;
 SELECT replace(seller_id::text,'-','') id,seller_city city,seller_state state,count(DISTINCT order_id) orders,
        count(*) units,sum(price) revenue INTO top_seller FROM mart.order_item_enriched WHERE status='delivered'
 GROUP BY seller_id,seller_city,seller_state ORDER BY revenue DESC,seller_id LIMIT 1;
 IF (top_seller.id,top_seller.city,top_seller.state,top_seller.orders,top_seller.units,top_seller.revenue) IS DISTINCT FROM
 ('4869f7a5dfa277a7dca6462dcf3b52b2'::text,'guariba'::text,'SP'::text,1124::bigint,1148::bigint,226987.93) THEN
  RAISE EXCEPTION 'Reviewed Q2 control differs'; END IF;
 SELECT count(*) n,count(*) FILTER(WHERE is_repeat) repeats,
  round(100.0*count(*) FILTER(WHERE is_repeat)/nullif(count(*),0),12) share
 INTO q4 FROM mart.buyer_order_counts;
 IF (q4.n,q4.repeats,q4.share) IS DISTINCT FROM (96096::bigint,2997::bigint,3.118756243756) THEN
  RAISE EXCEPTION 'Reviewed Q4 control differs'; END IF;
 IF (SELECT sum(price) FROM mart.order_item_enriched WHERE status='delivered' AND category_name_pt='beleza_saude')<>1233131.72
 OR (SELECT sum(price) FROM mart.order_item_enriched WHERE status='delivered' AND category_name_pt IS NULL)<>170726.63
 OR (SELECT count(*) FROM core.category WHERE category_name_pt IN ('pc_gamer','portateis_cozinha_e_preparadores_de_alimentos') AND category_name_en IS NULL)<>2 THEN
  RAISE EXCEPTION 'Reviewed Q5 category control differs'; END IF;
 SELECT sum(revenue),sum(round(100.0*revenue/nullif(total,0),12)) INTO category_total,share_total FROM (
 SELECT k.category_id,coalesce(sum(i.price),0) revenue,
        sum(coalesce(sum(i.price),0)) OVER() total
 FROM core.category k LEFT JOIN mart.order_item_enriched i ON i.category_id=k.category_id AND i.status='delivered'
 GROUP BY k.category_id) c;
 IF category_total<>13221498.11 OR abs(share_total-100)>0.0000000001 THEN
  RAISE EXCEPTION 'Reviewed Q5 revenue/share control differs'; END IF;
END $$;

\endif

\echo __CAPIBARA_BEGIN_report
COPY (SELECT jsonb_build_object(
 'database_version',version(), 'server_version_num',current_setting('server_version_num'),
 'snapshot', (SELECT jsonb_agg(to_jsonb(x) ORDER BY layer,name) FROM (
SELECT 'raw' AS layer,'orders' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM raw.orders r) s
UNION ALL
SELECT 'raw' AS layer,'order_items' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM raw.order_items r) s
UNION ALL
SELECT 'raw' AS layer,'order_payments' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM raw.order_payments r) s
UNION ALL
SELECT 'raw' AS layer,'order_reviews' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM raw.order_reviews r) s
UNION ALL
SELECT 'raw' AS layer,'products' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM raw.products r) s
UNION ALL
SELECT 'raw' AS layer,'sellers' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM raw.sellers r) s
UNION ALL
SELECT 'raw' AS layer,'customers' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM raw.customers r) s
UNION ALL
SELECT 'raw' AS layer,'product_category_translation' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM raw.product_category_translation r) s
UNION ALL
SELECT 'core' AS layer,'buyer' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM core.buyer r) s
UNION ALL
SELECT 'core' AS layer,'customer_snapshot' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM core.customer_snapshot r) s
UNION ALL
SELECT 'core' AS layer,'orders' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM core.orders r) s
UNION ALL
SELECT 'core' AS layer,'category' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM core.category r) s
UNION ALL
SELECT 'core' AS layer,'product' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM core.product r) s
UNION ALL
SELECT 'core' AS layer,'seller' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM core.seller r) s
UNION ALL
SELECT 'core' AS layer,'order_item' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM core.order_item r) s
UNION ALL
SELECT 'core' AS layer,'order_payment' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM core.order_payment r) s
UNION ALL
SELECT 'core' AS layer,'order_review' AS name,count(*) AS rows,md5(coalesce(string_agg(h,'' ORDER BY h COLLATE "C"),'')) AS fingerprint FROM (SELECT md5(to_jsonb(r)::text) h FROM core.order_review r) s
) x),
 'warnings',jsonb_build_object(
 'delivered_without_payments',(SELECT count(*) FROM mart.order_totals WHERE status='delivered' AND NOT has_payments),
 'orders_without_items',(SELECT count(*) FROM mart.order_totals WHERE NOT has_items),
 'orders_without_reviews',(SELECT count(*) FROM mart.order_totals WHERE review_count=0),
 'payment_item_value_mismatch',(SELECT count(*) FROM mart.order_totals WHERE has_items AND has_payments AND order_value<>payment_value),
 'delivered_missing_delivery_date',(SELECT count(*) FROM core.orders WHERE status='delivered' AND delivered_to_customer_at IS NULL),
 'untranslated_categories',(SELECT jsonb_agg(category_name_pt ORDER BY category_name_pt) FROM core.category WHERE category_name_pt IS NOT NULL AND category_name_en IS NULL),
 'changed_existing_payment_keys',(SELECT count(*) FROM changed_payments)
 )) AS report) TO STDOUT WITH (FORMAT csv, HEADER true);
\echo __CAPIBARA_END_report
