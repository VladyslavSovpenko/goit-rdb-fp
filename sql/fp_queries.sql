-- Фінальний проєкт. Relational Databases for DS — Совпенко Владислав
-- Усі запити у порядку виконання ноутбука notebooks/fp_infectious_cases.ipynb
-- Імпорт CSV виконано через pandas.to_sql у таблицю pandemic.infectious_cases_raw (див. ноутбук)

-- ===== Завдання 1. Завантаження даних =====
DROP SCHEMA IF EXISTS pandemic CASCADE;
CREATE SCHEMA IF NOT EXISTS pandemic;

DROP TABLE IF EXISTS infectious_cases;
CREATE TABLE infectious_cases AS
SELECT
    "Entity"                        AS entity,
    "Code"                          AS code,
    "Year"::INTEGER                 AS year,
    "Number_yaws"::NUMERIC          AS number_yaws,
    "polio_cases"::NUMERIC          AS polio_cases,
    "cases_guinea_worm"::NUMERIC    AS cases_guinea_worm,
    "Number_rabies"::NUMERIC        AS number_rabies,
    "Number_malaria"::NUMERIC       AS number_malaria,
    "Number_hiv"::NUMERIC           AS number_hiv,
    "Number_tuberculosis"::NUMERIC  AS number_tuberculosis,
    "Number_smallpox"::NUMERIC      AS number_smallpox,
    "Number_cholera_cases"::NUMERIC AS number_cholera_cases
FROM infectious_cases_raw;

SELECT
    COUNT(*)                                  AS rows_total,
    COUNT(DISTINCT entity)                    AS entities,
    COUNT(*) FILTER (WHERE code IS NULL)      AS rows_without_code,
    MIN(year)                                 AS year_min,
    MAX(year)                                 AS year_max,
    COUNT(number_rabies)                      AS rabies_not_null,
    COUNT(number_malaria)                     AS malaria_not_null,
    COUNT(polio_cases)                        AS polio_not_null,
    COUNT(number_smallpox)                    AS smallpox_not_null
FROM infectious_cases;

-- ===== Завдання 2. Нормалізація до 3НФ =====
DROP TABLE IF EXISTS cases;
DROP TABLE IF EXISTS entities;

CREATE TABLE entities (
    entity_id  SERIAL PRIMARY KEY,
    entity     TEXT NOT NULL,
    code       TEXT,
    UNIQUE NULLS NOT DISTINCT (entity, code)
);

INSERT INTO entities (entity, code)
SELECT DISTINCT entity, code
FROM infectious_cases
ORDER BY entity, code;

CREATE TABLE cases (
    case_id               SERIAL PRIMARY KEY,
    entity_id             INTEGER NOT NULL REFERENCES entities(entity_id),
    year                  INTEGER NOT NULL CHECK (year BETWEEN 1800 AND 2100),
    number_yaws           NUMERIC,
    polio_cases           NUMERIC,
    cases_guinea_worm     NUMERIC,
    number_rabies         NUMERIC,
    number_malaria        NUMERIC,
    number_hiv            NUMERIC,
    number_tuberculosis   NUMERIC,
    number_smallpox       NUMERIC,
    number_cholera_cases  NUMERIC,
    UNIQUE (entity_id, year)
);

INSERT INTO cases (entity_id, year, number_yaws, polio_cases, cases_guinea_worm, number_rabies,
                   number_malaria, number_hiv, number_tuberculosis, number_smallpox, number_cholera_cases)
SELECT e.entity_id, c.year, c.number_yaws, c.polio_cases, c.cases_guinea_worm, c.number_rabies,
       c.number_malaria, c.number_hiv, c.number_tuberculosis, c.number_smallpox, c.number_cholera_cases
FROM infectious_cases AS c
JOIN entities AS e
  ON e.entity = c.entity
 AND e.code IS NOT DISTINCT FROM c.code;      -- NULL-safe порівняння коду;

SELECT
    (SELECT COUNT(*) FROM infectious_cases)                                AS original_rows,
    (SELECT COUNT(*) FROM cases c JOIN entities e USING (entity_id))      AS joined_rows,
    (SELECT COUNT(*) FROM (
        SELECT entity, code, year, number_rabies FROM infectious_cases
        EXCEPT
        SELECT e.entity, e.code, c.year, c.number_rabies FROM cases c JOIN entities e USING (entity_id)
    ) d)                                                                   AS rows_lost;

-- ===== Завдання 3. Аналіз `Number_rabies` =====
SELECT
    e.entity_id,
    e.entity,
    e.code,
    COUNT(c.number_rabies)             AS years_with_data,
    ROUND(AVG(c.number_rabies), 3)     AS avg_rabies,
    ROUND(MIN(c.number_rabies), 3)     AS min_rabies,
    ROUND(MAX(c.number_rabies), 3)     AS max_rabies,
    ROUND(SUM(c.number_rabies), 3)     AS sum_rabies
FROM cases AS c
JOIN entities AS e USING (entity_id)
WHERE c.number_rabies IS NOT NULL
GROUP BY e.entity_id, e.entity, e.code
ORDER BY avg_rabies DESC
LIMIT 10;

SELECT e.entity, e.code,
       ROUND(AVG(c.number_rabies), 3) AS avg_rabies,
       ROUND(MIN(c.number_rabies), 3) AS min_rabies,
       ROUND(MAX(c.number_rabies), 3) AS max_rabies,
       ROUND(SUM(c.number_rabies), 3) AS sum_rabies
FROM cases c JOIN entities e USING (entity_id)
WHERE c.number_rabies IS NOT NULL AND e.code IS NOT NULL
GROUP BY e.entity, e.code
ORDER BY avg_rabies DESC
LIMIT 10;

-- ===== Завдання 4. Колонка різниці в роках =====
SELECT
    e.entity,
    c.year,
    MAKE_DATE(c.year, 1, 1)                                             AS year_start_date,
    CURRENT_DATE                                                        AS today,
    EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(c.year, 1, 1)))::INT  AS years_diff
FROM cases AS c
JOIN entities AS e USING (entity_id)
WHERE e.entity = 'Ukraine'
ORDER BY c.year DESC
LIMIT 10;

SELECT DISTINCT year,
       MAKE_DATE(year, 1, 1)                                            AS year_start_date,
       CURRENT_DATE                                                     AS today,
       EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year, 1, 1)))::INT AS years_diff
FROM cases
WHERE year IN (SELECT MIN(year) FROM cases) OR year IN (SELECT MAX(year) FROM cases)
ORDER BY year;

-- ===== Завдання 5. Власні функції =====
CREATE OR REPLACE FUNCTION pandemic.years_since(p_year INTEGER)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(p_year, 1, 1)))::INTEGER;
$$;

SELECT e.entity, c.year,
       MAKE_DATE(c.year, 1, 1)  AS year_start_date,
       years_since(c.year)      AS years_diff_fn,
       EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(c.year, 1, 1)))::INT AS years_diff_builtin
FROM cases c JOIN entities e USING (entity_id)
WHERE e.code = 'UKR'
ORDER BY c.year DESC
LIMIT 5;

CREATE OR REPLACE FUNCTION pandemic.avg_cases_per_period(p_cases NUMERIC, p_divisor NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
             WHEN p_divisor IS NULL OR p_divisor = 0 THEN NULL
             ELSE ROUND(p_cases / p_divisor, 3)
           END;
$$;

SELECT avg_cases_per_period(1200, 12) AS per_month,
       avg_cases_per_period(1200, 4)  AS per_quarter,
       avg_cases_per_period(1200, 2)  AS per_half_year,
       avg_cases_per_period(1200, 0)  AS zero_divisor;

SELECT
    (SELECT COUNT(*) FROM cases WHERE number_rabies IS NOT NULL)                                   AS numeric_typed,
    (SELECT COUNT(*) FROM infectious_cases_raw WHERE "Number_rabies" ~ '^[0-9]+(\.[0-9]+)?$')     AS numeric_regex_raw;

SELECT
    e.entity,
    c.year,
    c.number_rabies                                AS rabies_per_year,
    avg_cases_per_period(c.number_rabies, 12)      AS rabies_per_month,
    avg_cases_per_period(c.number_rabies, 4)       AS rabies_per_quarter,
    avg_cases_per_period(c.number_rabies, 2)       AS rabies_per_half_year,
    years_since(c.year)                            AS years_ago
FROM cases AS c
JOIN entities AS e USING (entity_id)
WHERE c.number_rabies IS NOT NULL                  -- лише числові значення
  AND e.code IN ('IND', 'UKR', 'POL')
  AND c.year >= 2017
ORDER BY e.entity, c.year DESC;

SELECT c.year,
       c.number_rabies                               AS rabies_per_year,
       avg_cases_per_period(c.number_rabies, 12)     AS rabies_per_month,
       avg_cases_per_period(c.number_rabies, 4)      AS rabies_per_quarter,
       avg_cases_per_period(c.number_rabies, 2)      AS rabies_per_half_year
FROM cases c JOIN entities e USING (entity_id)
WHERE e.code = 'OWID_WRL' AND c.number_rabies IS NOT NULL
ORDER BY c.year DESC
LIMIT 6;

SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'pandemic'
ORDER BY table_name;

SELECT routine_name, data_type AS returns
FROM information_schema.routines
WHERE routine_schema = 'pandemic'
ORDER BY routine_name;
