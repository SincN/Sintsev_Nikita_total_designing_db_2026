-- Пользователь inspector для проверки схемы (FOOD-109).
-- В PostgreSQL пользователь — это роль с правом LOGIN:
-- CREATE USER ... эквивалентно CREATE ROLE ... LOGIN.
-- Скрипт можно запускать повторно: пользователь создаётся, если его ещё нет,
-- иначе обновляются пароль и права.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'inspector') THEN
        CREATE USER inspector PASSWORD 'NetoSQL2025';
    ELSE
        ALTER USER inspector WITH LOGIN PASSWORD 'NetoSQL2025';
    END IF;
END;
$$;

-- Схема: USAGE открывает доступ к объектам, CREATE разрешает создавать новые.
GRANT ALL PRIVILEGES ON SCHEMA sintsev_food TO inspector;
-- Таблицы: SELECT/INSERT/UPDATE/DELETE/TRUNCATE нужны процедурам и проверкам.
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA sintsev_food TO inspector;
-- Функции: EXECUTE для get_statistic, rating_change и uuid_generate_v4 из exts.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA sintsev_food, exts TO inspector;
-- Процедуры: EXECUTE для insert_test_data, erase_test_data, add_product, courier_salary.
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA sintsev_food TO inspector;

-- Системные схемы и exts.
GRANT USAGE ON SCHEMA information_schema, pg_catalog, exts TO inspector;
