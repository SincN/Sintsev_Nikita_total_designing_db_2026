CREATE TABLE sintsev_food.address (
    address_id       uuid NOT NULL DEFAULT exts.uuid_generate_v4(),     -- BR-11.1
    street           varchar(100) NOT NULL,                              -- BR-3.1
    house_number     varchar(10)  NOT NULL,                              -- BR-3.1
    apartment_office varchar(10),                                        -- NULL: BR-3.2
    PRIMARY KEY (address_id)
);

-- один и тот же адрес нельзя завести дважды, пустая квартира тоже учитывается (BR-3.3)
CREATE UNIQUE INDEX ON sintsev_food.address (street, house_number, coalesce(apartment_office, ''));

CREATE TABLE sintsev_food.client (
    client_id    uuid NOT NULL DEFAULT exts.uuid_generate_v4(),         -- BR-11.1
    login        varchar(50) NOT NULL UNIQUE,                            -- BR-2.2
    password     char(32)    NOT NULL,                                   -- BR-2.3
    phone_number char(12)    NOT NULL UNIQUE,                            -- BR-2.2
    PRIMARY KEY (client_id),
    CHECK (password ~ '^[0-9a-f]{32}$')                                  -- BR-2.3
);

CREATE TABLE sintsev_food.client_address (
    client_id  uuid NOT NULL,
    address_id uuid NOT NULL,
    PRIMARY KEY (client_id, address_id),                                       -- BR-2.5
    FOREIGN KEY (client_id)  REFERENCES sintsev_food.client (client_id),       -- BR-2.4
    FOREIGN KEY (address_id) REFERENCES sintsev_food.address (address_id)      -- BR-2.4
);

CREATE TABLE sintsev_food.restaurant (
    restaurant_id   uuid NOT NULL DEFAULT exts.uuid_generate_v4(),      -- BR-11.1
    restaurant_name varchar(100) NOT NULL,                              -- BR-4.1
    address_id      uuid NOT NULL UNIQUE,                               -- BR-3.3
    description     text NOT NULL,                                      -- BR-4.1
    work_start      time NOT NULL,                                      -- BR-4.4
    work_end        time NOT NULL,                                      -- BR-4.4
    company_details text NOT NULL,                                      -- BR-4.1, BR-4.5
    rating          numeric(3,2),                                       -- NULL: BR-9.7
    status          sintsev_food.restaurant_status NOT NULL,            -- BR-4.3
    PRIMARY KEY (restaurant_id),
    FOREIGN KEY (address_id) REFERENCES sintsev_food.address (address_id),  -- BR-3.3, BR-3.4
    CHECK (rating BETWEEN 0 AND 5),                                     -- BR-4.2
    CHECK (work_end > work_start)                                       -- BR-4.4
);

CREATE TABLE sintsev_food.product_category (
    product_category_id   uuid NOT NULL DEFAULT exts.uuid_generate_v4(),  -- BR-11.1
    product_category_name varchar(50) NOT NULL UNIQUE,                    -- справочник (BR-5.7), названия не повторяются
    PRIMARY KEY (product_category_id)
);

CREATE TABLE sintsev_food.product (
    product_id          uuid NOT NULL DEFAULT exts.uuid_generate_v4(),      -- BR-11.1
    product_name        varchar(100) NOT NULL,                              -- BR-5.2
    product_category_id uuid NOT NULL,                                      -- BR-5.1
    price               numeric(10,2) NOT NULL,                             -- BR-5.2
    restaurant_id       uuid NOT NULL,                                      -- BR-5.1
    photo_url           text,                                               -- NULL: BR-5.6
    rating              numeric(3,2),                                       -- NULL: BR-9.7
    status              sintsev_food.product_status NOT NULL,               -- BR-5.5
    description         text NOT NULL,                                      -- BR-5.2
    PRIMARY KEY (product_id),
    FOREIGN KEY (product_category_id)
        REFERENCES sintsev_food.product_category (product_category_id),     -- BR-5.1
    FOREIGN KEY (restaurant_id) REFERENCES sintsev_food.restaurant (restaurant_id),  -- BR-5.1
    UNIQUE (restaurant_id, product_name),                                   -- в одном ресторане названия блюд не повторяются
    CHECK (price >= 0),                                                     -- BR-5.3
    CHECK (rating BETWEEN 0 AND 5)                                          -- BR-5.4
);

CREATE TABLE sintsev_food.courier (
    courier_id     uuid NOT NULL DEFAULT exts.uuid_generate_v4(),       -- BR-11.1
    fio            varchar(150) NOT NULL,                               -- BR-6.1
    phone_number   char(12)     NOT NULL UNIQUE,                        -- BR-6.1, номер у курьеров не повторяется
    status         sintsev_food.courier_status NOT NULL,                -- BR-6.2
    hire_date      date NOT NULL,                                       -- BR-6.1
    dismissal_date date,                                                -- NULL: BR-6.3, BR-11.3
    coefficient    numeric(2,1) NOT NULL DEFAULT 0.1,                   -- BR-6.5
    PRIMARY KEY (courier_id),
    CHECK (coefficient BETWEEN 0.1 AND 0.5),                            -- BR-6.4
    CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL),           -- BR-6.3
    CHECK (dismissal_date >= hire_date)                                 -- увольнение не раньше найма
);

CREATE TABLE sintsev_food.courier_pay (
    courier_id       uuid NOT NULL,                                     -- BR-10.2
    year             int  NOT NULL,                                     -- BR-10.2
    month            int  NOT NULL,                                     -- BR-10.2
    amount           numeric(12,2) NOT NULL,                            -- BR-10.2
    coefficient_used numeric(2,1)  NOT NULL,                            -- BR-10.2
    PRIMARY KEY (courier_id, year, month),                              -- BR-10.3
    FOREIGN KEY (courier_id) REFERENCES sintsev_food.courier (courier_id),  -- BR-10.1
    CHECK (month BETWEEN 1 AND 12),                                     -- номер месяца
    CHECK (amount >= 0),                                                -- BR-10.4
    CHECK (coefficient_used BETWEEN 0.1 AND 0.5)                        -- BR-6.4, BR-10.2
);

CREATE TABLE sintsev_food."order" (
    order_id           uuid NOT NULL DEFAULT exts.uuid_generate_v4(),     -- BR-11.1
    courier_id         uuid NOT NULL,                                     -- BR-7.5
    client_id          uuid NOT NULL,                                     -- BR-7.2
    address_id         uuid NOT NULL,                                     -- BR-7.4
    restaurant_id      uuid NOT NULL,                                     -- BR-7.2
    order_timestamp    timestamp NOT NULL,                                -- BR-7.1
    delivery_timestamp timestamp,                                         -- NULL: BR-7.12
    order_amount       numeric(12,2) NOT NULL DEFAULT 0,                  -- BR-7.10, пересчитывается из позиций
    commission         numeric(12,2) NOT NULL
                       GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,                 -- BR-1.4, BR-7.10
    total_amount       numeric(12,2) NOT NULL
                       GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED,  -- BR-7.10
    status             sintsev_food.order_status NOT NULL,                -- BR-7.6, BR-7.7
    pay_status         sintsev_food.order_pay_status NOT NULL DEFAULT 'ожидает',  -- BR-7.8, BR-7.9; у нового заказа оплат ещё нет
    description        text NOT NULL,                                     -- BR-11.3
    PRIMARY KEY (order_id),
    FOREIGN KEY (courier_id)    REFERENCES sintsev_food.courier (courier_id),        -- BR-7.5, BR-1.3
    FOREIGN KEY (client_id)     REFERENCES sintsev_food.client (client_id),          -- BR-7.1, BR-7.2
    FOREIGN KEY (restaurant_id) REFERENCES sintsev_food.restaurant (restaurant_id),  -- BR-7.2
    FOREIGN KEY (client_id, address_id)
        REFERENCES sintsev_food.client_address (client_id, address_id),              -- BR-7.4
    CHECK (order_amount >= 0),                                            -- BR-5.3, BR-7.10
    CHECK (delivery_timestamp >= order_timestamp),                        -- BR-7.13
    CHECK (status <> 'доставлен' OR delivery_timestamp IS NOT NULL)       -- BR-7.12
);

CREATE TABLE sintsev_food.order_structure (
    order_id   uuid NOT NULL,                                                -- BR-7.14
    product_id uuid NOT NULL,                                                -- BR-7.14
    quantity   numeric(8,3) NOT NULL,                                        -- BR-7.14
    price      numeric(10,2) NOT NULL,                                       -- цена за единицу блюда на момент заказа для корректного пересчета суммы старых заказов
    PRIMARY KEY (order_id, product_id),                                      -- BR-7.16
    FOREIGN KEY (order_id)   REFERENCES sintsev_food."order" (order_id),     -- BR-7.14
    FOREIGN KEY (product_id) REFERENCES sintsev_food.product (product_id),   -- BR-7.14
    CHECK (quantity > 0),                                                    -- BR-7.15
    CHECK (price >= 0)                                                       -- BR-5.3
);

CREATE TABLE sintsev_food.payment (
    payment_id        uuid NOT NULL DEFAULT exts.uuid_generate_v4(),     -- BR-11.1
    order_id          uuid NOT NULL,                                     -- BR-8.1
    payment_type      sintsev_food.payment_type NOT NULL,                -- BR-8.2, BR-8.6
    amount            numeric(12,2) NOT NULL,                            -- BR-8.2
    transaction_id    varchar(64) NOT NULL UNIQUE,                       -- BR-8.2, BR-8.3
    payment_timestamp timestamp NOT NULL,                                -- BR-8.2
    status            sintsev_food.payment_status NOT NULL,              -- BR-8.2
    PRIMARY KEY (payment_id),
    FOREIGN KEY (order_id) REFERENCES sintsev_food."order" (order_id)    -- BR-8.1
);

-- у заказа может быть только одна успешная оплата (BR-8.1)
CREATE UNIQUE INDEX ON sintsev_food.payment (order_id) WHERE status = 'успех';

-- индекс для поиска всех платежей по заказу для поиска оплат по заказу
CREATE INDEX ON sintsev_food.payment (order_id);

CREATE TABLE sintsev_food.review (
    review_id        uuid NOT NULL DEFAULT exts.uuid_generate_v4(),     -- BR-11.1
    client_id        uuid NOT NULL,                                     -- BR-9.1
    order_id         uuid NOT NULL,                                     -- BR-9.2
    review_timestamp timestamp NOT NULL,                                -- BR-9.3
    entity_type      sintsev_food.review_entity_type NOT NULL,          -- BR-9.1
    entity_id        uuid NOT NULL,                                     -- BR-9.1
    description      text NOT NULL,                                     -- BR-9.3
    photo_url        text,                                              -- NULL: BR-9.3
    rating           smallint NOT NULL,                                 -- BR-9.3
    PRIMARY KEY (review_id),
    FOREIGN KEY (client_id) REFERENCES sintsev_food.client (client_id), -- BR-9.1
    FOREIGN KEY (order_id)  REFERENCES sintsev_food."order" (order_id), -- BR-9.2
    UNIQUE (order_id, entity_type, entity_id),                          -- BR-9.5
    CHECK (rating BETWEEN 1 AND 5),                                     -- BR-9.4
    CHECK (entity_type <> 'заказ' OR entity_id = order_id)              -- BR-9.2
);

-- индекс для поиска всех отзывов на блюдо или ресторан (используется при рассчете рейтинга в триггерах)
CREATE INDEX ON sintsev_food.review (entity_type, entity_id);
