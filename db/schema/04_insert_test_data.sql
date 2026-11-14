-- Генератор тестовых данных (FOOD-102).
-- value строк: клиенты, курьеры, категории, рестораны.
-- value * 5 строк: адреса, блюда, заказы, отзывы, оплаты (BR-11.7).
-- Текстовые поля — случайная кириллица; уникальные — с высокой энтропией.

-- Случайная строка из кириллицы длиной 1..max_length
CREATE OR REPLACE FUNCTION sintsev_food.random_cyrillic_text(max_length int)
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
    SELECT string_agg(
               substr('абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                      1 + floor(random() * 33)::int,
                      1),
               ''
           )
    FROM generate_series(1, 1 + floor(random() * max_length)::int);
$$;

-- Случайная уникальная строка из кириллицы (очень маленькая вероятность коллизии - считаю приемлимой для генерации тестовых данных)
CREATE OR REPLACE FUNCTION sintsev_food.random_unique_cyrillic_text(max_length int)
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
    WITH hash AS (
        SELECT md5(random()::text) AS value
    )
    SELECT left(
        translate(substr(hash.value, 1, 16),
                  '0123456789abcdef', 'абвгдежзиклмнопр')
        || translate(substr(hash.value, 17, 16),
                     '0123456789abcdef', 'стуфхцчшщэюяйкло'),
        least(max_length, 32)
    )
    FROM hash;
$$;

-- Формат телефона: +7 и 10 цифр.
-- number должен быть уникальным; функция только форматирует его.
CREATE OR REPLACE FUNCTION sintsev_food.format_phone_number(number bigint)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    -- остаток от деления текущего числа на 10^10 + заполнение слева нулями до 10 цифр
    SELECT '+7' || lpad((number % 10000000000)::text, 10, '0');
$$;

CREATE OR REPLACE PROCEDURE sintsev_food.insert_test_data(value int DEFAULT 10)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Границы шестимесячного окна
    current_month_start  date := date_trunc('month', current_date)::date;
    history_period_start date := (date_trunc('month', current_date) - interval '5 months')::date;

    -- массивы идентификаторов только что вставленных строк для использования в качестве FK
    category_identifiers            uuid[];
    courier_identifiers             uuid[];
    restaurant_address_identifiers  uuid[];
    client_address_identifiers      uuid[];
    restaurant_identifiers          uuid[];
    client_identifiers              uuid[];
    order_identifiers               uuid[];

    -- Текущий размер таблицы: продолжает нумерацию телефонов.
    existing_row_count int;
BEGIN
    -- 1. Категории блюд - рандомная уникальная кириллица
    WITH inserted_categories AS (
        INSERT INTO sintsev_food.product_category (product_category_name)
        SELECT sintsev_food.random_unique_cyrillic_text(50)
        FROM generate_series(1, value)
        RETURNING product_category_id
    )
    SELECT array_agg(product_category_id) INTO category_identifiers FROM inserted_categories;

    -- 2. Курьеры.
    -- fio — случайная кириллица
    -- phone_number — +7 + порядковый номер в таблице для выполнения уникальности
    -- status — случайный элемент enum courier_status.
    -- hire_date на день раньше history_period_start
    SELECT count(*) INTO existing_row_count FROM sintsev_food.courier;

    WITH new_couriers AS (
        SELECT sintsev_food.random_cyrillic_text(150) AS fio,
               sintsev_food.format_phone_number(existing_row_count + sequence_number) AS phone_number,
               (enum_range(NULL::sintsev_food.courier_status))
                   [1 + floor(random() * 4)::int] AS status
        FROM generate_series(1, value) AS generated_numbers(sequence_number)
    ),
    inserted_couriers AS (
        INSERT INTO sintsev_food.courier (fio, phone_number, status, hire_date, dismissal_date)
        SELECT fio, phone_number, status, history_period_start - 1,
               CASE WHEN status = 'уволен' THEN current_date END
        FROM new_couriers
        RETURNING courier_id
    )
    SELECT array_agg(courier_id) INTO courier_identifiers FROM inserted_couriers;

    -- BR-6.6: хотя бы один курьер в этой генерации должен быть не уволен
    IF NOT EXISTS (SELECT 1 FROM sintsev_food.courier
                   WHERE courier_id = ANY (courier_identifiers) AND status <> 'уволен') THEN
        UPDATE sintsev_food.courier
        SET status = 'свободен', dismissal_date = NULL
        WHERE courier_id = courier_identifiers[1];
    END IF;

    -- 3. Клиенты.
    -- login — случайная уникальная кириллица
    -- phone_number — +7 + порядковый номер в таблице для выполнения уникальности
    -- password — md5, ровно 32 hex-символа, как требует char(32).
    SELECT count(*) INTO existing_row_count FROM sintsev_food.client;

    WITH inserted_clients AS (
        INSERT INTO sintsev_food.client (login, password, phone_number)
        SELECT sintsev_food.random_unique_cyrillic_text(50),
               md5(random()::text),
               sintsev_food.format_phone_number(existing_row_count + sequence_number)
        FROM generate_series(1, value) AS generated_numbers(sequence_number)
        RETURNING client_id
    )
    SELECT array_agg(client_id) INTO client_identifiers FROM inserted_clients;

    -- 4. Адреса 
    -- value — под рестораны, value * 4 — под клиентов (BR-11.7).
    -- Улица — случайная уникальная кириллица
    -- Дом — случайное число 1–200
    -- Квартира/офис — случайное число 1–100 с вероятностью 60%.
    WITH inserted_restaurant_addresses AS (
        INSERT INTO sintsev_food.address (street, house_number, apartment_office)
        SELECT sintsev_food.random_unique_cyrillic_text(100),
               (1 + floor(random() * 200))::int::text,
               CASE WHEN random() < 0.6
                    THEN (1 + floor(random() * 100))::int::text END
        FROM generate_series(1, value) AS generated_numbers(sequence_number)
        RETURNING address_id
    )
    SELECT array_agg(address_id) INTO restaurant_address_identifiers FROM inserted_restaurant_addresses;

    WITH inserted_client_addresses AS (
        INSERT INTO sintsev_food.address (street, house_number, apartment_office)
        SELECT sintsev_food.random_unique_cyrillic_text(100),
               (1 + floor(random() * 200))::int::text,
               CASE WHEN random() < 0.6
                    THEN (1 + floor(random() * 100))::int::text END
        FROM generate_series(1, value * 4) AS generated_numbers(sequence_number)
        RETURNING address_id
    )
    SELECT array_agg(address_id) INTO client_address_identifiers FROM inserted_client_addresses;

    -- 5. Рестораны: каждому свой адрес (BR-3.3).
    -- Название и текстовые поля — случайная кириллица.
    -- unnest(restaurant_address_identifiers) даёт по одной строке на адрес.
    -- work_start 08:00–12:59, work_end 18:00–23:59
    WITH inserted_restaurants AS (
        INSERT INTO sintsev_food.restaurant
            (restaurant_name, address_id, description,
             work_start, work_end, company_details, status)
        SELECT sintsev_food.random_cyrillic_text(100),
               address_row.address_id,
               sintsev_food.random_cyrillic_text(330),
               time '08:00' + floor(random() * 300)::int * interval '1 minute',
               time '18:00' + floor(random() * 360)::int * interval '1 minute',
               sintsev_food.random_cyrillic_text(330),
               (enum_range(NULL::sintsev_food.restaurant_status))
                   [1 + floor(random() * 2)::int]
        FROM unnest(restaurant_address_identifiers) AS address_row(address_id)
        RETURNING restaurant_id
    )
    SELECT array_agg(restaurant_id) INTO restaurant_identifiers FROM inserted_restaurants;

    -- 6. Адреса клиентов (M:N, BR-2.4): каждому клиенту по 4 адреса.
    -- client_number — номер клиента (1..value), address_offset — 1..4.
    -- Адрес для пары: (client_number - 1) * 4 + address_offset.
    INSERT INTO sintsev_food.client_address (client_id, address_id)
    SELECT client_identifiers[client_number],
           client_address_identifiers[(client_number - 1) * 4 + address_offset] -- вычисляем индекс адреса для этого клиента
    FROM generate_series(1, value) AS clients(client_number)
    -- по 4 адреса на клиента
    CROSS JOIN generate_series(1, 4) AS offsets(address_offset)

    UNION ALL

    -- Примерно 10% адресов получают второго владельца.
    -- ON CONFLICT DO NOTHING пропускает случай, когда выпал тот же клиент.
    SELECT client_identifiers[1 + floor(random() * value)::int],
           client_address_row.address_id
    FROM unnest(client_address_identifiers) AS client_address_row(address_id)
    WHERE random() < 0.1
    ON CONFLICT DO NOTHING;

    -- 7. Блюда: по 5 на ресторан
    -- unnest(restaurant_identifiers) × generate_series(1,5) = 5 строк
    -- на ресторан. Название — случайная уникальная кириллица.
    -- category_identifiers[...] — случайная категория из этого вызова.
    -- price — случайное число 250–2000 с двумя знаками после запятой
    -- photo_url — с вероятностью 70% случайная ссылка на фото, иначе NULL
    INSERT INTO sintsev_food.product
        (product_name, product_category_id, price,
         restaurant_id, photo_url, status, description)
    SELECT sintsev_food.random_unique_cyrillic_text(100),
           category_identifiers[1 + floor(random() * value)::int],
           round((250 + random() * 1750)::numeric, 2),
           restaurant_row.restaurant_id,
           CASE WHEN random() < 0.7
                THEN 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' END,
           (enum_range(NULL::sintsev_food.product_status))
               [1 + floor(random() * 3)::int],
           sintsev_food.random_cyrillic_text(330)
    FROM unnest(restaurant_identifiers) AS restaurant_row(restaurant_id)
    CROSS JOIN generate_series(1, 5);

    -- 8. Заказы (value * 5).
    -- Первый заказ всегда доставлен, остальные — с вероятностью 70%.
    -- order_time — случайный момент от history_period_start до «сейчас - 2 часа».

    -- Один случайный адрес на клиента: DISTINCT ON + ORDER BY random()
    -- оставляет по одной строке на client_id.
    WITH random_client_address AS (
        SELECT DISTINCT ON (client_id)
               client_id,
               address_id
        FROM sintsev_food.client_address
        WHERE client_id = ANY (client_identifiers)
        ORDER BY client_id, random()
    ),
    new_orders AS (
        SELECT sequence_number,
               client_identifiers[1 + floor(random() * value)::int]     AS client_id,
               restaurant_identifiers[1 + floor(random() * value)::int] AS restaurant_id,
               courier_identifiers[1 + floor(random() * value)::int]    AS courier_id,
               CASE WHEN sequence_number = 1 OR random() < 0.7
                    THEN 'доставлен'::sintsev_food.order_status
                    ELSE (enum_range(NULL::sintsev_food.order_status))
                         [1 + floor(random() * 5)::int]
               END AS status,
               history_period_start::timestamp
                   + random() * (localtimestamp - interval '2 hours'
                                 - history_period_start::timestamp) AS order_time
        FROM generate_series(1, value * 5) AS generated_numbers(sequence_number)
    ),
    inserted_orders AS (
        INSERT INTO sintsev_food."order"
            (courier_id, client_id, address_id, restaurant_id,
             order_timestamp, delivery_timestamp, status, description)
        SELECT new_order.courier_id, new_order.client_id,
               random_client_address.address_id,
               new_order.restaurant_id, new_order.order_time,
               -- время доставки только для доставленных, иначе NULL (BR-7.12)
               CASE WHEN new_order.status = 'доставлен'
                    THEN new_order.order_time
                         + (20 + floor(random() * 70)::int) * interval '1 minute' END,
               new_order.status,
               sintsev_food.random_cyrillic_text(99)
        FROM new_orders AS new_order
        JOIN random_client_address
          ON random_client_address.client_id = new_order.client_id
        RETURNING order_id
    )
    SELECT array_agg(order_id) INTO order_identifiers FROM inserted_orders;

    -- 9. Позиции: 2–5 разных блюд из ресторана заказа
    -- Цена блюда >= 250, количество >= 2, записей >= 2
    -- 2 * 250 * 2 = 1000, поэтому сумма заказа всегда >= 1000 (BR-1.8).
    INSERT INTO sintsev_food.order_structure (order_id, product_id, quantity)
    SELECT order_row.order_id, product_row.product_id,
           2 + floor(random() * 3)::int
    FROM unnest(order_identifiers) AS order_identifier_row(order_id)
    JOIN sintsev_food."order" AS order_row
      ON order_row.order_id = order_identifier_row.order_id
    CROSS JOIN LATERAL (
        SELECT product_id
        FROM sintsev_food.product
        WHERE restaurant_id = order_row.restaurant_id
        ORDER BY random()
        -- первые 2-5
        LIMIT 2 + floor(random() * 4)::int
    ) AS product_row;

    -- 10. Оплаты (всего value * 5, BR-11.7).
    -- Каждый заказ получает одну попытку.
    -- amount = order_row.total_amount — генерируемое поле заказа (BR-8.4).
    -- transaction_id — UUID, уникален (BR-8.3).
    -- «создан» → в_обработке (pay_status останется «ожидает»),
    -- остальные → успех (триггер поставит pay_status = «оплачен»).
    INSERT INTO sintsev_food.payment
        (order_id, payment_type, amount, transaction_id, payment_timestamp, status)
    SELECT order_row.order_id,
           (enum_range(NULL::sintsev_food.payment_type))
               [1 + floor(random() * 3)::int],
           order_row.total_amount,
           exts.uuid_generate_v4()::text,
           order_row.order_timestamp
               + (5 + floor(random() * 10)::int) * interval '1 minute',
           CASE WHEN order_row.status = 'создан'
                THEN 'в_обработке'::sintsev_food.payment_status
                ELSE 'успех'::sintsev_food.payment_status
           END
    FROM sintsev_food."order" AS order_row
    WHERE order_row.order_id = ANY (order_identifiers);

    -- 11. Отзывы (value * 5): по одному на заказ.
    -- review_order  — заказ и одно блюдо из его состава.
    -- review_target — добавляет номер типа объекта (1=блюдо, 2=ресторан, 3=заказ).
    -- review_data   — собирает все поля отзыва с понятными именами.
    WITH review_order AS (
        SELECT order_row.order_id,
               order_row.client_id,
               order_row.restaurant_id,
               order_row.order_timestamp,
               order_row.delivery_timestamp,
               product_row.product_id
        FROM sintsev_food."order" AS order_row
        CROSS JOIN LATERAL (
            SELECT product_id
            FROM sintsev_food.order_structure
            WHERE order_id = order_row.order_id
            ORDER BY product_id
            LIMIT 1
        ) AS product_row
        WHERE order_row.order_id = ANY (order_identifiers)
    ),
    review_target AS (
        SELECT review_order.*,
               (1 + (row_number() OVER ()) % 3)::int AS entity_type_number
        FROM review_order
    ),
    review_data AS (
        SELECT review_target.client_id,
               review_target.order_id,
               coalesce(review_target.delivery_timestamp,
                        review_target.order_timestamp)
                   + random() * (localtimestamp
                                 - coalesce(review_target.delivery_timestamp,
                                            review_target.order_timestamp))
                   AS review_timestamp,
               (enum_range(NULL::sintsev_food.review_entity_type))
                   [review_target.entity_type_number] AS entity_type,
               CASE review_target.entity_type_number
                   WHEN 1 THEN review_target.product_id
                   WHEN 2 THEN review_target.restaurant_id
                   ELSE review_target.order_id
               END AS entity_id,
               sintsev_food.random_cyrillic_text(165) AS description,
               CASE WHEN random() < 0.3
                    THEN 'https://cdn.foodexpress.ru/img/'
                         || md5(random()::text) || '.jpg' END AS photo_url,
               1 + floor(random() * 5)::int AS rating
        FROM review_target
    )
    INSERT INTO sintsev_food.review
        (client_id, order_id, review_timestamp,
         entity_type, entity_id, description, photo_url, rating)
    SELECT client_id, order_id, review_timestamp,
           entity_type, entity_id, description, photo_url, rating
    FROM review_data;

    -- 12. Рейтинги блюд и ресторанов — среднее по отзывам (BR-9.6, BR-9.7).
    -- Подзапрос product_ratings считает среднее по каждому entity_id,
    -- UPDATE ... FROM переносит его в product.
    -- ANY(restaurant_identifiers) ограничивает обновление только этим вызовом.
    -- Если отзывов на объект нет, его нет в подзапросе, и rating остаётся NULL.
    UPDATE sintsev_food.product AS product_row
    SET rating = product_ratings.average_rating
    FROM (
        SELECT entity_id, round(avg(rating), 2) AS average_rating
        FROM sintsev_food.review
        WHERE entity_type = 'блюдо'
        GROUP BY entity_id
    ) AS product_ratings
    WHERE product_row.product_id = product_ratings.entity_id
      AND product_row.restaurant_id = ANY (restaurant_identifiers);

    UPDATE sintsev_food.restaurant AS restaurant_row
    SET rating = restaurant_ratings.average_rating
    FROM (
        SELECT entity_id, round(avg(rating), 2) AS average_rating
        FROM sintsev_food.review
        WHERE entity_type = 'ресторан'
        GROUP BY entity_id
    ) AS restaurant_ratings
    WHERE restaurant_row.restaurant_id = restaurant_ratings.entity_id
      AND restaurant_row.restaurant_id = ANY (restaurant_identifiers);

    -- 13. Выплаты курьерам за последние 6 месяцев (BR-10.2, BR-10.7).
    -- monthly_statistics — каждый курьер × каждый месяц.
    -- Условия месяца и статуса стоят в ON, а не в WHERE: так месяцы
    -- без доставок остаются в результате (LEFT JOIN).
    -- count(order_row.order_id) для пустого месяца даёт 0, а не 1.
    -- coalesce(sum(...), 0) превращает NULL от пустой суммы в 0.
    WITH months AS (
        SELECT generate_series(history_period_start,
                               current_month_start,
                               interval '1 month')::date AS month_start_date
    ),
    monthly_statistics AS (
        SELECT courier_row.courier_id, month_row.month_start_date,
               count(order_row.order_id) AS delivered_order_count,
               coalesce(sum(order_row.commission), 0) AS commission_total
        FROM unnest(courier_identifiers) AS courier_row(courier_id)
        CROSS JOIN months AS month_row
        LEFT JOIN sintsev_food."order" AS order_row
               ON order_row.courier_id = courier_row.courier_id
              AND order_row.status = 'доставлен'
              AND order_row.order_timestamp >= month_row.month_start_date
              AND order_row.order_timestamp < month_row.month_start_date + interval '1 month'
        GROUP BY courier_row.courier_id, month_row.month_start_date
    ),
    -- lag(delivered_order_count) — доставки предыдущего месяца для этого
    -- курьера. Для первого месяца предыдущего значения нет → коэффициент 0.1.
    -- BR-10.2: 0–150 → 0.1, 151–250 → 0.2, 251–500 → 0.3, больше 500 → 0.5.
    monthly_coefficients AS (
        SELECT courier_id, month_start_date, commission_total,
               CASE WHEN previous_month_delivered_count IS NULL THEN 0.1
                    WHEN previous_month_delivered_count <= 150 THEN 0.1
                    WHEN previous_month_delivered_count <= 250 THEN 0.2
                    WHEN previous_month_delivered_count <= 500 THEN 0.3
                    ELSE 0.5
               END AS coefficient_used
        FROM (
            SELECT courier_id, month_start_date, commission_total,
                   lag(delivered_order_count)
                       OVER (PARTITION BY courier_id
                             ORDER BY month_start_date)
                       AS previous_month_delivered_count
            FROM monthly_statistics
        ) AS statistics_with_previous_month
    )
    INSERT INTO sintsev_food.courier_pay
        (courier_id, year, month, amount, coefficient_used)
    SELECT courier_id,
           extract(year FROM month_start_date)::int,
           extract(month FROM month_start_date)::int,
           round(coefficient_used * commission_total, 2),
           coefficient_used
    FROM monthly_coefficients;

    -- Коэффициент на следующий месяц — по доставкам текущего месяца.
    -- current_month_statistics.delivered_order_count — число доставленных
    -- заказов в текущем месяце.
    -- Уволенным новый коэффициент не назначаем: оставляем тот,
    -- который действовал в текущем месяце (BR-10.6).
    -- current_month_payment — запись courier_pay за текущий месяц,
    -- из неё берём coefficient_used.
    UPDATE sintsev_food.courier AS courier_to_update
    SET coefficient = CASE
            WHEN courier_to_update.status = 'уволен'
                THEN current_month_payment.coefficient_used
            WHEN current_month_statistics.delivered_order_count <= 150 THEN 0.1
            WHEN current_month_statistics.delivered_order_count <= 250 THEN 0.2
            WHEN current_month_statistics.delivered_order_count <= 500 THEN 0.3
            ELSE 0.5
        END
    FROM (
        SELECT courier_row.courier_id,
               count(order_row.order_id) AS delivered_order_count
        FROM unnest(courier_identifiers) AS courier_row(courier_id)
        LEFT JOIN sintsev_food."order" AS order_row
               ON order_row.courier_id = courier_row.courier_id
              AND order_row.status = 'доставлен'
              AND order_row.order_timestamp >= current_month_start
        GROUP BY courier_row.courier_id
    ) AS current_month_statistics
    JOIN sintsev_food.courier_pay AS current_month_payment
      ON current_month_payment.courier_id = current_month_statistics.courier_id
     AND current_month_payment.year = extract(year FROM current_month_start)::int
     AND current_month_payment.month = extract(month FROM current_month_start)::int
    WHERE courier_to_update.courier_id = current_month_statistics.courier_id;
END;
$$;
