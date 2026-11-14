-- Зарплата курьеров (FOOD-107, BR-10.2–BR-10.6).
-- Считает доставленные заказы за текущий месяц, пишет выплату в courier_pay
-- и обновляет коэффициент курьера на следующий месяц.
-- Уволенным выплату пишет, но коэффициент не меняет.
CREATE OR REPLACE PROCEDURE sintsev_food.courier_salary()
LANGUAGE plpgsql
AS $$
DECLARE
    month_start date := date_trunc('month', current_date)::date;
BEGIN
    WITH
    -- Считаем по каждому курьеру: сколько доставленных заказов
    -- и сколько комиссий он принёс за текущий месяц.
    monthly_orders AS (
        SELECT courier_id,
               count(*) AS delivered_count,
               coalesce(sum(commission), 0) AS commission_total
        FROM sintsev_food."order"
        WHERE status = 'доставлен'
          AND order_timestamp >= month_start
          AND order_timestamp < month_start + interval '1 month'
        GROUP BY courier_id
    ),
    -- Для каждого курьера берём коэффициент, который действует в этом месяце.
    -- Уволенных в прошлых месяцах не считаем: свою выплату они уже получили.
    -- Работающие и уволенные в текущем месяце — считаются.
    -- Если выплата за этот месяц уже есть (например, после insert_test_data
    -- или повторного вызова), берём coefficient_used из неё.
    -- Иначе — текущий коэффициент курьера.
    salary_data AS (
        SELECT courier.courier_id,
               courier.status,
               coalesce(existing_payment.coefficient_used, courier.coefficient)
                   AS coefficient_used,
               coalesce(monthly_orders.delivered_count, 0) AS delivered_count,
               coalesce(monthly_orders.commission_total, 0) AS commission_total
        FROM sintsev_food.courier AS courier
        LEFT JOIN monthly_orders
               ON monthly_orders.courier_id = courier.courier_id
        LEFT JOIN sintsev_food.courier_pay AS existing_payment
               ON existing_payment.courier_id = courier.courier_id
              AND existing_payment.year = extract(year FROM month_start)::int
              AND existing_payment.month = extract(month FROM month_start)::int
        WHERE courier.status <> 'уволен'
           OR courier.dismissal_date >= month_start
    ),
    -- Пишем или обновляем выплату за текущий месяц.
    -- Повторный вызов не создаёт дубликат: PK (courier_id, year, month).
    upsert_payment AS (
        INSERT INTO sintsev_food.courier_pay
            (courier_id, year, month, amount, coefficient_used)
        SELECT courier_id,
               extract(year FROM month_start)::int,
               extract(month FROM month_start)::int,
               round(coefficient_used * commission_total, 2),
               coefficient_used
        FROM salary_data
        ON CONFLICT (courier_id, year, month)
        DO UPDATE SET amount = excluded.amount,
                      coefficient_used = excluded.coefficient_used
        RETURNING courier_id
    )
    -- Обновляем коэффициент на следующий месяц.
    -- Уволенных не трогаем: они получают выплату, но новый коэффициент
    -- им уже не назначается.
    UPDATE sintsev_food.courier AS courier
    SET coefficient = CASE
            WHEN salary_data.delivered_count <= 150 THEN 0.1
            WHEN salary_data.delivered_count <= 250 THEN 0.2
            WHEN salary_data.delivered_count <= 500 THEN 0.3
            ELSE 0.5
        END
    FROM salary_data
    WHERE courier.courier_id = salary_data.courier_id
      AND courier.status <> 'уволен';
END;
$$;
