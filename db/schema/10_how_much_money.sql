-- Отчёт «сколько денег» по месяцам (FOOD-108, BR-11.9).
-- Берём все месяцы от первого доставленного заказа до последнего.
-- Месяцы без доставленных заказов тоже попадают в отчёт с нулями.
CREATE OR REPLACE VIEW sintsev_food.how_much_money AS
WITH RECURSIVE
-- Суммы доставленных заказов с комиссией и без по месяцам.
order_totals AS (
    SELECT date_trunc('month', order_timestamp)::date AS month_start,
           sum(order_amount) AS sum_no_commission,
           sum(total_amount) AS sum_with_commission
    FROM sintsev_food."order"
    WHERE status = 'доставлен'
    GROUP BY date_trunc('month', order_timestamp)::date
),
-- Границы отчёта: первый и последний месяц с доставленными заказами.
bounds AS (
    SELECT min(month_start) AS first_month,
           max(month_start) AS last_month
    FROM order_totals
),
-- Непрерывная серия месяцев от первого до последнего (собираем рекурсивно)
months AS (
    SELECT bounds.first_month AS month_start
    FROM bounds
    WHERE bounds.first_month IS NOT NULL

    UNION ALL

    SELECT (months.month_start + interval '1 month')::date
    FROM months
    CROSS JOIN bounds
    WHERE months.month_start < bounds.last_month
),
-- Выплаты курьерам по месяцам.
pay_totals AS (
    SELECT make_date(year, month, 1) AS month_start,
           sum(amount) AS courier_pay
    FROM sintsev_food.courier_pay
    GROUP BY make_date(year, month, 1)
),
-- Суммы с комиссией, без комиссии, сама комиссия и выплаты курьерам.
monthly_totals AS (
    SELECT months.month_start,
           coalesce(order_totals.sum_no_commission, 0) AS sum_no_commission,
           coalesce(order_totals.sum_with_commission, 0) AS sum_with_commission,
           coalesce(order_totals.sum_with_commission, 0)
               - coalesce(order_totals.sum_no_commission, 0) AS commission,
           coalesce(pay_totals.courier_pay, 0) AS courier_pay
    FROM months
    LEFT JOIN order_totals
           ON order_totals.month_start = months.month_start
    LEFT JOIN pay_totals
           ON pay_totals.month_start = months.month_start
),
-- Комиссии за предыдущий месяц для каждого месяца (кроме первого).
with_previous AS (
    SELECT monthly_totals.*,
           lag(commission) OVER (ORDER BY month_start) AS prev_commission
    FROM monthly_totals
)
SELECT to_char(month_start, 'YYYY-MM') AS year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission - prev_commission AS commission_diff,
       courier_pay,
       commission - courier_pay AS net_profit
FROM with_previous
ORDER BY month_start;
