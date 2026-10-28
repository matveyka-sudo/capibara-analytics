-- Compare every mapped field and every row, including preserved source metadata.
DO $$ BEGIN IF EXISTS ((SELECT buyer_id FROM core.buyer EXCEPT ALL SELECT buyer_id FROM stage_buyer) UNION ALL (SELECT buyer_id FROM stage_buyer EXCEPT ALL SELECT buyer_id FROM core.buyer)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: buyer'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT customer_id,buyer_id,zip_code_prefix,city,state,source,source_loaded_at FROM core.customer_snapshot EXCEPT ALL SELECT customer_id,buyer_id,zip_code_prefix,city,state,source,source_loaded_at FROM stage_customer_snapshot) UNION ALL (SELECT customer_id,buyer_id,zip_code_prefix,city,state,source,source_loaded_at FROM stage_customer_snapshot EXCEPT ALL SELECT customer_id,buyer_id,zip_code_prefix,city,state,source,source_loaded_at FROM core.customer_snapshot)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: customer_snapshot'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT order_id,customer_id,status,purchased_at,approved_at,delivered_to_carrier_at,delivered_to_customer_at,estimated_delivery_at,source,source_loaded_at FROM core.orders EXCEPT ALL SELECT order_id,customer_id,status,purchased_at,approved_at,delivered_to_carrier_at,delivered_to_customer_at,estimated_delivery_at,source,source_loaded_at FROM stage_orders) UNION ALL (SELECT order_id,customer_id,status,purchased_at,approved_at,delivered_to_carrier_at,delivered_to_customer_at,estimated_delivery_at,source,source_loaded_at FROM stage_orders EXCEPT ALL SELECT order_id,customer_id,status,purchased_at,approved_at,delivered_to_carrier_at,delivered_to_customer_at,estimated_delivery_at,source,source_loaded_at FROM core.orders)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: orders'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT category_id,category_name_pt,category_name_en,source,translation_source_loaded_at FROM core.category EXCEPT ALL SELECT category_id,category_name_pt,category_name_en,source,translation_source_loaded_at FROM stage_category) UNION ALL (SELECT category_id,category_name_pt,category_name_en,source,translation_source_loaded_at FROM stage_category EXCEPT ALL SELECT category_id,category_name_pt,category_name_en,source,translation_source_loaded_at FROM core.category)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: category'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT product_id,category_id,photo_count,weight_g,length_cm,height_cm,width_cm,source,source_loaded_at,name_length,description_length FROM core.product EXCEPT ALL SELECT product_id,category_id,photo_count,weight_g,length_cm,height_cm,width_cm,source,source_loaded_at,name_length,description_length FROM stage_product) UNION ALL (SELECT product_id,category_id,photo_count,weight_g,length_cm,height_cm,width_cm,source,source_loaded_at,name_length,description_length FROM stage_product EXCEPT ALL SELECT product_id,category_id,photo_count,weight_g,length_cm,height_cm,width_cm,source,source_loaded_at,name_length,description_length FROM core.product)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: product'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT seller_id,zip_code_prefix,city,state,source,source_loaded_at FROM core.seller EXCEPT ALL SELECT seller_id,zip_code_prefix,city,state,source,source_loaded_at FROM stage_seller) UNION ALL (SELECT seller_id,zip_code_prefix,city,state,source,source_loaded_at FROM stage_seller EXCEPT ALL SELECT seller_id,zip_code_prefix,city,state,source,source_loaded_at FROM core.seller)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: seller'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT order_item_id,order_id,item_number,product_id,seller_id,shipping_limit_at,price,freight_value,source,source_loaded_at FROM core.order_item EXCEPT ALL SELECT order_item_id,order_id,item_number,product_id,seller_id,shipping_limit_at,price,freight_value,source,source_loaded_at FROM stage_order_item) UNION ALL (SELECT order_item_id,order_id,item_number,product_id,seller_id,shipping_limit_at,price,freight_value,source,source_loaded_at FROM stage_order_item EXCEPT ALL SELECT order_item_id,order_id,item_number,product_id,seller_id,shipping_limit_at,price,freight_value,source,source_loaded_at FROM core.order_item)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: order_item'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT order_id,payment_sequential,payment_type,installment_count,payment_value,source,source_loaded_at FROM core.order_payment EXCEPT ALL SELECT order_id,payment_sequential,payment_type,installment_count,payment_value,source,source_loaded_at FROM stage_order_payment) UNION ALL (SELECT order_id,payment_sequential,payment_type,installment_count,payment_value,source,source_loaded_at FROM stage_order_payment EXCEPT ALL SELECT order_id,payment_sequential,payment_type,installment_count,payment_value,source,source_loaded_at FROM core.order_payment)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: order_payment'; END IF; END $$;
DO $$ BEGIN IF EXISTS ((SELECT order_id,review_id,score,comment_title,comment_message,created_at,submitted_at,source,source_loaded_at FROM core.order_review EXCEPT ALL SELECT order_id,review_id,score,comment_title,comment_message,created_at,submitted_at,source,source_loaded_at FROM stage_order_review) UNION ALL (SELECT order_id,review_id,score,comment_title,comment_message,created_at,submitted_at,source,source_loaded_at FROM stage_order_review EXCEPT ALL SELECT order_id,review_id,score,comment_title,comment_message,created_at,submitted_at,source,source_loaded_at FROM core.order_review)) THEN RAISE EXCEPTION 'Source-to-core conservation failed: order_review'; END IF; END $$;
DO $$ BEGIN
 IF (SELECT count(*) FROM mart.order_totals)<>(SELECT count(*) FROM core.orders)
 OR (SELECT count(*) FROM mart.order_item_enriched)<>(SELECT count(*) FROM core.order_item)
 OR (SELECT sum(price) FROM mart.order_item_enriched) IS DISTINCT FROM (SELECT sum(price) FROM core.order_item)
 OR (SELECT sum(freight_value) FROM mart.order_item_enriched) IS DISTINCT FROM (SELECT sum(freight_value) FROM core.order_item)
 OR (SELECT sum(items_subtotal) FROM mart.order_totals) IS DISTINCT FROM (SELECT sum(price) FROM core.order_item)
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
   WHERE (n.nspname=pg_my_temp_schema()::regnamespace::text AND c.relname IN ('answer_1','answer_2','answer_3','answer_4','answer_5','answer_6','answer_7','answer_8','answer_9a','answer_9b','answer_10')) OR n.nspname='mart' AND c.relname IN ('order_totals','order_item_enriched','buyer_kpi','seller_kpi','city_delivery_kpi','order_review_selected','product_recommendation')
   UNION
   SELECT d.refobjid FROM dependencies v JOIN pg_rewrite r ON r.ev_class=v.oid
   JOIN pg_depend d ON d.classid='pg_rewrite'::regclass AND d.objid=r.oid
   WHERE d.refclassid='pg_class'::regclass AND d.refobjid<>v.oid
  ) SELECT FROM dependencies d JOIN pg_class c ON c.oid=d.oid JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname NOT IN ('core','mart') AND NOT (c.relnamespace=pg_my_temp_schema() AND c.relname IN ('answer_1','answer_2','answer_3','answer_4','answer_5','answer_6','answer_7','answer_8','answer_9a','answer_9b','answer_10'))
 ) THEN RAISE EXCEPTION 'Unexpected mart relation dependency outside core/mart'; END IF;
END $$;


CREATE FUNCTION pg_temp.assert_same(actual text, expected text, label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE differs boolean;
BEGIN
 EXECUTE format('SELECT EXISTS (((%s) EXCEPT ALL (%s)) UNION ALL ((%s) EXCEPT ALL (%s)))',actual,expected,expected,actual) INTO differs;
 IF differs THEN RAISE EXCEPTION 'Conservation/answer check failed: %',label; END IF;
END $$;
SELECT pg_temp.assert_same($actual$SELECT order_id FROM mart.order_totals$actual$,$expected$SELECT order_id FROM core.orders$expected$,'order IDs');
SELECT pg_temp.assert_same($actual$SELECT order_item_id FROM mart.order_item_enriched$actual$,$expected$SELECT order_item_id FROM core.order_item$expected$,'item IDs');
SELECT pg_temp.assert_same($actual$SELECT buyer_id,ordered_orders_count,delivered_orders_count,is_repeat_buyer,first_order_at,last_order_at FROM mart.buyer_kpi$actual$,$expected$SELECT c.buyer_id,count(DISTINCT o.order_id),count(DISTINCT o.order_id) FILTER(WHERE status='delivered'),count(DISTINCT o.order_id)>=2,min(purchased_at),max(purchased_at) FROM core.orders o JOIN core.customer_snapshot c USING(customer_id) GROUP BY c.buyer_id$expected$,'buyers');
SELECT pg_temp.assert_same($actual$SELECT seller_id FROM mart.seller_kpi$actual$,$expected$SELECT seller_id FROM core.seller$expected$,'seller IDs');
SELECT pg_temp.assert_same($actual$SELECT order_id,review_id,score,created_at,submitted_at FROM mart.order_review_selected$actual$,$expected$SELECT DISTINCT ON(order_id) order_id,review_id,score,created_at,submitted_at FROM core.order_review ORDER BY order_id,submitted_at DESC NULLS LAST,created_at DESC NULLS LAST,review_id ASC$expected$,'selected reviews');
SELECT pg_temp.assert_same($actual$SELECT * FROM answer_6$actual$,$expected$SELECT o.purchased_at::date,i.price,count(*) FROM core.order_item i JOIN core.orders o USING(order_id) WHERE o.status='delivered' AND i.product_id=(SELECT x.product_id FROM core.order_item x JOIN core.orders y USING(order_id) WHERE y.status='delivered' GROUP BY x.product_id ORDER BY count(DISTINCT x.price) DESC,x.product_id LIMIT 1) GROUP BY o.purchased_at::date,i.price$expected$,'Q6 global product, day and price');
SELECT pg_temp.assert_same($actual$SELECT * FROM answer_7$actual$,$expected$SELECT customer_state,count(*),round(avg(delivery_days),6),round(100.0*count(*) FILTER(WHERE is_late)/nullif(count(*) FILTER(WHERE is_late_eligible),0),6) FROM mart.order_totals WHERE status='delivered' GROUP BY customer_state HAVING count(*)>=500$expected$,'Q7 direct weighted delivery');
SELECT pg_temp.assert_same($actual$SELECT status,order_count,orders_without_items FROM answer_8$actual$,$expected$SELECT s.status,count(o.order_id),count(o.order_id) FILTER(WHERE NOT EXISTS(SELECT FROM core.order_item i WHERE i.order_id=o.order_id)) FROM unnest(enum_range(NULL::core.order_status)) s(status) LEFT JOIN core.orders o USING(status) GROUP BY s.status$expected$,'Q8 counts and missing items');
SELECT pg_temp.assert_same($actual$SELECT * FROM answer_9a$actual$,$expected$SELECT c.state,count(p.order_id),sum(p.payment_value)::numeric(18,2),round(avg(p.installment_count),6) FROM core.customer_snapshot c JOIN core.orders o USING(customer_id) JOIN core.order_payment p USING(order_id) WHERE o.purchased_at>=timestamp '2018-01-01' AND o.purchased_at<timestamp '2019-01-01' GROUP BY c.state$expected$,'Q9a payment facts');
SELECT pg_temp.assert_same($actual$SELECT * FROM answer_9b$actual$,$expected$SELECT t.payment_type,count(p.order_id),round(avg(p.installment_count),6) FROM unnest(enum_range(NULL::core.payment_type)) t(payment_type) LEFT JOIN core.order_payment p USING(payment_type) GROUP BY t.payment_type$expected$,'Q9b full snapshot and installments');
SELECT pg_temp.assert_same($actual$SELECT * FROM answer_10$actual$,$expected$SELECT s.score,count(o.order_id),round(avg(extract(epoch FROM(o.delivered_to_customer_at-o.purchased_at))/86400.0),6),round(100.0*count(o.order_id) FILTER(WHERE o.delivered_to_customer_at::date>o.estimated_delivery_at::date)/nullif(count(o.order_id) FILTER(WHERE o.delivered_to_customer_at IS NOT NULL AND o.estimated_delivery_at IS NOT NULL),0),6) FROM generate_series(1,5) s(score) LEFT JOIN (core.orders o JOIN (SELECT DISTINCT ON(order_id) order_id,score FROM core.order_review ORDER BY order_id,submitted_at DESC NULLS LAST,created_at DESC NULLS LAST,review_id) r USING(order_id)) ON r.score=s.score AND o.status='delivered' GROUP BY s.score$expected$,'Q10 selected review and independent denominators');
SELECT pg_temp.assert_same(
$actual$SELECT * FROM mart.seller_kpi$actual$,
$expected$SELECT s.seller_id,count(DISTINCT i.order_id),
 count(DISTINCT i.order_id) FILTER(WHERE o.status='delivered'),count(i.order_item_id),
 count(i.order_item_id) FILTER(WHERE o.status='delivered'),
 coalesce(sum(i.price) FILTER(WHERE o.status='delivered'),0)::numeric(18,2),
 count(DISTINCT i.order_id) FILTER(WHERE o.status='canceled'),
 count(DISTINCT i.order_id) FILTER(WHERE o.status='unavailable')
 FROM core.order_item i JOIN core.orders o USING(order_id) RIGHT JOIN core.seller s USING(seller_id)
 GROUP BY s.seller_id$expected$,'seller KPI all fields');
DO $$ BEGIN
 IF EXISTS(SELECT FROM mart.order_totals t JOIN core.orders o USING(order_id)
 WHERE t.delivery_days IS DISTINCT FROM CASE WHEN o.status='delivered' AND o.purchased_at IS NOT NULL AND o.delivered_to_customer_at IS NOT NULL
 THEN extract(epoch FROM(o.delivered_to_customer_at-o.purchased_at))/86400.0 END
 OR t.is_late IS DISTINCT FROM CASE WHEN o.status='delivered' AND o.delivered_to_customer_at IS NOT NULL AND o.estimated_delivery_at IS NOT NULL
 THEN o.delivered_to_customer_at::date>o.estimated_delivery_at::date END) THEN
 RAISE EXCEPTION 'Delivery policy mismatch'; END IF;
 IF (SELECT sum(freight_total) FROM mart.order_totals) IS DISTINCT FROM (SELECT sum(freight_value) FROM core.order_item)
 OR (SELECT sum(order_total) FROM mart.order_totals) IS DISTINCT FROM (SELECT sum(price+freight_value) FROM core.order_item) THEN
 RAISE EXCEPTION 'Order money conservation failed'; END IF;
END $$;
DO $$ BEGIN
 IF (SELECT count(*) FROM information_schema.tables WHERE table_schema='core' AND table_type='BASE TABLE')<>9
 OR (SELECT count(*) FROM information_schema.columns WHERE table_schema='core')<>66
 OR (SELECT count(*) FROM information_schema.views WHERE table_schema='mart')<>7 THEN
 RAISE EXCEPTION 'Expected exactly 9 core tables, 66 columns and 7 mart views'; END IF;
 IF EXISTS(SELECT FROM mart.order_totals WHERE has_items<>(item_count>0) OR unit_count<>item_count
 OR has_payments<>(payment_count>0) OR (items_subtotal IS NULL)<>NOT has_items
 OR (freight_total IS NULL)<>NOT has_items OR (order_total IS NULL)<>NOT has_items
 OR (payment_value IS NULL)<>NOT has_payments
 OR (delivery_days IS NULL)<>NOT is_duration_eligible OR (is_late IS NULL)<>NOT is_late_eligible) THEN
 RAISE EXCEPTION 'Missing facts or eligibility incorrectly represented'; END IF;
 IF (SELECT coalesce(sum(ordered_units_count),0) FROM mart.seller_kpi) IS DISTINCT FROM (SELECT count(*)::numeric FROM core.order_item)
 OR (SELECT coalesce(sum(delivered_revenue),0) FROM mart.seller_kpi) IS DISTINCT FROM
 (SELECT coalesce(sum(i.price),0) FROM core.order_item i JOIN core.orders o USING(order_id) WHERE status='delivered') THEN
 RAISE EXCEPTION 'Seller KPI fanout'; END IF;
 IF (SELECT sum(order_count) FROM answer_8)<>(SELECT count(*) FROM core.orders)
 OR (SELECT sum(orders_without_items) FROM answer_8)<>(SELECT count(*) FROM core.orders o WHERE NOT EXISTS(SELECT FROM core.order_item i WHERE i.order_id=o.order_id))
 OR ((SELECT count(*) FROM core.orders)>0 AND abs((SELECT sum(order_share_percent) FROM answer_8)-100)>0.000004)
 OR (SELECT sum(payment_count) FROM answer_9b)<>(SELECT count(*) FROM core.order_payment)
 OR (SELECT sum(order_count) FROM answer_10)<>(SELECT count(*) FROM core.orders o WHERE status='delivered' AND EXISTS(SELECT FROM core.order_review r WHERE r.order_id=o.order_id)) THEN
 RAISE EXCEPTION 'Final answer population mismatch'; END IF;
END $$;

SELECT pg_temp.assert_same('SELECT * FROM raw_before',$raw$SELECT 'orders' AS name,count(*) AS rows,md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY md5(to_jsonb(r)::text) COLLATE "C"),'')) AS fingerprint FROM raw.orders r UNION ALL SELECT 'order_items' AS name,count(*) AS rows,md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY md5(to_jsonb(r)::text) COLLATE "C"),'')) AS fingerprint FROM raw.order_items r UNION ALL SELECT 'order_payments' AS name,count(*) AS rows,md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY md5(to_jsonb(r)::text) COLLATE "C"),'')) AS fingerprint FROM raw.order_payments r UNION ALL SELECT 'order_reviews' AS name,count(*) AS rows,md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY md5(to_jsonb(r)::text) COLLATE "C"),'')) AS fingerprint FROM raw.order_reviews r UNION ALL SELECT 'products' AS name,count(*) AS rows,md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY md5(to_jsonb(r)::text) COLLATE "C"),'')) AS fingerprint FROM raw.products r UNION ALL SELECT 'sellers' AS name,count(*) AS rows,md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY md5(to_jsonb(r)::text) COLLATE "C"),'')) AS fingerprint FROM raw.sellers r UNION ALL SELECT 'customers' AS name,count(*) AS rows,md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY md5(to_jsonb(r)::text) COLLATE "C"),'')) AS fingerprint FROM raw.customers r UNION ALL SELECT 'product_category_translation' AS name,count(*) AS rows,md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY md5(to_jsonb(r)::text) COLLATE "C"),'')) AS fingerprint FROM raw.product_category_translation r$raw$,'raw unchanged');
DO $$ BEGIN
 IF EXISTS(SELECT FROM mart.product_recommendation WHERE product_id=recommended_product_id
 OR shared_orders<2 OR recommendation_score<=0 OR recommendation_score>1 OR calculated_at IS NOT NULL)
 OR EXISTS(SELECT FROM mart.product_recommendation GROUP BY product_id,recommended_product_id HAVING count(*)>1)
 OR EXISTS(SELECT FROM mart.product_recommendation GROUP BY product_id HAVING count(*)>5) THEN
 RAISE EXCEPTION 'Invalid co-purchase recommendations'; END IF;
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
 SELECT count(*) n,sum(item_count) items,sum(items_subtotal) revenue,sum(freight_total) freight,
        sum(order_total) value,round(avg(order_total),12) aov,round(avg(item_count),12) aitems
 INTO q3 FROM mart.order_totals WHERE status='delivered';
 IF (q3.n,q3.items,q3.revenue,q3.freight,q3.value,q3.aov,q3.aitems) IS DISTINCT FROM
    (96478::bigint,110197::numeric,13221498.11,2202965.54,15424463.65,159.875449843488,1.142198221356) THEN
  RAISE EXCEPTION 'Reviewed Q3 control differs: %',q3; END IF;
 IF (SELECT count(*) FROM mart.order_totals WHERE status='delivered' AND purchased_at>=timestamp '2016-09-01' AND purchased_at<timestamp '2018-09-01')<>96478
 OR (SELECT coalesce(sum(items_subtotal),0) FROM mart.order_totals WHERE status='delivered' AND purchased_at>=timestamp '2016-11-01' AND purchased_at<timestamp '2016-12-01')<>0 THEN
  RAISE EXCEPTION 'Reviewed Q1 date window control differs'; END IF;
 SELECT replace(seller_id::text,'-','') id,seller_city city,seller_state state,count(DISTINCT order_id) orders,
        count(*) units,sum(price) revenue INTO top_seller FROM mart.order_item_enriched WHERE status='delivered'
 GROUP BY seller_id,seller_city,seller_state ORDER BY revenue DESC,seller_id LIMIT 1;
 IF (top_seller.id,top_seller.city,top_seller.state,top_seller.orders,top_seller.units,top_seller.revenue) IS DISTINCT FROM
 ('4869f7a5dfa277a7dca6462dcf3b52b2'::text,'guariba'::text,'SP'::text,1124::bigint,1148::bigint,226987.93) THEN
  RAISE EXCEPTION 'Reviewed Q2 control differs'; END IF;
 SELECT count(*) n,count(*) FILTER(WHERE is_repeat_buyer) repeats,
  round(100.0*count(*) FILTER(WHERE is_repeat_buyer)/nullif(count(*),0),12) share
 INTO q4 FROM mart.buyer_kpi;
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

DO $$ BEGIN
 IF (SELECT count(*) FROM answer_1)<>24 OR (SELECT count(*) FROM answer_1 WHERE revenue=0)<>1
 OR (SELECT sum(revenue) FROM answer_1)<>13221498.11
 OR (SELECT count(*) FROM answer_2)<>10 OR (SELECT max(revenue) FROM answer_2)<>226987.93
 OR (SELECT average_order_value FROM answer_3)<>159.88
 OR (SELECT customer_count FROM answer_4)<>96096 OR (SELECT repeat_customer_share_pct FROM answer_4)<>3.12
 OR (SELECT count(*) FROM answer_5)<>74 OR (SELECT max(revenue) FROM answer_5)<>1233131.72
 OR (SELECT sum(revenue) FROM answer_5)<>13221498.11 THEN
 RAISE EXCEPTION 'Actual answer Q1-Q5 acceptance control failed'; END IF;
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
 'payment_item_value_mismatch',(SELECT count(*) FROM mart.order_totals WHERE has_items AND has_payments AND order_total<>payment_value),
 'delivered_negative_duration',(SELECT count(*) FROM mart.order_totals WHERE delivery_days<0),
 'delivered_missing_delivery_date',(SELECT count(*) FROM core.orders WHERE status='delivered' AND delivered_to_customer_at IS NULL),
 'untranslated_categories',(SELECT jsonb_agg(category_name_pt ORDER BY category_name_pt) FROM core.category WHERE category_name_pt IS NOT NULL AND category_name_en IS NULL),
 'changed_existing_payment_keys',(SELECT count(*) FROM changed_payments)
 )) AS report) TO STDOUT WITH (FORMAT csv, HEADER true);
\echo __CAPIBARA_END_report
