
-- 1. Check and lock the existing raw tables.
-- Inspected organizer DDL at 3da32d149bfa14dca3fdb0c5863d0771c38efbfc.
CREATE TEMP TABLE expected_raw(table_name text,column_name text,type_name text);
INSERT INTO expected_raw VALUES
('orders','order_id','text'),
('orders','customer_id','text'),
('orders','order_status','text'),
('orders','order_purchase_timestamp','text'),
('orders','order_approved_at','text'),
('orders','order_delivered_carrier_date','text'),
('orders','order_delivered_customer_date','text'),
('orders','order_estimated_delivery_date','text'),
('orders','_source_file','text'),
('orders','_loaded_at','timestamp with time zone'),
('order_items','order_id','text'),
('order_items','order_item_id','text'),
('order_items','product_id','text'),
('order_items','seller_id','text'),
('order_items','shipping_limit_date','text'),
('order_items','price','text'),
('order_items','freight_value','text'),
('order_items','_source_file','text'),
('order_items','_loaded_at','timestamp with time zone'),
('order_payments','order_id','text'),
('order_payments','payment_sequential','text'),
('order_payments','payment_type','text'),
('order_payments','payment_installments','text'),
('order_payments','payment_value','text'),
('order_payments','_source_file','text'),
('order_payments','_loaded_at','timestamp with time zone'),
('order_reviews','review_id','text'),
('order_reviews','order_id','text'),
('order_reviews','review_score','text'),
('order_reviews','review_comment_title','text'),
('order_reviews','review_comment_message','text'),
('order_reviews','review_creation_date','text'),
('order_reviews','review_answer_timestamp','text'),
('order_reviews','_source_file','text'),
('order_reviews','_loaded_at','timestamp with time zone'),
('products','product_id','text'),
('products','product_category_name','text'),
('products','product_name_lenght','text'),
('products','product_description_lenght','text'),
('products','product_photos_qty','text'),
('products','product_weight_g','text'),
('products','product_length_cm','text'),
('products','product_height_cm','text'),
('products','product_width_cm','text'),
('products','_source_file','text'),
('products','_loaded_at','timestamp with time zone'),
('sellers','seller_id','text'),
('sellers','seller_zip_code_prefix','text'),
('sellers','seller_city','text'),
('sellers','seller_state','text'),
('sellers','_source_file','text'),
('sellers','_loaded_at','timestamp with time zone'),
('customers','customer_id','text'),
('customers','customer_unique_id','text'),
('customers','customer_zip_code_prefix','text'),
('customers','customer_city','text'),
('customers','customer_state','text'),
('customers','_source_file','text'),
('customers','_loaded_at','timestamp with time zone'),
('product_category_translation','product_category_name','text'),
('product_category_translation','product_category_name_english','text'),
('product_category_translation','_source_file','text'),
('product_category_translation','_loaded_at','timestamp with time zone');
DO $$ BEGIN
 IF EXISTS (SELECT * FROM expected_raw EXCEPT
  SELECT table_name::text,column_name::text,data_type::text FROM information_schema.columns WHERE table_schema='raw') THEN
  RAISE EXCEPTION 'Missing/incompatible raw columns; supply organizer raw schema first (no raw initialization occurs in this build)'; END IF;
END $$;
LOCK TABLE raw.orders,raw.order_items,raw.order_payments,raw.order_reviews,raw.products,
 raw.sellers,raw.customers,raw.product_category_translation IN SHARE MODE;

-- 2. Strict conversions before narrowing types.
-- These helpers live only in this psql session. No persistent data-cleaning API.
CREATE FUNCTION pg_temp.optional(v text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE WHEN v IS NULL OR v ~ '^[[:space:]]*$' THEN NULL ELSE v END
$$;
CREATE FUNCTION pg_temp.required_name(v text, label text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
 IF pg_temp.optional(v) IS NULL THEN RAISE EXCEPTION 'Missing required value: %',label; END IF;
 RETURN v;
END $$;
CREATE FUNCTION pg_temp.source_uuid(v text, label text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
 IF v IS NULL OR v !~ '^[0-9a-f]{32}$' THEN
  RAISE EXCEPTION 'Invalid source key at %: expected exact lowercase 32-hex, got %',label,v;
 END IF;
 RETURN v::uuid;
END $$;
CREATE FUNCTION pg_temp.postal(v text, label text) RETURNS varchar LANGUAGE plpgsql AS $$
BEGIN
 IF pg_temp.optional(v) IS NULL THEN RETURN NULL; END IF;
 IF length(v)>5 THEN RAISE EXCEPTION 'Postal prefix too long at %: %',label,v; END IF;
 RETURN v;
END $$;
CREATE FUNCTION pg_temp.exact_numeric(v text, label text, p integer, s integer,
 lo numeric, hi numeric, required boolean) RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE n numeric;
BEGIN
 IF pg_temp.optional(v) IS NULL THEN
  IF required THEN RAISE EXCEPTION 'Missing required number at %',label; END IF;
  RETURN NULL;
 END IF;
 IF v !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$' THEN
  RAISE EXCEPTION 'Invalid finite decimal at %: %',label,v; END IF;
 BEGIN n:=v::numeric;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Invalid/out-of-range decimal at %: %',label,v;
 END;
 IF n<>round(n,s) OR abs(n)>=power(10::numeric,p-s) OR n<lo OR (hi IS NOT NULL AND n>hi) THEN
  RAISE EXCEPTION 'Decimal precision/scale/range violation at %: % (numeric(%,%), min %, max %)',label,v,p,s,lo,hi;
 END IF;
 RETURN n;
END $$;
CREATE FUNCTION pg_temp.local_timestamp(v text, label text, required boolean)
 RETURNS timestamp LANGUAGE plpgsql AS $$
DECLARE t timestamp;
BEGIN
 IF pg_temp.optional(v) IS NULL THEN
  IF required THEN RAISE EXCEPTION 'Missing required timestamp at %',label; END IF;
  RETURN NULL;
 END IF;
 -- Reject timezone suffixes, ambiguous dates, infinities and fractional rounding.
 IF v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]{1,6})?$'
 OR substring(v,12,2)::integer>23 OR substring(v,15,2)::integer>59 OR substring(v,18,2)::integer>59 THEN
  RAISE EXCEPTION 'Invalid unambiguous local timestamp at %: %',label,v; END IF;
 BEGIN t:=v::timestamp;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Invalid local calendar timestamp at %: %',label,v;
 END;
 RETURN t;
END $$;
CREATE FUNCTION pg_temp.enum_value(v text, label text, allowed text[]) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
 IF v IS NULL OR NOT (v=ANY(allowed)) THEN
  RAISE EXCEPTION 'Unexpected enum at %: %. Allowed: %. Publication blocked; explicit contract/migration decision required.',label,v,allowed;
 END IF;
 RETURN v;
END $$;

-- 3. Stage every source row; validate keys and foreign keys.
-- Staging uses a consistent raw snapshot; never mutate raw.
CREATE TEMP TABLE stage_customer_snapshot ON COMMIT DROP AS SELECT
    pg_temp.source_uuid(customer_id,'raw.customers.customer_id') AS customer_id,
    pg_temp.source_uuid(customer_unique_id,'raw.customers.customer_unique_id') AS buyer_id,
    pg_temp.postal(customer_zip_code_prefix,'raw.customers.customer_zip_code_prefix') AS zip_code_prefix,
    customer_city AS city,
    customer_state AS state,
    _source_file AS source,
    _loaded_at AS source_loaded_at
FROM raw.customers;
CREATE TEMP TABLE stage_orders ON COMMIT DROP AS SELECT
    pg_temp.source_uuid(order_id,'raw.orders.order_id') AS order_id,
    pg_temp.source_uuid(customer_id,'raw.orders.customer_id') AS customer_id,
    pg_temp.enum_value(order_status,'raw.orders.order_status',ARRAY['approved','canceled','created','delivered','invoiced','processing','shipped','unavailable'])::core.order_status AS status,
    pg_temp.local_timestamp(order_purchase_timestamp,'raw.orders.order_purchase_timestamp',true) AS purchased_at,
    pg_temp.local_timestamp(order_approved_at,'raw.orders.order_approved_at',false) AS approved_at,
    pg_temp.local_timestamp(order_delivered_carrier_date,'raw.orders.order_delivered_carrier_date',false) AS delivered_to_carrier_at,
    pg_temp.local_timestamp(order_delivered_customer_date,'raw.orders.order_delivered_customer_date',false) AS delivered_to_customer_at,
    pg_temp.local_timestamp(order_estimated_delivery_date,'raw.orders.order_estimated_delivery_date',false) AS estimated_delivery_at,
    _source_file AS source,
    _loaded_at AS source_loaded_at
FROM raw.orders;
CREATE TEMP TABLE stage_product ON COMMIT DROP AS SELECT
    pg_temp.source_uuid(product_id,'raw.products.product_id') AS product_id,
    public.uuid_generate_v5('e92ade3a-37ee-5319-848f-948b075be7b0'::uuid,CASE WHEN pg_temp.optional(product_category_name) IS NULL THEN 'category:unknown' ELSE 'category:pt:'||product_category_name END) AS category_id,
    pg_temp.exact_numeric(product_photos_qty,'raw.products.product_photos_qty',10,0,0,2147483647,false)::integer AS photo_count,
    pg_temp.exact_numeric(product_weight_g,'raw.products.product_weight_g',12,3,0,NULL,false)::numeric(12,3) AS weight_g,
    pg_temp.exact_numeric(product_length_cm,'raw.products.product_length_cm',12,3,0,NULL,false)::numeric(12,3) AS length_cm,
    pg_temp.exact_numeric(product_height_cm,'raw.products.product_height_cm',12,3,0,NULL,false)::numeric(12,3) AS height_cm,
    pg_temp.exact_numeric(product_width_cm,'raw.products.product_width_cm',12,3,0,NULL,false)::numeric(12,3) AS width_cm,
    _source_file AS source,
    _loaded_at AS source_loaded_at
FROM raw.products;
CREATE TEMP TABLE stage_seller ON COMMIT DROP AS SELECT
    pg_temp.source_uuid(seller_id,'raw.sellers.seller_id') AS seller_id,
    pg_temp.postal(seller_zip_code_prefix,'raw.sellers.seller_zip_code_prefix') AS zip_code_prefix,
    seller_city AS city,
    seller_state AS state,
    _source_file AS source,
    _loaded_at AS source_loaded_at
FROM raw.sellers;
CREATE TEMP TABLE stage_order_item ON COMMIT DROP AS SELECT
    public.uuid_generate_v5('e92ade3a-37ee-5319-848f-948b075be7b0'::uuid,'order-item:'||replace(pg_temp.source_uuid(order_id,'raw.order_items.order_id')::text,'-','')||':'||pg_temp.exact_numeric(order_item_id,'raw.order_items.order_item_id',10,0,1,2147483647,true)::integer::text) AS order_item_id,
    pg_temp.source_uuid(order_id,'raw.order_items.order_id') AS order_id,
    pg_temp.exact_numeric(order_item_id,'raw.order_items.order_item_id',10,0,1,2147483647,true)::integer AS item_number,
    pg_temp.source_uuid(product_id,'raw.order_items.product_id') AS product_id,
    pg_temp.source_uuid(seller_id,'raw.order_items.seller_id') AS seller_id,
    pg_temp.local_timestamp(shipping_limit_date,'raw.order_items.shipping_limit_date',false) AS shipping_limit_at,
    pg_temp.exact_numeric(price,'raw.order_items.price',18,2,0,NULL,true)::numeric(18,2) AS price,
    pg_temp.exact_numeric(freight_value,'raw.order_items.freight_value',18,2,0,NULL,true)::numeric(18,2) AS freight_value,
    _source_file AS source,
    _loaded_at AS source_loaded_at
FROM raw.order_items;
CREATE TEMP TABLE stage_order_payment ON COMMIT DROP AS SELECT
    pg_temp.source_uuid(order_id,'raw.order_payments.order_id') AS order_id,
    pg_temp.exact_numeric(payment_sequential,'raw.order_payments.payment_sequential',10,0,1,2147483647,true)::integer AS payment_sequential,
    pg_temp.enum_value(payment_type,'raw.order_payments.payment_type',ARRAY['boleto','credit_card','debit_card','not_defined','voucher'])::core.payment_type AS payment_type,
    pg_temp.exact_numeric(payment_installments,'raw.order_payments.payment_installments',10,0,0,2147483647,false)::integer AS installment_count,
    pg_temp.exact_numeric(payment_value,'raw.order_payments.payment_value',18,2,0,NULL,true)::numeric(18,2) AS payment_value,
    _source_file AS source,
    _loaded_at AS source_loaded_at
FROM raw.order_payments;
CREATE TEMP TABLE stage_order_review ON COMMIT DROP AS SELECT
    pg_temp.source_uuid(order_id,'raw.order_reviews.order_id') AS order_id,
    pg_temp.source_uuid(review_id,'raw.order_reviews.review_id') AS review_id,
    pg_temp.exact_numeric(review_score,'raw.order_reviews.review_score',5,0,1,5,true)::smallint AS score,
    review_comment_title AS comment_title,
    review_comment_message AS comment_message,
    pg_temp.local_timestamp(review_creation_date,'raw.order_reviews.review_creation_date',false) AS created_at,
    pg_temp.local_timestamp(review_answer_timestamp,'raw.order_reviews.review_answer_timestamp',false) AS answered_at,
    _source_file AS source,
    _loaded_at AS source_loaded_at
FROM raw.order_reviews;
-- Translation keys must be nonempty and unique before joining.
CREATE TEMP TABLE stage_translation ON COMMIT DROP AS
SELECT pg_temp.required_name(product_category_name,'raw.product_category_translation.product_category_name') AS category_name_pt,
       pg_temp.optional(product_category_name_english) AS category_name_en, _source_file AS source,
       _loaded_at AS translation_source_loaded_at
FROM raw.product_category_translation;
DO $$ BEGIN
 IF EXISTS (SELECT FROM stage_translation GROUP BY category_name_pt HAVING count(*)>1) THEN
  RAISE EXCEPTION 'Duplicate translation key in raw.product_category_translation'; END IF;
END $$;
CREATE TEMP TABLE stage_buyer ON COMMIT DROP AS SELECT DISTINCT buyer_id FROM stage_customer_snapshot;
CREATE TEMP TABLE stage_category ON COMMIT DROP AS
SELECT public.uuid_generate_v5('e92ade3a-37ee-5319-848f-948b075be7b0'::uuid,'category:pt:'||c.name) AS category_id,
       c.name AS category_name_pt, t.category_name_en, t.source, t.translation_source_loaded_at
FROM (SELECT product_category_name AS name FROM raw.products WHERE pg_temp.optional(product_category_name) IS NOT NULL
      UNION SELECT category_name_pt FROM stage_translation) c
LEFT JOIN stage_translation t ON t.category_name_pt=c.name
UNION ALL SELECT public.uuid_generate_v5('e92ade3a-37ee-5319-848f-948b075be7b0'::uuid,'category:unknown'),NULL,NULL,NULL,NULL::timestamptz;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_buyer GROUP BY buyer_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key buyer(buyer_id) after validated conversion'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_customer_snapshot GROUP BY customer_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key customer_snapshot(customer_id) after validated conversion'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_orders GROUP BY order_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key orders(order_id) after validated conversion'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_category GROUP BY category_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key category(category_id) after validated conversion'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_product GROUP BY product_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key product(product_id) after validated conversion'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_seller GROUP BY seller_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key seller(seller_id) after validated conversion'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_order_item GROUP BY order_item_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key order_item(order_item_id) after validated conversion'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_order_item GROUP BY order_id, item_number HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key order_item(order_id, item_number) after validated conversion'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_order_payment GROUP BY order_id, payment_sequential HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key order_payment(order_id, payment_sequential) after validated conversion'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_order_review GROUP BY order_id, review_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate key order_review(order_id, review_id) after validated conversion'; END IF; END $$;
-- Temporary keys and fresh statistics avoid quadratic FK validation plans.
CREATE UNIQUE INDEX ON stage_buyer (buyer_id);
ANALYZE stage_buyer;
CREATE UNIQUE INDEX ON stage_customer_snapshot (customer_id);
ANALYZE stage_customer_snapshot;
CREATE UNIQUE INDEX ON stage_orders (order_id);
ANALYZE stage_orders;
CREATE UNIQUE INDEX ON stage_category (category_id);
ANALYZE stage_category;
CREATE UNIQUE INDEX ON stage_product (product_id);
ANALYZE stage_product;
CREATE UNIQUE INDEX ON stage_seller (seller_id);
ANALYZE stage_seller;
CREATE UNIQUE INDEX ON stage_order_item (order_item_id);
ANALYZE stage_order_item;
CREATE UNIQUE INDEX ON stage_order_payment (order_id,payment_sequential);
ANALYZE stage_order_payment;
CREATE UNIQUE INDEX ON stage_order_review (order_id,review_id);
ANALYZE stage_order_review;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_customer_snapshot a LEFT JOIN stage_buyer b ON a.buyer_id=b.buyer_id WHERE b.buyer_id IS NULL) THEN RAISE EXCEPTION 'Missing FK coverage: customer_snapshot.buyer_id -> buyer.buyer_id'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_orders a LEFT JOIN stage_customer_snapshot b ON a.customer_id=b.customer_id WHERE b.customer_id IS NULL) THEN RAISE EXCEPTION 'Missing FK coverage: orders.customer_id -> customer_snapshot.customer_id'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_product a LEFT JOIN stage_category b ON a.category_id=b.category_id WHERE b.category_id IS NULL) THEN RAISE EXCEPTION 'Missing FK coverage: product.category_id -> category.category_id'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_order_item a LEFT JOIN stage_orders b ON a.order_id=b.order_id WHERE b.order_id IS NULL) THEN RAISE EXCEPTION 'Missing FK coverage: order_item.order_id -> orders.order_id'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_order_item a LEFT JOIN stage_product b ON a.product_id=b.product_id WHERE b.product_id IS NULL) THEN RAISE EXCEPTION 'Missing FK coverage: order_item.product_id -> product.product_id'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_order_item a LEFT JOIN stage_seller b ON a.seller_id=b.seller_id WHERE b.seller_id IS NULL) THEN RAISE EXCEPTION 'Missing FK coverage: order_item.seller_id -> seller.seller_id'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_order_payment a LEFT JOIN stage_orders b ON a.order_id=b.order_id WHERE b.order_id IS NULL) THEN RAISE EXCEPTION 'Missing FK coverage: order_payment.order_id -> orders.order_id'; END IF; END $$;
DO $$ BEGIN IF EXISTS (SELECT FROM stage_order_review a LEFT JOIN stage_orders b ON a.order_id=b.order_id WHERE b.order_id IS NULL) THEN RAISE EXCEPTION 'Missing FK coverage: order_review.order_id -> orders.order_id'; END IF; END $$;
DO $$ BEGIN
 IF EXISTS (SELECT FROM stage_orders o LEFT JOIN stage_order_item i USING(order_id)
            WHERE o.status='delivered' AND i.order_id IS NULL) THEN
  RAISE EXCEPTION 'Incomplete delivered orders: missing item facts; answers cannot be validated'; END IF;
END $$;

-- 4. Audit payment changes under the explicit full-snapshot replacement policy.
CREATE TEMP TABLE changed_payments ON COMMIT DROP AS
SELECT s.order_id,s.payment_sequential FROM stage_order_payment s JOIN core.order_payment c
USING(order_id,payment_sequential)
WHERE (s.payment_type,s.installment_count,s.payment_value) IS DISTINCT FROM
      (c.payment_type,c.installment_count,c.payment_value);

-- 5. Replace all nine known tables inside the current transaction.
-- Explicit full-snapshot policy: validated input replaces all nine known tables.
-- Changed payment values are accepted only as part of this audited full refresh.
TRUNCATE core.buyer, core.customer_snapshot, core.orders, core.category, core.product, core.seller, core.order_item, core.order_payment, core.order_review RESTRICT;
INSERT INTO core.buyer SELECT * FROM stage_buyer;
INSERT INTO core.customer_snapshot SELECT * FROM stage_customer_snapshot;
INSERT INTO core.orders SELECT * FROM stage_orders;
INSERT INTO core.category SELECT * FROM stage_category;
INSERT INTO core.product SELECT * FROM stage_product;
INSERT INTO core.seller SELECT * FROM stage_seller;
INSERT INTO core.order_item SELECT * FROM stage_order_item;
INSERT INTO core.order_payment SELECT * FROM stage_order_payment;
INSERT INTO core.order_review SELECT * FROM stage_order_review;
-- Refresh planner statistics before validating/reading the rebuilt marts.
ANALYZE core.buyer, core.customer_snapshot, core.orders, core.category, core.product, core.seller, core.order_item, core.order_payment, core.order_review;
