-- Блюдо в заказе должно быть из того же ресторана, что и заказ (BR-7.3).
-- Цена позиции всегда берётся из меню на момент добавления блюда, руками её не задать.
-- Если в позиции поменяли только количество, цена остаётся прежней
CREATE FUNCTION sintsev_food.check_order_structure_restaurant()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    order_restaurant   uuid;
    product_restaurant uuid;
    product_price      numeric;
BEGIN
    SELECT restaurant_id INTO order_restaurant
    FROM sintsev_food."order"
    WHERE order_id = NEW.order_id;

    SELECT restaurant_id, price INTO product_restaurant, product_price
    FROM sintsev_food.product
    WHERE product_id = NEW.product_id;

    IF order_restaurant <> product_restaurant THEN
        RAISE EXCEPTION 'Блюдо не из ресторана заказа';
    END IF;

    IF TG_OP = 'INSERT' OR NEW.product_id <> OLD.product_id THEN
        NEW.price := product_price;
    ELSE
        NEW.price := OLD.price;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER order_structure_restaurant_check
BEFORE INSERT OR UPDATE ON sintsev_food.order_structure
FOR EACH ROW EXECUTE FUNCTION sintsev_food.check_order_structure_restaurant();


-- Проверки отзыва: отзыв пишет тот же клиент, ресторан и блюдо из этого заказа (BR-9.2).
-- Отзыв на сам заказ проверяет CHECK в таблице review
CREATE FUNCTION sintsev_food.check_review()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    order_client     uuid;
    order_restaurant uuid;
    order_product    uuid;
BEGIN
    SELECT client_id, restaurant_id INTO order_client, order_restaurant
    FROM sintsev_food."order"
    WHERE order_id = NEW.order_id;

    IF NEW.client_id <> order_client THEN
        RAISE EXCEPTION 'Отзыв может оставить только клиент, сделавший заказ';
    END IF;

    IF NEW.entity_type = 'ресторан' AND NEW.entity_id <> order_restaurant THEN
        RAISE EXCEPTION 'Отзыв на ресторан, которого нет в заказе';
    END IF;

    IF NEW.entity_type = 'блюдо' THEN
        SELECT product_id INTO order_product
        FROM sintsev_food.order_structure
        WHERE order_id = NEW.order_id AND product_id = NEW.entity_id;

        IF order_product IS NULL THEN
            RAISE EXCEPTION 'Отзыв на блюдо, которого нет в заказе';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER review_check
BEFORE INSERT OR UPDATE ON sintsev_food.review
FOR EACH ROW EXECUTE FUNCTION sintsev_food.check_review();


-- Сумма оплаты должна совпадать с суммой заказа (BR-8.4)
CREATE FUNCTION sintsev_food.check_payment_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    order_total numeric;
BEGIN
    SELECT total_amount INTO order_total
    FROM sintsev_food."order"
    WHERE order_id = NEW.order_id;

    IF NEW.amount <> order_total THEN
        RAISE EXCEPTION 'Сумма оплаты не равна сумме заказа';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER payment_amount_check
BEFORE INSERT OR UPDATE ON sintsev_food.payment
FOR EACH ROW EXECUTE FUNCTION sintsev_food.check_payment_amount();


-- То же самое со стороны заказа: нельзя поменять ресторан, если в заказе уже есть блюда,
-- клиента, если есть отзывы, и сумму, если уже есть оплаты (BR-7.3, BR-9.2, BR-8.4).
CREATE FUNCTION sintsev_food.check_order_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.restaurant_id <> OLD.restaurant_id
       AND EXISTS (SELECT 1 FROM sintsev_food.order_structure WHERE order_id = NEW.order_id) THEN
        RAISE EXCEPTION 'Нельзя сменить ресторан у заказа, в котором уже есть блюда';
    END IF;

    IF NEW.client_id <> OLD.client_id
       AND EXISTS (SELECT 1 FROM sintsev_food.review WHERE order_id = NEW.order_id) THEN
        RAISE EXCEPTION 'Нельзя сменить клиента у заказа, на который уже есть отзывы';
    END IF;

    IF NEW.order_amount <> OLD.order_amount
       AND EXISTS (SELECT 1 FROM sintsev_food.payment WHERE order_id = NEW.order_id) THEN
        RAISE EXCEPTION 'Нельзя изменить сумму заказа, по которому уже есть оплаты';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER order_change_check
BEFORE UPDATE ON sintsev_food."order"
FOR EACH ROW EXECUTE FUNCTION sintsev_food.check_order_change();


-- Пересчитываем статус оплаты заказа по попыткам (BR-8.7):
-- есть успешная — 'оплачен', все с ошибкой — 'ошибка', иначе — 'ожидает'
CREATE FUNCTION sintsev_food.update_order_pay_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_order    uuid;
    attempts        int;
    success_count   int;
    error_count     int;
    new_status      sintsev_food.order_pay_status;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_order := OLD.order_id;
    ELSE
        target_order := NEW.order_id;
    END IF;

    SELECT count(*) INTO attempts
    FROM sintsev_food.payment
    WHERE order_id = target_order;

    SELECT count(*) INTO success_count
    FROM sintsev_food.payment
    WHERE order_id = target_order AND status = 'успех';

    SELECT count(*) INTO error_count
    FROM sintsev_food.payment
    WHERE order_id = target_order AND status = 'ошибка';

    IF success_count > 0 THEN
        new_status := 'оплачен';
    ELSIF attempts > 0 AND error_count = attempts THEN
        new_status := 'ошибка';
    ELSE
        new_status := 'ожидает';
    END IF;

    UPDATE sintsev_food."order"
    SET pay_status = new_status
    WHERE order_id = target_order;

    RETURN NULL;
END;
$$;

CREATE TRIGGER payment_pay_status_update
AFTER INSERT OR UPDATE OR DELETE ON sintsev_food.payment
FOR EACH ROW EXECUTE FUNCTION sintsev_food.update_order_pay_status();


-- Сумма заказа без комиссии = стоимость блюд (BR-7.10).
-- После изменения позиций пересчитываем order_amount, комиссия и итог посчитаются сами.
CREATE FUNCTION sintsev_food.update_order_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_order uuid;
    items_sum    numeric;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_order := OLD.order_id;
    ELSE
        target_order := NEW.order_id;
    END IF;

    SELECT round(sum(price * quantity), 2) INTO items_sum
    FROM sintsev_food.order_structure
    WHERE order_id = target_order;

    -- если позиций не осталось (заказ удаляют целиком), сумму не трогаем
    IF items_sum IS NOT NULL THEN
        UPDATE sintsev_food."order"
        SET order_amount = items_sum
        WHERE order_id = target_order
          AND order_amount <> items_sum;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER order_structure_amount_update
AFTER INSERT OR UPDATE OR DELETE ON sintsev_food.order_structure
FOR EACH ROW EXECUTE FUNCTION sintsev_food.update_order_amount();


-- Заказ проверяется целиком в конце транзакции, при COMMIT:
-- в заказе должна быть хотя бы одна позиция (BR-7.14) и общая сумма не меньше 1000 (BR-1.8, BR-7.11).
-- Заказ и позиции приходят в одной транзакции, а сумма считается из позиций,
-- поэтому сразу при вставке заказа это проверить нельзя
CREATE FUNCTION sintsev_food.check_order_complete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    target_order uuid;
    order_total  numeric;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_order := OLD.order_id;
    ELSE
        target_order := NEW.order_id;
    END IF;

    SELECT total_amount INTO order_total
    FROM sintsev_food."order"
    WHERE order_id = target_order;

    -- заказ удалён целиком — проверять нечего
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM sintsev_food.order_structure WHERE order_id = target_order) THEN
        RAISE EXCEPTION 'В заказе должна быть хотя бы одна позиция';
    END IF;

    IF order_total < 1000 THEN
        RAISE EXCEPTION 'Сумма заказа % меньше 1000', order_total;
    END IF;

    RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER order_complete_check
AFTER INSERT OR UPDATE OF order_amount ON sintsev_food."order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION sintsev_food.check_order_complete();

CREATE CONSTRAINT TRIGGER order_structure_complete_check
AFTER INSERT OR UPDATE OR DELETE ON sintsev_food.order_structure
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION sintsev_food.check_order_complete();
