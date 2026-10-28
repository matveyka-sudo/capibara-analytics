WITH revenues AS (
 SELECT k.category_id,coalesce(k.category_name_pt,'category:unknown') AS category_code,
        k.category_name_en AS category_name_english,
        coalesce(k.category_name_en,k.category_name_pt,'Unknown') AS category_label,
        coalesce(sum(i.price),0.00) AS revenue
 FROM core.category k LEFT JOIN mart.order_item_enriched i ON i.category_id=k.category_id AND i.status='delivered'
 GROUP BY k.category_id,k.category_name_pt,k.category_name_en
)
SELECT category_code,category_name_english,category_label,revenue,
       round(100.0*revenue/nullif(sum(revenue) OVER(),0),12) AS revenue_share_pct
FROM revenues ORDER BY revenue DESC,category_code COLLATE "C" ASC;
