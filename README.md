# goit-rdb-fp — фінальний проєкт «Relational Databases for DS»

**Совпенко Владислав.** Датасет `infectious_cases.csv` (статистика інфекційних захворювань по країнах і регіонах, 1920–2023, 10 521 рядок) — з курсового Google Drive, копія лежить у `data/`.

## Структура репозиторію

| Шлях | Що це |
|---|---|
| `notebooks/fp_infectious_cases.ipynb` | ноутбук з усіма кроками і output клітинок (Colab: PostgreSQL через `pgserver`; локально — `FP_PG_URI`) |
| `sql/fp_queries.sql` | усі SQL-запити у порядку виконання (без Python) |
| `data/infectious_cases.csv` | вихідний датасет |
| `screenshots/*.png` | результати запитів по кожному завданню |

## Що зроблено

**1. Завантаження.** `CREATE SCHEMA pandemic`, `SET search_path TO pandemic`, імпорт CSV через pandas `to_sql` у `infectious_cases_raw` (текст), типізована `infectious_cases` (`year INTEGER`, показники `NUMERIC`, порожні значення → `NULL`). Огляд: 245 сутностей, 1 128 рядків без ISO-коду (агрегати World, Africa, групи WB/WHO), `Number_rabies` заповнений для 6 780 рядків.

**2. Нормалізація до 3НФ.** `Code` залежить лише від `Entity` (частина ключа `Entity, Year`) → винесено довідник
`entities(entity_id SERIAL PK, entity, code, UNIQUE NULLS NOT DISTINCT (entity, code))` — 245 рядків,
і таблицю показників `cases(case_id PK, entity_id FK → entities, year, 9 показників, UNIQUE(entity_id, year))` — 10 521 рядок. Заповнення через `JOIN ... ON e.code IS NOT DISTINCT FROM c.code` (NULL-safe). Перевірка `EXCEPT` → 0 втрачених рядків.

**3. Аналіз `Number_rabies`.** `AVG / MIN / MAX / SUM` по `entity_id` з `WHERE number_rabies IS NOT NULL`, `ORDER BY avg DESC LIMIT 10`. Топ: World (сер. 20 192), Lower Middle Income (WB), South Asia (WB) …, єдина країна в десятці — Індія (8 599). Додатково той самий запит лише по країнах.

**4. Різниця в роках.** `MAKE_DATE(year, 1, 1)`, `CURRENT_DATE`, `EXTRACT(YEAR FROM AGE(CURRENT_DATE, MAKE_DATE(year,1,1)))` — повні роки.

**5. Власні функції** (мова SQL):
- `years_since(p_year INTEGER) RETURNS INTEGER` — та ж логіка, що в п. 4 (`STABLE`);
- `avg_cases_per_period(p_cases NUMERIC, p_divisor NUMERIC) RETURNS NUMERIC` — кількість за рік / дільник (12 — місяць, 4 — квартал, 2 — півріччя), при нульовому дільнику повертає `NULL`.
Обидві використано в запитах; фільтр «лише числові значення» — `number_rabies IS NOT NULL` у типізованій таблиці та перевірка regex `^[0-9]+(\.[0-9]+)?$` на raw-шарі (обидва дають 6 780 рядків).

## Як запустити

**Google Colab:** `!git clone https://github.com/VladyslavSovpenko/goit-rdb-fp`, відкрити ноутбук, *Runtime → Restart and run all*. PostgreSQL 16 стартує через `pgserver`; CSV береться з `data/`, а якщо його немає — завантажується з курсового Google Drive.

**Локально з PostgreSQL 16** (наприклад, Docker `postgres:16`):

```bash
export FP_PG_URI='postgresql+psycopg2://user:password@localhost:5432/dbname'
jupyter notebook notebooks/fp_infectious_cases.ipynb
# або лише SQL (після імпорту CSV у pandemic.infectious_cases_raw):
psql "$FP_PG_URI" -f sql/fp_queries.sql
```
