# Входные данные

Файлы данных хранятся только локально и исключены из Git. Здесь перечислены пути относительно корня репозитория.

| Работа | Требуемые файлы |
| --- | --- |
| 1 | `data/lab-01/olist.duckdb` с таблицами из `labs/lab-01/schema.sql` |
| 2 | `data/lab-02/lab2_timeseries_coffee.csv`, `data/lab-02/lab2_households.csv` |
| 4 | `data/lab-04/olist_metrics.csv`, `data/lab-04/olist_paneldata.csv`, `data/lab-04/telco_panel.csv`, `data/lab-04/telco_survival.csv` |
| 12 | `data/lab-12/bank_marketing.csv` |

Для работы 1 можно скопировать локальную учебную базу, переименовав её в `olist.duckdb`. Либо положить в `data/lab-01/` исходные CSV: `olist_customers_dataset.csv`, `olist_sellers_dataset.csv`, `product_category_name_translation.csv`, `olist_products_dataset.csv`, `olist_orders_dataset.csv`, `olist_order_items_dataset.csv`, `olist_order_payments_dataset.csv`, `olist_order_reviews_dataset.csv`, `olist_geolocation_dataset.csv`.

Затем из `labs/lab-01/` создать новую базу с помощью DuckDB CLI:

```sh
duckdb ../../data/lab-01/olist.duckdb < schema.sql
```

SQL предназначен для новой базы: повторное выполнение на уже заполненной базе приведёт к конфликтам существующих таблиц. Исходные CSV в комплект не входят.

Для работы 12 используйте исходный учебный CSV банковского маркетинга под нейтральным именем `bank_marketing.csv`; содержание и столбцы менять не требуется. Другой датасет с похожим названием не является гарантированно совместимой заменой.

В работе 2 временные базы `analysis.duckdb` и `panel.duckdb` создаются при запуске в каталоге работы и игнорируются Git.
