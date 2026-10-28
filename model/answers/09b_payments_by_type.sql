SELECT payment_type,count(p.order_id) AS payment_count,
       round(avg(p.installment_count),6) AS average_installment_count
FROM unnest(enum_range(NULL::core.payment_type)) AS types(payment_type)
LEFT JOIN core.order_payment p USING(payment_type)
GROUP BY payment_type ORDER BY payment_type;
