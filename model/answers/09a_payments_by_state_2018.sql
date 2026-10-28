SELECT c.state,count(*) AS payment_count,sum(p.payment_value)::numeric(18,2) AS payment_value,
       round(avg(p.installment_count),6) AS average_installment_count
FROM core.order_payment p JOIN core.orders o USING(order_id)
JOIN core.customer_snapshot c USING(customer_id)
WHERE o.purchased_at>=timestamp '2018-01-01' AND o.purchased_at<timestamp '2019-01-01'
GROUP BY c.state ORDER BY c.state ASC NULLS LAST;
