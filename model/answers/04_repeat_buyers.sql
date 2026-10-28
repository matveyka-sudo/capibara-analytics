SELECT count(*) AS customer_count,count(*) FILTER(WHERE is_repeat) AS repeat_customer_count,
       round(100.0*count(*) FILTER(WHERE is_repeat)/nullif(count(*),0),2) AS repeat_customer_share_pct,
       round(100.0*count(*) FILTER(WHERE is_repeat)/nullif(count(*),0),12) AS repeat_customer_share_pct_12dp
FROM mart.buyer_order_counts;
