-- Статистика по ресторанам (FOOD-106).
-- Учитываются только заказы со статусом 'доставлен'.
-- Для каждого ресторана — одна строка.
-- best_product_name и best_user при равенстве выбираются случайно.
CREATE OR REPLACE FUNCTION sintsev_food.get_statistic()
RETURNS TABLE (
    restaurant_name   varchar,
    best_product_name varchar,
    total_amount      numeric,
    avg_amount        numeric,
    best_user         varchar
)
LANGUAGE sql
VOLATILE
AS $$
    WITH
    -- Все доставленные заказы
    delivered_orders AS (
        SELECT order_id,
               restaurant_id,
               client_id,
               total_amount
        FROM sintsev_food."order"
        WHERE status = 'доставлен'
    ),
    -- Сумма и средний чек по доставленным заказам
    restaurant_totals AS (
        SELECT restaurant_id,
               sum(total_amount) AS total_amount,
               round(avg(total_amount), 2) AS avg_amount
        FROM delivered_orders
        GROUP BY restaurant_id
    ),
    -- Сколько каждого блюда продано в каждом ресторане
    product_sales AS (
        SELECT delivered_orders.restaurant_id,
               order_structure.product_id,
               sum(order_structure.quantity) AS sold_quantity
        FROM delivered_orders
        JOIN sintsev_food.order_structure
          ON order_structure.order_id = delivered_orders.order_id
        GROUP BY delivered_orders.restaurant_id, order_structure.product_id
    ),
    -- Самое покупаемое блюдо каждого ресторана.
    best_products AS (
        SELECT DISTINCT ON (product_sales.restaurant_id)
               product_sales.restaurant_id,
               product.product_name
        FROM product_sales
        JOIN sintsev_food.product AS product
          ON product.product_id = product_sales.product_id
        ORDER BY product_sales.restaurant_id,
                 product_sales.sold_quantity DESC
    ),
    -- Доставленных заказы по каждому клиенту и ресторану
    client_orders AS (
        SELECT delivered_orders.restaurant_id,
               delivered_orders.client_id,
               count(*) AS order_count
        FROM delivered_orders
        GROUP BY delivered_orders.restaurant_id, delivered_orders.client_id
    ),
    best_clients AS (
        -- Клиенты с наибольшим количеством доставленных заказов в каждом ресторане.
        SELECT DISTINCT ON (client_orders.restaurant_id)
               client_orders.restaurant_id,
               client.login
        FROM client_orders
        JOIN sintsev_food.client AS client
          ON client.client_id = client_orders.client_id
        ORDER BY client_orders.restaurant_id,
                 client_orders.order_count DESC
    )
    -- Собираем результат
    SELECT restaurant.restaurant_name,
           best_products.product_name AS best_product_name,
           coalesce(restaurant_totals.total_amount, 0) AS total_amount,
           coalesce(restaurant_totals.avg_amount, 0) AS avg_amount,
           best_clients.login AS best_user
    FROM sintsev_food.restaurant AS restaurant
    LEFT JOIN restaurant_totals
           ON restaurant_totals.restaurant_id = restaurant.restaurant_id
    LEFT JOIN best_products
           ON best_products.restaurant_id = restaurant.restaurant_id
    LEFT JOIN best_clients
           ON best_clients.restaurant_id = restaurant.restaurant_id
    ORDER BY restaurant.restaurant_name;
$$;
