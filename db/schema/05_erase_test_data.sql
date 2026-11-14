-- Удаление тестовых данных (FOOD-103).
-- Все таблицы очищаются одной командой TRUNCATE: в ней перечислены все связанные таблицы,
-- поэтому внешние ключи не мешают и порядок не важен.
-- TRUNCATE не запускает построчные триггеры, так что проверки заказов, оплат и отзывов
-- при очистке не срабатывают, и на больших объёмах это быстро.
-- Типы, функции, процедуры и триггеры не трогаются, повторный вызов на пустой схеме не падает.
CREATE PROCEDURE sintsev_food.erase_test_data()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE
        sintsev_food.review,
        sintsev_food.payment,
        sintsev_food.order_structure,
        sintsev_food."order",
        sintsev_food.courier_pay,
        sintsev_food.courier,
        sintsev_food.product,
        sintsev_food.product_category,
        sintsev_food.restaurant,
        sintsev_food.client_address,
        sintsev_food.client,
        sintsev_food.address;
END;
$$;
