-- Session-wide lock serializes this builder, including its migration transaction.
SET application_name = 'capibara_builder';
SET search_path = pg_catalog, public;
SET datestyle = 'ISO, YMD';
SET timezone = 'UTC'; -- Only metadata rendering; business timestamps remain WITHOUT time zone.
SET client_encoding = 'UTF8';
SET lock_timeout = '15s';
-- Small Docker /dev/shm may not fit several parallel hash-join plans at once.
SET max_parallel_workers_per_gather = 0;
DO $$ BEGIN
 PERFORM pg_advisory_lock(210692031,21);
 IF current_setting('server_version_num')::integer < 160000 THEN
  RAISE EXCEPTION 'PostgreSQL 16 or newer is required'; END IF;
 IF NOT EXISTS (SELECT FROM pg_available_extensions WHERE name='uuid-ossp') THEN
  RAISE EXCEPTION 'uuid-ossp unavailable; install the PostgreSQL contrib extension, random UUIDs are forbidden'; END IF;
END $$;
-- This prerequisite commits before the data-refresh transaction.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
DO $$ BEGIN
 IF to_regprocedure('public.uuid_generate_v5(uuid,text)') IS NULL THEN
  RAISE EXCEPTION 'uuid-ossp must expose public.uuid_generate_v5(uuid,text); inspect extension schema/permissions'; END IF;
 IF public.uuid_generate_v5('e92ade3a-37ee-5319-848f-948b075be7b0','category:unknown')<>'e241560a-82de-55d7-ae54-22be2eb37541'
 OR public.uuid_generate_v5('e92ade3a-37ee-5319-848f-948b075be7b0','category:pt:beleza_saude')<>'2526c832-a5aa-56c2-bc83-e3867e74188a'
 OR public.uuid_generate_v5('e92ade3a-37ee-5319-848f-948b075be7b0','order-item:0008288aa423d2a3f00fcb17cd7d8719:1')<>'e02c1f59-03a6-5b15-9cae-3a1a6b9bf8c2' THEN
  RAISE EXCEPTION 'UUIDv5 test vectors failed'; END IF;
END $$;

BEGIN ISOLATION LEVEL REPEATABLE READ;
CREATE SCHEMA IF NOT EXISTS analytics_meta;
CREATE TABLE IF NOT EXISTS analytics_meta.migrations (
    version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
SELECT NOT EXISTS (SELECT FROM analytics_meta.migrations WHERE version = '001_core_v2.1') AS install \gset
\if :install
DO $$ BEGIN
 IF EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('core','mart') AND c.relname IN
            ('buyer','customer_snapshot','orders','category','product','seller','order_item',
             'order_payment','order_review','order_totals','order_item_enriched','buyer_order_counts'))
 OR EXISTS (SELECT FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
            WHERE n.nspname='core' AND t.typname IN ('order_status','payment_type')) THEN
   RAISE EXCEPTION 'Unversioned/older Capibara objects found. Supply an explicit reviewed migration; no objects were reset.';
 END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS mart;
CREATE TYPE core.order_status AS ENUM ('approved', 'canceled', 'created', 'delivered', 'invoiced', 'processing', 'shipped', 'unavailable');
CREATE TYPE core.payment_type AS ENUM ('boleto', 'credit_card', 'debit_card', 'not_defined', 'voucher');
CREATE TABLE core.buyer (
    buyer_id uuid NOT NULL,
    PRIMARY KEY (buyer_id)
);
CREATE TABLE core.customer_snapshot (
    customer_id uuid NOT NULL,
    buyer_id uuid NOT NULL,
    zip_code_prefix character varying(5),
    city text,
    state text,
    source text,
    source_loaded_at timestamp with time zone,
    PRIMARY KEY (customer_id),
    FOREIGN KEY (buyer_id) REFERENCES core.buyer (buyer_id) ON UPDATE NO ACTION ON DELETE NO ACTION
);
CREATE TABLE core.orders (
    order_id uuid NOT NULL,
    customer_id uuid NOT NULL,
    status core.order_status NOT NULL,
    purchased_at timestamp without time zone NOT NULL,
    approved_at timestamp without time zone,
    delivered_to_carrier_at timestamp without time zone,
    delivered_to_customer_at timestamp without time zone,
    estimated_delivery_at timestamp without time zone,
    source text,
    source_loaded_at timestamp with time zone,
    PRIMARY KEY (order_id),
    FOREIGN KEY (customer_id) REFERENCES core.customer_snapshot (customer_id) ON UPDATE NO ACTION ON DELETE NO ACTION
);
CREATE TABLE core.category (
    category_id uuid NOT NULL,
    category_name_pt text,
    category_name_en text,
    source text,
    translation_source_loaded_at timestamp with time zone,
    PRIMARY KEY (category_id),
    UNIQUE (category_name_pt)
);
CREATE TABLE core.product (
    product_id uuid NOT NULL,
    category_id uuid NOT NULL,
    photo_count integer,
    weight_g numeric(12,3),
    length_cm numeric(12,3),
    height_cm numeric(12,3),
    width_cm numeric(12,3),
    source text,
    source_loaded_at timestamp with time zone,
    PRIMARY KEY (product_id),
    FOREIGN KEY (category_id) REFERENCES core.category (category_id) ON UPDATE NO ACTION ON DELETE NO ACTION
);
CREATE TABLE core.seller (
    seller_id uuid NOT NULL,
    zip_code_prefix character varying(5),
    city text,
    state text,
    source text,
    source_loaded_at timestamp with time zone,
    PRIMARY KEY (seller_id)
);
CREATE TABLE core.order_item (
    order_item_id uuid NOT NULL,
    order_id uuid NOT NULL,
    item_number integer NOT NULL,
    product_id uuid NOT NULL,
    seller_id uuid NOT NULL,
    shipping_limit_at timestamp without time zone,
    price numeric(18,2) NOT NULL,
    freight_value numeric(18,2) NOT NULL,
    source text,
    source_loaded_at timestamp with time zone,
    PRIMARY KEY (order_item_id),
    UNIQUE (order_id, item_number),
    FOREIGN KEY (order_id) REFERENCES core.orders (order_id) ON UPDATE NO ACTION ON DELETE NO ACTION,
    FOREIGN KEY (product_id) REFERENCES core.product (product_id) ON UPDATE NO ACTION ON DELETE NO ACTION,
    FOREIGN KEY (seller_id) REFERENCES core.seller (seller_id) ON UPDATE NO ACTION ON DELETE NO ACTION
);
CREATE TABLE core.order_payment (
    order_id uuid NOT NULL,
    payment_sequential integer NOT NULL,
    payment_type core.payment_type NOT NULL,
    installment_count integer,
    payment_value numeric(18,2) NOT NULL,
    source text,
    source_loaded_at timestamp with time zone,
    PRIMARY KEY (order_id, payment_sequential),
    FOREIGN KEY (order_id) REFERENCES core.orders (order_id) ON UPDATE NO ACTION ON DELETE NO ACTION
);
CREATE TABLE core.order_review (
    order_id uuid NOT NULL,
    review_id uuid NOT NULL,
    score smallint NOT NULL,
    comment_title text,
    comment_message text,
    created_at timestamp without time zone,
    answered_at timestamp without time zone,
    source text,
    source_loaded_at timestamp with time zone,
    PRIMARY KEY (order_id, review_id),
    FOREIGN KEY (order_id) REFERENCES core.orders (order_id) ON UPDATE NO ACTION ON DELETE NO ACTION
);
CREATE INDEX idx_customer_snapshot_buyer_id ON core.customer_snapshot (buyer_id);
CREATE INDEX idx_orders_customer_id ON core.orders (customer_id);
CREATE INDEX idx_orders_status_purchased_at ON core.orders (status, purchased_at);
CREATE INDEX idx_product_category_id ON core.product (category_id);
CREATE INDEX idx_order_item_product_id ON core.order_item (product_id);
CREATE INDEX idx_order_item_seller_id ON core.order_item (seller_id);
INSERT INTO analytics_meta.migrations(version) VALUES ('001_core_v2.1');
\endif


-- Fail on drift rather than treating IF NOT EXISTS as a migration.
CREATE TEMP TABLE expected_columns(table_name text, column_name text, type_name text, required boolean);
INSERT INTO expected_columns VALUES
('buyer','buyer_id','uuid',true),
('customer_snapshot','customer_id','uuid',true),
('customer_snapshot','buyer_id','uuid',true),
('customer_snapshot','zip_code_prefix','character varying(5)',false),
('customer_snapshot','city','text',false),
('customer_snapshot','state','text',false),
('customer_snapshot','source','text',false),
('customer_snapshot','source_loaded_at','timestamp with time zone',false),
('orders','order_id','uuid',true),
('orders','customer_id','uuid',true),
('orders','status','core.order_status',true),
('orders','purchased_at','timestamp without time zone',true),
('orders','approved_at','timestamp without time zone',false),
('orders','delivered_to_carrier_at','timestamp without time zone',false),
('orders','delivered_to_customer_at','timestamp without time zone',false),
('orders','estimated_delivery_at','timestamp without time zone',false),
('orders','source','text',false),
('orders','source_loaded_at','timestamp with time zone',false),
('category','category_id','uuid',true),
('category','category_name_pt','text',false),
('category','category_name_en','text',false),
('category','source','text',false),
('category','translation_source_loaded_at','timestamp with time zone',false),
('product','product_id','uuid',true),
('product','category_id','uuid',true),
('product','photo_count','integer',false),
('product','weight_g','numeric(12,3)',false),
('product','length_cm','numeric(12,3)',false),
('product','height_cm','numeric(12,3)',false),
('product','width_cm','numeric(12,3)',false),
('product','source','text',false),
('product','source_loaded_at','timestamp with time zone',false),
('seller','seller_id','uuid',true),
('seller','zip_code_prefix','character varying(5)',false),
('seller','city','text',false),
('seller','state','text',false),
('seller','source','text',false),
('seller','source_loaded_at','timestamp with time zone',false),
('order_item','order_item_id','uuid',true),
('order_item','order_id','uuid',true),
('order_item','item_number','integer',true),
('order_item','product_id','uuid',true),
('order_item','seller_id','uuid',true),
('order_item','shipping_limit_at','timestamp without time zone',false),
('order_item','price','numeric(18,2)',true),
('order_item','freight_value','numeric(18,2)',true),
('order_item','source','text',false),
('order_item','source_loaded_at','timestamp with time zone',false),
('order_payment','order_id','uuid',true),
('order_payment','payment_sequential','integer',true),
('order_payment','payment_type','core.payment_type',true),
('order_payment','installment_count','integer',false),
('order_payment','payment_value','numeric(18,2)',true),
('order_payment','source','text',false),
('order_payment','source_loaded_at','timestamp with time zone',false),
('order_review','order_id','uuid',true),
('order_review','review_id','uuid',true),
('order_review','score','smallint',true),
('order_review','comment_title','text',false),
('order_review','comment_message','text',false),
('order_review','created_at','timestamp without time zone',false),
('order_review','answered_at','timestamp without time zone',false),
('order_review','source','text',false),
('order_review','source_loaded_at','timestamp with time zone',false);
SELECT EXISTS (SELECT FROM analytics_meta.migrations WHERE version='002_core_v3.1') AS upgraded \gset
\if :upgraded
UPDATE expected_columns SET type_name='character varying(2)' WHERE column_name='state';
UPDATE expected_columns SET column_name='submitted_at' WHERE table_name='order_review' AND column_name='answered_at';
INSERT INTO expected_columns VALUES ('product','name_length','integer',false),('product','description_length','integer',false);
\endif
DO $$ BEGIN
 IF EXISTS (
  (SELECT * FROM expected_columns EXCEPT
   SELECT c.relname::text,a.attname::text,format_type(a.atttypid,a.atttypmod),a.attnotnull
   FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='core' AND c.relname IN (SELECT table_name FROM expected_columns) AND a.attnum>0 AND NOT a.attisdropped)
  UNION ALL
  (SELECT c.relname::text,a.attname::text,format_type(a.atttypid,a.atttypmod),a.attnotnull
   FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='core' AND c.relname IN (SELECT table_name FROM expected_columns) AND a.attnum>0 AND NOT a.attisdropped
   EXCEPT SELECT * FROM expected_columns)
 ) THEN RAISE EXCEPTION 'Core v2.1 column/type/nullability mismatch: explicit migration required'; END IF;
 IF EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='core' AND c.relname IN (SELECT table_name FROM expected_columns)
    AND (c.relkind <> 'r' OR c.relrowsecurity))
 OR EXISTS (SELECT FROM pg_trigger WHERE tgrelid IN (SELECT ('core.'||table_name)::regclass FROM expected_columns) AND NOT tgisinternal)
 OR EXISTS (SELECT FROM pg_attrdef WHERE adrelid IN (SELECT ('core.'||table_name)::regclass FROM expected_columns)) THEN
  RAISE EXCEPTION 'Unexpected core table kind, row security, trigger or default'; END IF;
 IF (SELECT array_agg(enumlabel::text ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid='core.order_status'::regtype) IS DISTINCT FROM ARRAY['approved','canceled','created','delivered','invoiced','processing','shipped','unavailable']::text[] THEN RAISE EXCEPTION 'Enum core.order_status mismatch: explicit migration required'; END IF;
 IF (SELECT array_agg(enumlabel::text ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid='core.payment_type'::regtype) IS DISTINCT FROM ARRAY['boleto','credit_card','debit_card','not_defined','voucher']::text[] THEN RAISE EXCEPTION 'Enum core.payment_type mismatch: explicit migration required'; END IF;
END $$;
CREATE TEMP TABLE expected_constraints(table_name text, definition text);
INSERT INTO expected_constraints VALUES
('buyer','PRIMARY KEY (buyer_id)'),
('customer_snapshot','PRIMARY KEY (customer_id)'),
('orders','PRIMARY KEY (order_id)'),
('category','PRIMARY KEY (category_id)'),
('product','PRIMARY KEY (product_id)'),
('seller','PRIMARY KEY (seller_id)'),
('order_item','PRIMARY KEY (order_item_id)'),
('order_payment','PRIMARY KEY (order_id, payment_sequential)'),
('order_review','PRIMARY KEY (order_id, review_id)'),
('category','UNIQUE (category_name_pt)'),
('order_item','UNIQUE (order_id, item_number)'),
('customer_snapshot','FOREIGN KEY (buyer_id) REFERENCES core.buyer(buyer_id)'),
('orders','FOREIGN KEY (customer_id) REFERENCES core.customer_snapshot(customer_id)'),
('product','FOREIGN KEY (category_id) REFERENCES core.category(category_id)'),
('order_item','FOREIGN KEY (order_id) REFERENCES core.orders(order_id)'),
('order_item','FOREIGN KEY (product_id) REFERENCES core.product(product_id)'),
('order_item','FOREIGN KEY (seller_id) REFERENCES core.seller(seller_id)'),
('order_payment','FOREIGN KEY (order_id) REFERENCES core.orders(order_id)'),
('order_review','FOREIGN KEY (order_id) REFERENCES core.orders(order_id)');
DO $$ BEGIN
 IF EXISTS (
  (SELECT * FROM expected_constraints EXCEPT
   SELECT c.relname::text,pg_get_constraintdef(k.oid) FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid
   WHERE k.conrelid IN (SELECT ('core.'||table_name)::regclass FROM expected_columns))
  UNION ALL
  (SELECT c.relname::text,pg_get_constraintdef(k.oid) FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid
   WHERE k.conrelid IN (SELECT ('core.'||table_name)::regclass FROM expected_columns)
   EXCEPT SELECT * FROM expected_constraints)
 ) OR EXISTS (SELECT FROM pg_constraint WHERE conrelid IN (SELECT ('core.'||table_name)::regclass FROM expected_columns)
              AND (NOT convalidated OR condeferrable)) THEN
  RAISE EXCEPTION 'Core v2.1 primary/unique/foreign key mismatch: explicit migration required'; END IF;
END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_indexes p JOIN pg_index i ON i.indexrelid=to_regclass('core.'||p.indexname) WHERE p.schemaname='core' AND p.tablename='customer_snapshot' AND p.indexname='idx_customer_snapshot_buyer_id' AND p.indexdef='CREATE INDEX idx_customer_snapshot_buyer_id ON core.customer_snapshot USING btree (buyer_id)' AND i.indisvalid AND i.indisready) THEN RAISE EXCEPTION 'Missing/drifted index idx_customer_snapshot_buyer_id'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_indexes p JOIN pg_index i ON i.indexrelid=to_regclass('core.'||p.indexname) WHERE p.schemaname='core' AND p.tablename='orders' AND p.indexname='idx_orders_customer_id' AND p.indexdef='CREATE INDEX idx_orders_customer_id ON core.orders USING btree (customer_id)' AND i.indisvalid AND i.indisready) THEN RAISE EXCEPTION 'Missing/drifted index idx_orders_customer_id'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_indexes p JOIN pg_index i ON i.indexrelid=to_regclass('core.'||p.indexname) WHERE p.schemaname='core' AND p.tablename='orders' AND p.indexname='idx_orders_status_purchased_at' AND p.indexdef='CREATE INDEX idx_orders_status_purchased_at ON core.orders USING btree (status, purchased_at)' AND i.indisvalid AND i.indisready) THEN RAISE EXCEPTION 'Missing/drifted index idx_orders_status_purchased_at'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_indexes p JOIN pg_index i ON i.indexrelid=to_regclass('core.'||p.indexname) WHERE p.schemaname='core' AND p.tablename='product' AND p.indexname='idx_product_category_id' AND p.indexdef='CREATE INDEX idx_product_category_id ON core.product USING btree (category_id)' AND i.indisvalid AND i.indisready) THEN RAISE EXCEPTION 'Missing/drifted index idx_product_category_id'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_indexes p JOIN pg_index i ON i.indexrelid=to_regclass('core.'||p.indexname) WHERE p.schemaname='core' AND p.tablename='order_item' AND p.indexname='idx_order_item_product_id' AND p.indexdef='CREATE INDEX idx_order_item_product_id ON core.order_item USING btree (product_id)' AND i.indisvalid AND i.indisready) THEN RAISE EXCEPTION 'Missing/drifted index idx_order_item_product_id'; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_indexes p JOIN pg_index i ON i.indexrelid=to_regclass('core.'||p.indexname) WHERE p.schemaname='core' AND p.tablename='order_item' AND p.indexname='idx_order_item_seller_id' AND p.indexdef='CREATE INDEX idx_order_item_seller_id ON core.order_item USING btree (seller_id)' AND i.indisvalid AND i.indisready) THEN RAISE EXCEPTION 'Missing/drifted index idx_order_item_seller_id'; END IF; END $$;

\if :upgraded
\else
DO $$
DECLARE bad record;
BEGIN
 SELECT customer_id AS id,state INTO bad FROM core.customer_snapshot WHERE length(state)>2 LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'State too long: core.customer_snapshot key %, state %',bad.id,bad.state; END IF;
 SELECT seller_id AS id,state INTO bad FROM core.seller WHERE length(state)>2 LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'State too long: core.seller key %, state %',bad.id,bad.state; END IF;
 SELECT customer_id AS id,customer_state AS state INTO bad FROM raw.customers WHERE length(customer_state)>2 LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'State too long: raw.customers key %, state %',bad.id,bad.state; END IF;
 SELECT seller_id AS id,seller_state AS state INTO bad FROM raw.sellers WHERE length(seller_state)>2 LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'State too long: raw.sellers key %, state %',bad.id,bad.state; END IF;
END $$;
-- RESTRICT protects any unknown consumers; all known views return in this transaction.
DROP VIEW IF EXISTS mart.buyer_order_counts RESTRICT;
DROP VIEW IF EXISTS mart.order_item_enriched RESTRICT;
DROP VIEW IF EXISTS mart.order_totals RESTRICT;
ALTER TABLE core.customer_snapshot ALTER COLUMN state TYPE varchar(2);
ALTER TABLE core.seller ALTER COLUMN state TYPE varchar(2);
ALTER TABLE core.product ADD COLUMN name_length integer, ADD COLUMN description_length integer;
ALTER TABLE core.order_review RENAME COLUMN answered_at TO submitted_at;
INSERT INTO analytics_meta.migrations(version) VALUES ('002_core_v3.1');
UPDATE expected_columns SET type_name='character varying(2)' WHERE column_name='state';
UPDATE expected_columns SET column_name='submitted_at' WHERE table_name='order_review' AND column_name='answered_at';
INSERT INTO expected_columns VALUES ('product','name_length','integer',false),('product','description_length','integer',false);
\endif
DO $$ BEGIN
 IF EXISTS (
  (SELECT * FROM expected_columns EXCEPT
   SELECT c.relname::text,a.attname::text,format_type(a.atttypid,a.atttypmod),a.attnotnull
   FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='core' AND c.relname IN (SELECT table_name FROM expected_columns) AND a.attnum>0 AND NOT a.attisdropped)
  UNION ALL
  (SELECT c.relname::text,a.attname::text,format_type(a.atttypid,a.atttypmod),a.attnotnull
   FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='core' AND c.relname IN (SELECT table_name FROM expected_columns) AND a.attnum>0 AND NOT a.attisdropped
   EXCEPT SELECT * FROM expected_columns)
 ) THEN RAISE EXCEPTION 'Core v3.1 column/type/nullability mismatch: explicit migration required'; END IF;
 IF EXISTS (SELECT FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='core' AND c.relname IN (SELECT table_name FROM expected_columns)
    AND (c.relkind <> 'r' OR c.relrowsecurity))
 OR EXISTS (SELECT FROM pg_trigger WHERE tgrelid IN (SELECT ('core.'||table_name)::regclass FROM expected_columns) AND NOT tgisinternal)
 OR EXISTS (SELECT FROM pg_attrdef WHERE adrelid IN (SELECT ('core.'||table_name)::regclass FROM expected_columns)) THEN
  RAISE EXCEPTION 'Unexpected core table kind, row security, trigger or default'; END IF;
 IF (SELECT array_agg(enumlabel::text ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid='core.order_status'::regtype) IS DISTINCT FROM ARRAY['approved','canceled','created','delivered','invoiced','processing','shipped','unavailable']::text[] THEN RAISE EXCEPTION 'Enum core.order_status mismatch: explicit migration required'; END IF;
 IF (SELECT array_agg(enumlabel::text ORDER BY enumsortorder) FROM pg_enum WHERE enumtypid='core.payment_type'::regtype) IS DISTINCT FROM ARRAY['boleto','credit_card','debit_card','not_defined','voucher']::text[] THEN RAISE EXCEPTION 'Enum core.payment_type mismatch: explicit migration required'; END IF;
END $$;
