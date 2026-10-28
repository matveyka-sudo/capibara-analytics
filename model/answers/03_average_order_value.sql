SELECT count(*) AS order_count,coalesce(sum(item_count),0) AS item_row_count,
       coalesce(sum(unit_count),0) AS item_unit_count,coalesce(sum(item_revenue),0.00) AS item_revenue,
       coalesce(sum(freight_value),0.00) AS freight_value,coalesce(sum(order_value),0.00) AS order_value,
       round(avg(order_value),2) AS average_order_value,round(avg(order_value),12) AS average_order_value_12dp,
       round(avg(item_count),12) AS average_item_rows_per_order_12dp,
       round(avg(unit_count),12) AS average_item_units_per_order_12dp
FROM mart.order_totals WHERE status='delivered';
