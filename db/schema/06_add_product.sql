-- Добавление блюда (FOOD-104).
-- Принимает все атрибуты блюда, кроме product_id — он берётся из DEFAULT (BR-11.1).
-- Перед вставкой проверяем данные сами, чтобы ошибка была понятной, а не текстом
-- про нарушение какого-то ограничения.
-- Фото и рейтинг могут быть пустыми (BR-5.6, BR-9.7), поэтому у них DEFAULT NULL.
CREATE PROCEDURE sintsev_food.add_product(
    p_restaurant_id       uuid,
    p_product_category_id uuid,
    p_name                varchar,
    p_price               numeric,
    p_status              sintsev_food.product_status,
    p_description         text,
    p_photo_url           text    DEFAULT NULL,
    p_rating              numeric DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sintsev_food.restaurant WHERE restaurant_id = p_restaurant_id) THEN
        RAISE EXCEPTION 'Ресторан % не найден', p_restaurant_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM sintsev_food.product_category WHERE product_category_id = p_product_category_id) THEN
        RAISE EXCEPTION 'Категория блюд % не найдена', p_product_category_id;
    END IF;

    IF p_name IS NULL OR p_name = '' THEN
        RAISE EXCEPTION 'Не указано название блюда';
    END IF;

    IF p_price IS NULL OR p_price < 0 THEN
        RAISE EXCEPTION 'Цена блюда должна быть не меньше 0, передано %', p_price;
    END IF;

    IF p_rating < 0 OR p_rating > 5 THEN
        RAISE EXCEPTION 'Рейтинг блюда должен быть от 0 до 5, передано %', p_rating;
    END IF;

    IF p_status IS NULL THEN
        RAISE EXCEPTION 'Не указан статус блюда';
    END IF;

    IF p_description IS NULL THEN
        RAISE EXCEPTION 'Не указано описание блюда';
    END IF;

    IF EXISTS (SELECT 1 FROM sintsev_food.product
               WHERE restaurant_id = p_restaurant_id AND product_name = p_name) THEN
        RAISE EXCEPTION 'В этом ресторане уже есть блюдо «%»', p_name;
    END IF;

    INSERT INTO sintsev_food.product (product_name, product_category_id, price, restaurant_id,
                                      photo_url, rating, status, description)
    VALUES (p_name, p_product_category_id, p_price, p_restaurant_id,
            p_photo_url, p_rating, p_status, p_description);
END;
$$;
