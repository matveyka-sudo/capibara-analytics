-- Console output uses the ten calculated answers, not acceptance constants.
SELECT concat('1. Продажи за период: ',coalesce(sum(revenue),0.00),
              '; доставленных заказов: ',coalesce(sum(order_count),0),
              '; месяцев: ',count(*),'.') AS answer
FROM answer_1
UNION ALL
SELECT coalesce((SELECT concat('2. Первый продавец: ',seller_id,' (',seller_city,', ',seller_state,
                              '); выручка: ',revenue,'; заказов: ',order_count,
                              '; единиц: ',item_unit_count,'.')
                 FROM answer_2 ORDER BY revenue DESC,seller_id LIMIT 1),
                '2. Продавцы: нет доставленных товаров.')
UNION ALL
SELECT concat('3. Средний чек с доставкой: ',coalesce(average_order_value::text,'нет данных'),
              '; строк/единиц на заказ: ',coalesce(average_item_rows_per_order_12dp::text,'нет данных'),'.')
FROM answer_3
UNION ALL
SELECT concat('4. Покупателей: ',customer_count,'; повторных: ',repeat_customer_count,
              '; доля: ',coalesce(repeat_customer_share_pct::text,'нет данных'),
              CASE WHEN repeat_customer_share_pct IS NOT NULL THEN '%' ELSE '' END,'.')
FROM answer_4
UNION ALL
SELECT concat('5. Категорий: ',count(*),'; общая выручка: ',coalesce(sum(revenue),0.00),
              '; крупнейшая: ',coalesce((SELECT concat(category_code,' — ',revenue)
                  FROM answer_5 ORDER BY revenue DESC,category_code COLLATE "C" LIMIT 1),
                  'нет данных'),'.')
FROM answer_5
UNION ALL
SELECT coalesce((SELECT concat('6. Товар: ',replace(product_id::text,'-',''),
 '; разных цен: ',count(DISTINCT price),'; единиц: ',count(*),
 '; строк истории: ',(SELECT count(*) FROM answer_6),'.')
 FROM mart.order_item_enriched WHERE status='delivered' GROUP BY product_id
 ORDER BY count(DISTINCT price) DESC,product_id ASC LIMIT 1),'6. Нет доставленных товаров.')
UNION ALL
SELECT concat('7. Штатов с 500+ доставленными заказами: ',count(*),'; заказов: ',coalesce(sum(order_count),0),'.') FROM answer_7
UNION ALL
SELECT concat('8. Статусов: ',count(*),'; заказов: ',coalesce(sum(order_count),0),'; без позиций: ',coalesce(sum(orders_without_items),0),'.') FROM answer_8
UNION ALL
SELECT concat('9. Оплаты: в заказах 2018 года ',coalesce(sum(payment_count),0),'; сумма: ',coalesce(sum(payment_value),0.00),
 '; по типам за весь снимок ',(SELECT sum(payment_count) FROM answer_9b),'; типов: ',(SELECT count(*) FROM answer_9b),'.') FROM answer_9a
UNION ALL
SELECT concat('10. Доставленных заказов с выбранным отзывом: ',coalesce(sum(order_count),0),'; групп оценок: ',count(*),'.') FROM answer_10
UNION ALL
SELECT concat('Рекомендации: ',count(*),' пар для ',count(DISTINCT product_id),
 ' товаров; до 5 на товар, минимум 2 совместных заказа, Jaccard.')
FROM mart.product_recommendation;
