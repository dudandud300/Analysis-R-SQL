CREATE TABLE olist_customers_dataset (
    customer_id               VARCHAR NOT NULL,
    customer_unique_id        VARCHAR NOT NULL,
    customer_zip_code_prefix  INTEGER,
    customer_city             VARCHAR,
    customer_state            VARCHAR,

    PRIMARY KEY (customer_id)

);

CREATE TABLE olist_sellers_dataset (
    seller_id               VARCHAR NOT NULL,
    seller_zip_code_prefix  INTEGER,
    seller_city             VARCHAR,
    seller_state            VARCHAR,

    PRIMARY KEY (seller_id)
);

CREATE TABLE product_category_name_translation (
    product_category_name          VARCHAR NOT NULL,
    product_category_name_english  VARCHAR,

    PRIMARY KEY (product_category_name)
);

CREATE TABLE olist_products_dataset (
    product_id                  VARCHAR NOT NULL,
    product_category_name       VARCHAR,
    product_name_lenght         INTEGER,
    product_description_lenght  INTEGER,
    product_photos_qty          INTEGER,
    product_weight_g            INTEGER,
    product_length_cm           INTEGER,
    product_height_cm           INTEGER,
    product_width_cm            INTEGER,

    PRIMARY KEY (product_id)

);

CREATE TABLE olist_orders_dataset (
    order_id                       VARCHAR NOT NULL,
    customer_id                    VARCHAR NOT NULL,
    order_status                   VARCHAR,
    order_purchase_timestamp       TIMESTAMP,
    order_approved_at              TIMESTAMP,
    order_delivered_carrier_date   TIMESTAMP,
    order_delivered_customer_date  TIMESTAMP,
    order_estimated_delivery_date  TIMESTAMP,

    PRIMARY KEY (order_id),
    FOREIGN KEY (customer_id) REFERENCES olist_customers_dataset(customer_id)
);

CREATE TABLE olist_order_items_dataset (
    order_id             VARCHAR NOT NULL,
    order_item_id        INTEGER NOT NULL,
    product_id           VARCHAR NOT NULL,
    seller_id            VARCHAR NOT NULL,
    shipping_limit_date  TIMESTAMP,
    price                DECIMAL(12,2),
    freight_value        DECIMAL(12,2),

    PRIMARY KEY (order_id, order_item_id),
    FOREIGN KEY (order_id)   REFERENCES olist_orders_dataset(order_id),
    FOREIGN KEY (product_id) REFERENCES olist_products_dataset(product_id),
    FOREIGN KEY (seller_id)  REFERENCES olist_sellers_dataset(seller_id)
);

CREATE TABLE olist_order_payments_dataset (
    order_id               VARCHAR NOT NULL,
    payment_sequential     INTEGER NOT NULL,
    payment_type           VARCHAR,
    payment_installments   INTEGER,
    payment_value          DECIMAL(12,2),

    PRIMARY KEY (order_id, payment_sequential),
    FOREIGN KEY (order_id) REFERENCES olist_orders_dataset(order_id)
);

CREATE TABLE olist_order_reviews_dataset (
    review_id               VARCHAR NOT NULL,
    order_id                VARCHAR NOT NULL,
    review_score            INTEGER,
    review_comment_title    VARCHAR,
    review_comment_message  VARCHAR,
    review_creation_date    TIMESTAMP,
    review_answer_timestamp TIMESTAMP,

    PRIMARY KEY (review_id, order_id),
    FOREIGN KEY (order_id) REFERENCES olist_orders_dataset(order_id)
);

CREATE TABLE olist_geolocation_dataset (
    geolocation_zip_code_prefix  INTEGER,
    geolocation_lat              DOUBLE,
    geolocation_lng              DOUBLE,
    geolocation_city             VARCHAR,
    geolocation_state            VARCHAR
);



COPY olist_customers_dataset FROM '../../data/lab-01/olist_customers_dataset.csv'
(HEADER TRUE, AUTO_DETECT TRUE);

COPY olist_sellers_dataset FROM '../../data/lab-01/olist_sellers_dataset.csv'
(HEADER TRUE, AUTO_DETECT TRUE);

COPY product_category_name_translation FROM '../../data/lab-01/product_category_name_translation.csv'
(HEADER TRUE, AUTO_DETECT TRUE);

COPY olist_products_dataset FROM '../../data/lab-01/olist_products_dataset.csv'
(HEADER TRUE, AUTO_DETECT TRUE);

COPY olist_orders_dataset FROM '../../data/lab-01/olist_orders_dataset.csv'
(HEADER TRUE, AUTO_DETECT TRUE);

COPY olist_order_items_dataset FROM '../../data/lab-01/olist_order_items_dataset.csv'
(HEADER TRUE, AUTO_DETECT TRUE);

COPY olist_order_payments_dataset FROM '../../data/lab-01/olist_order_payments_dataset.csv'
(HEADER TRUE, AUTO_DETECT TRUE);

COPY olist_order_reviews_dataset FROM '../../data/lab-01/olist_order_reviews_dataset.csv'
(HEADER TRUE, AUTO_DETECT TRUE);

COPY olist_geolocation_dataset FROM '../../data/lab-01/olist_geolocation_dataset.csv'
(HEADER TRUE, AUTO_DETECT TRUE);

-- olist_geolocation_dataset нельзя связать внешним ключом по geolocation_zip_code_prefix, 
-- потому что этот префикс не уникален (на один prefix там много строк), а FK может ссылаться только на PK/UNIQUE.
-- product_category_name_translation нельзя связать FK с olist_products_dataset.product_category_name,
-- потому что в products есть категории, которых нет в таблице переводов, и тогда загрузка
-- FK упадет (у меня упало на pc_gamer)
-- в то же время их можно лефтджойнить, поэтому, кажется,
-- на данном этапе представленной реляционной базы должно хватить