-- exts с uuid-ossp уже есть в базе (BR-13.3), здесь её не создаём

CREATE SCHEMA IF NOT EXISTS sintsev_food;

-- BR-4.3
CREATE TYPE sintsev_food.restaurant_status AS ENUM ('активен', 'неактивен');

-- BR-5.5
CREATE TYPE sintsev_food.product_status AS ENUM ('доступно', 'нет_в_наличии', 'архив');

-- BR-6.2
CREATE TYPE sintsev_food.courier_status AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');

-- BR-7.7
CREATE TYPE sintsev_food.order_status AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');

-- BR-7.9
CREATE TYPE sintsev_food.order_pay_status AS ENUM ('ожидает', 'оплачен', 'ошибка');

-- BR-8.2 (статус попытки оплаты)
CREATE TYPE sintsev_food.payment_status AS ENUM ('успех', 'ошибка', 'в_обработке');

-- BR-8.2 (тип оплаты)
CREATE TYPE sintsev_food.payment_type AS ENUM ('карта', 'наличные', 'безнал');

-- BR-9.1
CREATE TYPE sintsev_food.review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ');
