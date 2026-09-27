-- Агрегация товарных позиций на уровне заказа

drop TABLE IF EXISTS order_items_agg;
CREATE TABLE order_items_agg AS
SELECT
    order_id,
    COUNT(*)                     AS n_items,
    COUNT(DISTINCT product_id)   AS n_distinct_products,
    COUNT(DISTINCT seller_id)    AS n_distinct_sellers,
    SUM(price)                   AS total_price,
    SUM(freight_value)           AS total_freight_value,
    AVG(price)                   AS avg_item_price
FROM olist_order_items_dataset
GROUP BY order_id;

-- Агрегация оплаты на уровне заказа

DROP TABLE IF EXISTS order_payments_agg;
CREATE TABLE order_payments_agg AS
SELECT
    order_id,
    COUNT(DISTINCT payment_type) AS n_payment_types,
    MAX(payment_installments)    AS max_installments,
    SUM(payment_value)           AS total_payment_value
FROM olist_order_payments_dataset
GROUP BY order_id;

-- "Главный" товар заказа (первая позиция)

DROP TABLE IF EXISTS order_main_item;
CREATE TABLE order_main_item AS
SELECT oi.order_id, oi.product_id, oi.seller_id
FROM olist_order_items_dataset oi
JOIN (
    SELECT order_id, MIN(order_item_id) AS min_item_id
    FROM olist_order_items_dataset
    GROUP BY order_id
) m ON m.order_id = oi.order_id AND m.min_item_id = oi.order_item_id;

-- Товары и перевод категории на английский

DROP TABLE IF EXISTS products_translated;
CREATE TABLE products_translated AS
SELECT
    p.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name) AS product_category,
    p.product_weight_g,
    p.product_photos_qty
FROM olist_products_dataset p
LEFT JOIN product_category_name_translation t
       ON p.product_category_name = t.product_category_name;

-- Отзывы на уровне заказа 

DROP TABLE IF EXISTS order_review_agg;
CREATE TABLE order_review_agg AS
SELECT
    order_id,
    AVG(review_score) AS review_score
FROM olist_order_reviews_dataset
GROUP BY order_id;

-- Финальная таблица признаков

DROP TABLE IF EXISTS model_features;
CREATE TABLE model_features AS
SELECT
    o.order_id,
    o.customer_id,

    -- временные признаки
    JULIANDAY(o.order_approved_at)             - JULIANDAY(o.order_purchase_timestamp)      AS approval_time_days,
    JULIANDAY(o.order_delivered_carrier_date)  - JULIANDAY(o.order_purchase_timestamp)      AS shipping_prep_days,
    JULIANDAY(o.order_delivered_customer_date) - JULIANDAY(o.order_delivered_carrier_date)  AS carrier_to_customer_days,
    JULIANDAY(o.order_delivered_customer_date) - JULIANDAY(o.order_purchase_timestamp)      AS total_delivery_days,
    JULIANDAY(o.order_delivered_customer_date) - JULIANDAY(o.order_estimated_delivery_date) AS delivery_delay_days,

    -- признаки заказа/товаров
    oia.n_items,
    oia.n_distinct_products,
    oia.n_distinct_sellers,
    oia.total_price,
    oia.total_freight_value,
    oia.avg_item_price,

    -- оплата
    opa.n_payment_types,
    opa.max_installments,
    opa.total_payment_value,

    -- товар (по первой позиции заказа)
    pt.product_category,
    pt.product_weight_g,
    pt.product_photos_qty,

    -- география 
    c.customer_state,
    s.seller_state,
    CASE WHEN c.customer_state = s.seller_state THEN 1 ELSE 0 END AS same_state,

    -- целевая переменная
    r.review_score

FROM olist_orders_dataset o
JOIN      order_items_agg     oia ON oia.order_id   = o.order_id
LEFT JOIN order_payments_agg  opa ON opa.order_id   = o.order_id
LEFT JOIN order_main_item     omi ON omi.order_id   = o.order_id
LEFT JOIN products_translated pt  ON pt.product_id  = omi.product_id
LEFT JOIN olist_customers_dataset c ON c.customer_id = o.customer_id
LEFT JOIN olist_sellers_dataset   s ON s.seller_id   = omi.seller_id
LEFT JOIN order_review_agg        r ON r.order_id    = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL;

Select * from model_features;