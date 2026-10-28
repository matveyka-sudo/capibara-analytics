-- Console output uses the five calculated answers, not acceptance constants.
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
FROM answer_5;
