library(DBI)
library(duckdb)


# Здесь задания 2 и 3. Задание 1 в schema.sql

# Для наглядности я сделаю подключение для каждого запроса

db_path <- "../../data/lab-01/olist.duckdb"
if (!file.exists(db_path)) stop("База данных не найдена. См. data/README.md.")

# 1 задание 1 вараинт
# Найдите все заказы, которые были успешно доставлены (order_status = 'delivered') и 
# сделаны в течение 2018 года. 
# Выведите только поля order_id, order_status и order_delivered_customer_date.

con <- dbConnect(duckdb::duckdb(), db_path)

query1 <- "
  SELECT order_id, order_status, order_delivered_customer_date
  FROM olist_orders_dataset
  WHERE order_status = 'delivered'
    AND EXTRACT(YEAR FROM order_purchase_timestamp) = 2018;
    
  -- выбираем нужные поля из таблицы, где статус 'доставлен'
  -- и 2018 год (из таймстампа забираем год)
  "
  
result1 <- dbGetQuery(con, query1)
print(result1)

dbDisconnect(con)

# 2 задание 2 вариант
# Соедините таблицы orders и order_reviews так, чтобы для каждого отзыва
# с оценкой 5 звёзд вывести: review_id, order_id, review_score
# и дату покупки (order_purchase_timestamp)

con <- dbConnect(duckdb::duckdb(), db_path)

query2 <- "
  SELECT r.review_id, o.order_id, r.review_score, o.order_purchase_timestamp
  FROM olist_order_reviews_dataset r
  JOIN olist_orders_dataset o ON r.order_id = o.order_id
  WHERE r.review_score = 5;
  
  -- склеиваем таблицу отзывов r и таблицу заказов o по столбцу order_id (чтобы соответствовали друг другу)
  -- оставляю только пятибальные отщывы и вывожу заданные параметры
"


result2 <- dbGetQuery(con, query2)
print(result2)
dbDisconnect(con)

# задание 3 вариант 1
# Для каждого штата (customer_state) рассчитайте общее количество заказов, сделанных в 2018 году.
# Оставьте только те штаты, где было оформлено более 1000 заказов.
# Отсортируйте результат по убыванию числа заказов.

con <- dbConnect(duckdb::duckdb(), db_path)

query3 <- "
  SELECT c.customer_state, COUNT(o.order_id) AS itogovoe_po_zakazam
  FROM olist_orders_dataset o
  JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
  WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) = 2018
  GROUP BY c.customer_state
  HAVING COUNT(o.order_id) > 1000
  ORDER BY itogovoe_po_zakazam DESC;
  
  -- таблицу с заказами о объединяем с таблицей клиентов c по столбцу customer_id (чтобы соответствовали друг другу)
  -- снова забираем 2018 год из таймстампа и группируем по штату
  -- после группировки оставляем только полученные штаты, где число заказов больше тысячи
  -- по итоговому числу по заказам сортируем по убыванию и выводим, что получилось
"

result3 <- dbGetQuery(con, query3)
print(result3)
dbDisconnect(con)

# задание 4 вариант 2
# Рассчитайте среднее время доставки (в днях) по каждому штату клиента (customer_state) и статусу заказа (order_status). Используйте таблицы
# orders, customers и рассчитайте разницу между order_delivered_customer_- date и order_purchase_timestamp

con <- dbConnect(duckdb::duckdb(), db_path)

query4 <- "
  SELECT c.customer_state, o.order_status,
         AVG(DATE_DIFF('day', DATE(o.order_purchase_timestamp), DATE(o.order_delivered_customer_date))) AS avg_delivery_time
  FROM olist_orders_dataset o
  JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
  GROUP BY c.customer_state, o.order_status;
  
  -- таблицу с заказами о объединяем с таблицей клиентов c по столбцу customer_id (чтобы соответствовали друг другу)
  -- группируем по штату и статусу заказа
  -- выводим штат, выводим статус заказа и среднее время доставки
  -- можно было бы поставить еще условие WHERE o.order_delivered_customer_date IS NOT NULL;
  -- чтобы сделать вывод более красивым, но я оставил как есть
"

result4 <- dbGetQuery(con, query4)

print(result4)
dbDisconnect(con)


# задание 5 вариант 2
# Для каждого клиента (customer_unique_id) пронумеруйте его заказы по хронологии (от самого раннего 
# к самому позднему). Используйте ROW_NUMBER() с сортировкой по order_purchase_timestamp.

con <- dbConnect(duckdb::duckdb(), db_path)



query5 <- "
  SELECT o.order_id, c.customer_unique_id, o.order_purchase_timestamp,
         ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp) as sort_purchase
  FROM olist_orders_dataset o
  JOIN olist_customers_dataset c ON o.customer_id = c.customer_id;
  
  -- таблицу с заказами о объединяем с таблицей клиентов c по столбцу customer_id (чтобы соответствовали друг другу)
  -- выводим заявленные столбцы + создаем группы через PARTITION по id клиента и упорядочиваем по времени покупки, добавляем ROW_NUMBER
  -- уникальный номер в рамках группы заказов одного клиента
  -- запсевдонимлю строку вывода с ROW_NUMBER, чтобы было визуально легче
"

result5 <- dbGetQuery(con, query5)

print(result5)
dbDisconnect(con)



# НОВЫЙ НОМЕР
# Вариант 2
# Задание 1
# Для каждого продавца (seller_id) рассчитайте метрику «доля своевременных доставок» за 2017–2018 гг. 
# Своевременной считается доставка, если order_delivered_customer_date ≤ order_estimated_delivery_date.

con <- dbConnect(duckdb::duckdb(), db_path)

query11 <- "
  SELECT so.seller_id,
         AVG(CASE WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 1 ELSE 0 END)
           AS succes_ratio
  FROM (SELECT DISTINCT seller_id, order_id FROM olist_order_items_dataset) so
  JOIN olist_orders_dataset o ON so.order_id = o.order_id
  WHERE EXTRACT(YEAR FROM o.order_purchase_timestamp) IN (2017, 2018)
    AND o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL
  GROUP BY so.seller_id;
  
  -- сначала делаем таблицу so (концептуально seller_orders), где каждая строка - уникальная пара seller_id + order_id
  -- такой шаг необходим, потому что нам интересна доля своевременных доставок, и важно, чтобы 
  -- один заказ продавца считался только один раз, даже если в order_items несколько позиций
  -- дальше соединяем so с таблицей заказов o по order_id, чтобы взять даты доставки и оценочную дату
  -- дальше оставляем только заказы, сделанные в 2017–2018 и 
  -- отсекаем строки с NULL в датах, чтобы сравнение delivered <= estimated было корректным
  -- затем CASE превращает успешную доставку в 1, а неуспешную в 0, а AVG по этим 0/1 даёт долю своевременных доставок
"

result11 <- dbGetQuery(con, query11)

print(result11)
dbDisconnect(con)


# Задание 2
# В таблице order_reviews есть числовая оценка review_score от 1 до 5 
# Создайте новую колонку sentiment в этой таблице по следующим правилам:
#  5 -> 'Positive'
#  4 -> 'Neutral'
#  1, 2, 3 -> 'Negative'

con <- dbConnect(duckdb::duckdb(), db_path)

query22 <- "
  SELECT review_id, order_id, review_score,
         CASE 
           WHEN review_score = 5 THEN 'Positive'
           WHEN review_score = 4 THEN 'Neutral'
           WHEN review_score IN (1, 2, 3) THEN 'Negative'
         END AS mnenie
  FROM olist_order_reviews_dataset;
  
  -- из таблицы отзывов отберу оценки 123, 4,5 и для каждой дам новое название в выводе,
  -- сам столбец кейсвенов назову как mnenie
  -- выведу все, что требуется
"

result22 <- dbGetQuery(con, query22)

print(result22)
dbDisconnect(con)
