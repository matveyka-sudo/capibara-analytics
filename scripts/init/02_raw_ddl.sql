-- Raw initialization replaces existing tables; business values stay text.

DROP TABLE IF EXISTS raw.orders;
DROP TABLE IF EXISTS raw.order_items;
DROP TABLE IF EXISTS raw.order_payments;
DROP TABLE IF EXISTS raw.order_reviews;
DROP TABLE IF EXISTS raw.products;
DROP TABLE IF EXISTS raw.sellers;
DROP TABLE IF EXISTS raw.customers;
DROP TABLE IF EXISTS raw.product_category_translation;

CREATE TABLE raw.orders (
    order_id                      text,
    customer_id                   text,
    order_status                  text,
    order_purchase_timestamp      text,
    order_approved_at             text,
    order_delivered_carrier_date  text,
    order_delivered_customer_date text,
    order_estimated_delivery_date text,
    _source_file                  text,
    _loaded_at                    timestamptz DEFAULT now()
);

CREATE TABLE raw.order_items (
    order_id            text,
    order_item_id       text,  -- Position number within an order, not a global identifier.
    product_id          text,
    seller_id           text,
    shipping_limit_date text,
    price               text,
    freight_value       text,
    _source_file        text,
    _loaded_at          timestamptz DEFAULT now()
);

CREATE TABLE raw.order_payments (
    order_id             text,
    payment_sequential   text,
    payment_type         text,
    payment_installments text,
    payment_value        text,
    _source_file         text,
    _loaded_at           timestamptz DEFAULT now()
);

CREATE TABLE raw.order_reviews (
    review_id               text,
    order_id                text,
    review_score            text,
    review_comment_title    text,
    review_comment_message  text,
    review_creation_date    text,
    review_answer_timestamp text,
    _source_file            text,
    _loaded_at              timestamptz DEFAULT now()
);

CREATE TABLE raw.products (
    product_id                 text,
    product_category_name      text,
    product_name_lenght        text,  -- Source spelling is intentional.
    product_description_lenght text,
    product_photos_qty         text,
    product_weight_g           text,
    product_length_cm          text,
    product_height_cm          text,
    product_width_cm           text,
    _source_file               text,
    _loaded_at                 timestamptz DEFAULT now()
);

CREATE TABLE raw.sellers (
    seller_id              text,
    seller_zip_code_prefix text,
    seller_city            text,
    seller_state           text,
    _source_file           text,
    _loaded_at             timestamptz DEFAULT now()
);

CREATE TABLE raw.customers (
    customer_id              text,
    customer_unique_id       text,
    customer_zip_code_prefix text,
    customer_city            text,
    customer_state           text,
    _source_file             text,
    _loaded_at               timestamptz DEFAULT now()
);

CREATE TABLE raw.product_category_translation (
    product_category_name         text,
    product_category_name_english text,
    _source_file                  text,
    _loaded_at                    timestamptz DEFAULT now()
);
