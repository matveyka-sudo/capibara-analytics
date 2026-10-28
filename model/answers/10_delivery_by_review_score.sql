SELECT scores.score,count(o.order_id) AS order_count,
       round(avg(o.delivery_days),6) AS average_delivery_days,
       round(100.0*count(o.order_id) FILTER(WHERE o.is_late)/nullif(count(o.order_id) FILTER(WHERE o.is_late_eligible),0),6) AS late_rate_percent
FROM generate_series(1,5) AS scores(score)
LEFT JOIN (mart.order_review_selected r JOIN mart.order_totals o ON o.order_id=r.order_id AND o.status='delivered')
 ON r.score=scores.score
GROUP BY scores.score ORDER BY scores.score;
