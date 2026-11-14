-- Пересчёт рейтинга одного объекта по отзывам (FOOD-105, BR-9.6, BR-9.7).
-- Для 'заказ' ничего не делает: у заказа агрегированного рейтинга нет.
-- Если отзывов нет, avg вернёт NULL, и рейтинг станет пустым.
CREATE OR REPLACE FUNCTION sintsev_food.recalculate_rating(
    entity_type_value sintsev_food.review_entity_type,
    entity_identifier uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    average_rating numeric;
BEGIN
    IF entity_type_value = 'блюдо' THEN
        SELECT round(avg(rating), 2) INTO average_rating
        FROM sintsev_food.review
        WHERE entity_type = 'блюдо' AND entity_id = entity_identifier;

        UPDATE sintsev_food.product
        SET rating = average_rating
        WHERE product_id = entity_identifier;

    ELSIF entity_type_value = 'ресторан' THEN
        SELECT round(avg(rating), 2) INTO average_rating
        FROM sintsev_food.review
        WHERE entity_type = 'ресторан' AND entity_id = entity_identifier;

        UPDATE sintsev_food.restaurant
        SET rating = average_rating
        WHERE restaurant_id = entity_identifier;
    END IF;
END;
$$;

-- При изменении отзыва пересчитывает нужные объекты.
-- INSERT — только NEW, DELETE — только OLD.
-- UPDATE пересчитывает только если изменились entity_type, entity_id или rating.
-- Если объект тот же — пересчитываем один раз NEW; если изменился — OLD и NEW.
-- Рекурсии нет: функция меняет product/restaurant, а на них триггеров нет.
CREATE OR REPLACE FUNCTION sintsev_food.rating_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM sintsev_food.recalculate_rating(OLD.entity_type, OLD.entity_id);
        RETURN NULL;
    END IF;

    IF TG_OP = 'INSERT' THEN
        PERFORM sintsev_food.recalculate_rating(NEW.entity_type, NEW.entity_id);
        RETURN NULL;
    END IF;

    -- Ранний выход: если не изменились ни объект, ни рейтинг — пересчитывать нечего.
    IF OLD.entity_type = NEW.entity_type
       AND OLD.entity_id = NEW.entity_id
       AND OLD.rating = NEW.rating THEN
        RETURN NULL;
    END IF;

    -- При изменении объекта пересчитываем старый и новый объект, иначе — только новый.
    IF OLD.entity_type <> NEW.entity_type
       OR OLD.entity_id <> NEW.entity_id THEN
        PERFORM sintsev_food.recalculate_rating(OLD.entity_type, OLD.entity_id);
    END IF;

    PERFORM sintsev_food.recalculate_rating(NEW.entity_type, NEW.entity_id);

    RETURN NULL;
END;
$$;

CREATE TRIGGER review_rating_change
AFTER INSERT OR UPDATE OR DELETE ON sintsev_food.review
FOR EACH ROW EXECUTE FUNCTION sintsev_food.rating_change();
