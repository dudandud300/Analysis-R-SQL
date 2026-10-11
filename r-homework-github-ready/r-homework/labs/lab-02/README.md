# Лабораторная работа 2

> Это версия исходника для чтения на GitHub: код и авторские пояснения, без вычисленного вывода. Для исполнения используйте [analysis.Rmd](analysis.Rmd).


```r
knitr::opts_chunk$set(
  echo = TRUE,
  warning = FALSE,
  message = FALSE,
  fig.width = 10,
  fig.height = 6,
  fig.align = "center",
  out.width = "90%"
)

options(
  scipen = 999,
  digits = 3
)

```

Установим базовые пакеты указанные в ТЗ, в том числе для работы с .duckdb

```r
library(tidyverse)
library(lubridate)
library(forecast)
library(tseries)
library(ARDL)
library(CausalImpact)
library(TraMineR)
library(geepack)
library(plm)

library(DBI)
library(duckdb)

library(zoo)

library(naniar)
library(mice)
library(marginaleffects)
library(car)
library(DescTools)

```

Зададим начальные переменные - выберем магазин c **store_id** = 5 по чаю. Обозначим путь датасета

```r
store_id <- 5
product_category <- "Tea"
csv_path_tea <- "../../data/lab-02/lab2_timeseries_coffee.csv"
csv_path_panel <- "../../data/lab-02/lab2_households.csv"
```

1 упражнение

1.1 пункт

Подключимся к .duckdb и перенесем туда .csv данные, чтобы в дальнейшем переложить расчет простых метрик на внутреннее исполнение. Скопируем туда абсолютно все данные

```r
con <- dbConnect(duckdb(), "analysis.duckdb")

raw_for_5_tea <- read.csv(csv_path_tea, stringsAsFactors = FALSE)
dbWriteTable(con, "raw_for_5_tea", raw_for_5_tea, overwrite = TRUE)

dbGetQuery(con, "SELECT COUNT(*) AS n_rows FROM raw_for_5_tea")
dbGetQuery(con, "SELECT * FROM raw_for_5_tea LIMIT 5")

dbDisconnect(con)
```

Подключимся к базе лишь единожды. Для удобства создадим таблицу, в которой будут находиться переменные с условием нужных **store_id** и product_category. Также создадим прокси-колонку для уникальных посетителей, опираясь на **transaction_id**

```r
con <- dbConnect(duckdb(), "analysis.duckdb")


# Создаем таблицу только для store_id = 5 и категории Tea
dbExecute(con, "
  CREATE OR REPLACE TABLE data_5_tea AS
  SELECT
    *,
    transaction_id AS customer_id_proxy
  FROM raw_for_5_tea
  WHERE store_id = 5
    AND product_category = 'Tea'
")

# Проверяем размер отфильтрованной выборки
dbGetQuery(con, "SELECT COUNT(*) AS n_rows FROM data_5_tea")

# Смотрим, что новая колонка создалась корректно
dbGetQuery(con, "SELECT transaction_id, customer_id_proxy FROM data_5_tea LIMIT 5")

```

Рассчитаем основные и синтетические метрики, выведем их

```r

task_daily <- "
SELECT
  transaction_date,
  COUNT(*) AS n_transactions,                      -- общее число транзакций за день
  SUM(total_bill) AS revenue,                      -- общая дневная выручка
  AVG(total_bill) AS avg_ticket,                   -- средний чек
  COUNT(DISTINCT customer_id_proxy) AS dau_approx, -- прокси DAU (который по сути есть число транзакций)
  AVG(rating) AS avg_rating,                       -- средний рейтинг
  AVG(is_app_order) AS app_order_share             -- доля заказов через приложение
FROM data_5_tea
GROUP BY transaction_date
ORDER BY transaction_date
"


# Выполняем запрос и сохраняем результат
daily_metrics <- dbGetQuery(con, task_daily)

# А теперь просматриваем заголовки
head(daily_metrics)

```

Теперь посмотрим, есть ли пропущенные данные по датам - подготавливаемся к анализу временных рядов.

```r

ts_query <- "
SELECT
  CAST(transaction_date AS DATE) AS date,           -- преобразуем в дату
  SUM(total_bill) AS revenue,                       -- в остальном все такое же, только группирровка
                                                    -- через ДАТУ а не через текстовый формат даты
  COUNT(*) AS n_transactions,   
  COUNT(DISTINCT customer_id_proxy) AS dau_approx,
  AVG(total_bill) AS avg_ticket,
  AVG(rating) AS avg_rating,
  AVG(is_app_order) AS app_order_share
FROM data_5_tea
GROUP BY CAST(transaction_date AS DATE)
ORDER BY date
"
#   Выполняем запрос
ts_5_tea <- dbGetQuery(con, ts_query)

# А теперь просматриваем заголовки
head(ts_5_tea)


# Проверяем, есть ли пропущенные даты - смотрим на последовательность по дням
date_seq <- seq(min(as.Date(ts_5_tea$date)), max(as.Date(ts_5_tea$date)), by = "day")
missing_dates <- setdiff(date_seq, as.Date(ts_5_tea$date))

length(missing_dates)
missing_dates
```

В данной базе данных отсутствуют пропуски в датах - тем не менее, в коде будет присутствовать блок, исправляющий потенциальные пропуски (ведь лид может вернуться еще со срочными запросами по другим периодам...)

```r

# При необходимости достраиваем полный календарь по дням. 
# В пропущенных днях на основные метрики ставим 0
ts_5_tea_complete <- ts_5_tea %>%
  mutate(date = as.Date(date)) %>%
  complete(
    date = seq(min(date), max(date), by = "day"),
    fill = list(
      revenue = 0,
      n_transactions = 0,
      dau_approx = 0
    )
  ) %>%
  arrange(date)

nrow(ts_5_tea_complete)


# Проверяем итоговый датасет после заполнения дат - 
# хотя ожидаем нулевые изменения из-за идеальности датасета
head(ts_5_tea_complete)
```

1.1 пункт

Нам необходимо проверить график временного ряда для **revenue** - необходимо преобразовать данные в формат zoo для дальнейшего анализа

```r

# Переводим revenue в формат zoo для анализа временного ряда
zoo_tea_revenue <- zoo(
  x = ts_5_tea_complete$revenue,
  order.by = as.Date(ts_5_tea_complete$date)
)

head(zoo_tea_revenue)

```

Визуализируем временной ряд для **revenue**

```r
# Строим график дневной выручки по магазину 5 и категории Tea
plot(
  zoo_tea_revenue ,
  main = "Daily revenue: store_id = 5, Tea",
  xlab = "Date",
  ylab = "Revenue",
  col = "black",
  lwd = 2,                   
)

```

Мы видим, что выручка растет. Но засчет чего? Построим два декомпозированных ряда STL: для 7 и 30 дневнего цикла - это позволит ответить нам на вопрос, какая сезонность наблюдается - недельная или 30-дневная

```r

# Переводим revenue в объект ts с недельной частотой
# frequency = 7 позволяет проверить гипотезу о недельной сезонности
ts_5_tea_revenue_7<- ts(
  ts_5_tea_complete$revenue,
  frequency = 7
)

# Выполняем STL-декомпозицию:
# выделяем тренд, сезонность и остаток
ts_5_tea_revenue_stl_7 <- stl(
  ts_5_tea_revenue_7,
  s.window = "periodic"
)

# Собираем компоненты декомпозиции в отдельный датафрейм
# Это нужно для последующей визуализации и расчета дисперсий
comp_frame_7 <- data.frame(
  date = ts_5_tea_complete$date,
  observed = as.numeric(ts_5_tea_revenue_7),
  trend = as.numeric(ts_5_tea_revenue_stl_7$time.series[, "trend"]),
  seasonal = as.numeric(ts_5_tea_revenue_stl_7$time.series[, "seasonal"]),
  remainder = as.numeric(ts_5_tea_revenue_stl_7$time.series[, "remainder"])
)

# Переводим данные в длинный формат и строим график всех компонент STL
comp_frame_7 %>%
  pivot_longer(
    cols = c(observed, trend, seasonal, remainder),
    names_to = "component",
    values_to = "value"
  ) %>%
  ggplot(aes(x = date, y = value, color = component)) +
  geom_line(linewidth = 0.7) +
  facet_wrap(~component, scales = "free_y", ncol = 1) +
  labs(
    title = "7 STL-декомпозиция revenue (cafe 5, Tea)",
    x = "Date",
    y = NULL
  ) +
  theme_minimal() +
  theme(
    legend.position = "none",
    panel.grid.minor = element_blank()
  ) +
  scale_color_manual(values = c(
    "observed" = "black",
    "trend" = "blue",
    "seasonal" = "darkgreen",
    "remainder" = "red"
  ))

# Общая дисперсия исходного ряда
var_total_7 <- var(comp_frame_7$observed, na.rm = TRUE)

# Дисперсия сезонности
var_seasonal_7 <- var(comp_frame_7$seasonal, na.rm = TRUE)

# Дисперсия остатков
var_remainder_7 <- var(comp_frame_7$remainder, na.rm = TRUE)

# Доля шума в общей дисперсии ряда, %
var_remainder_7 / var_total_7 * 100

# Доля сезонности в общей дисперсии ряда, %
var_seasonal_7 / var_total_7 * 100

```

На графике с 7-дневной сезонностью имеется видимый тренд - выручка растет (однако, есть некоторые колебания). Сезонность, конечно, моделью выделяется, но она объясняет меньше процента дисперции, поэтому будем считать, что ее нет. Что касается шума - то он объясняет 19,3% дисперсии, что куда больше чем сезонность и кратно меньше чем тренд.

```r

# Переводим revenue в объект ts с недельной частотой
# frequency = 30 позволяет проверить гипотезу о 30-дневной сезонности
ts_5_tea_revenue_30 <- ts(
  ts_5_tea_complete$revenue,
  frequency = 30
)

# Выполняем STL-декомпозицию:
# выделяем тренд, сезонную компоненту и остаток
ts_5_tea_revenue_stl_30 <- stl(
  ts_5_tea_revenue_30,
  s.window = "periodic"
)

# Собираем компоненты декомпозиции в отдельный датафрейм
# Это нужно для последующей визуализации и расчета дисперсий
comp_frame_30 <- data.frame(
  date = ts_5_tea_complete$date,
  observed = as.numeric(ts_5_tea_revenue_30),
  trend = as.numeric(ts_5_tea_revenue_stl_30$time.series[, "trend"]),
  seasonal = as.numeric(ts_5_tea_revenue_stl_30$time.series[, "seasonal"]),
  remainder = as.numeric(ts_5_tea_revenue_stl_30$time.series[, "remainder"])
)

# Переводим данные в длинный формат и строим график всех компонент STL
comp_frame_30 %>%
  pivot_longer(
    cols = c(observed, trend, seasonal, remainder),
    names_to = "component",
    values_to = "value"
  ) %>%
  ggplot(aes(x = date, y = value, color = component)) +
  geom_line(linewidth = 0.7) +
  facet_wrap(~component, scales = "free_y", ncol = 1) +
  labs(
    title = "30 STL-декомпозиция revenue (cafe 5, Tea)",
    x = "Date",
    y = NULL
  ) +
  theme_minimal() +
  theme(
    legend.position = "none",
    panel.grid.minor = element_blank()
  ) +
  scale_color_manual(values = c(
    "observed" = "black",
    "trend" = "blue",
    "seasonal" = "darkgreen",
    "remainder" = "red"
  ))

# Общая дисперсия исходного ряда
var_total_30 <- var(comp_frame_30$observed, na.rm = TRUE)

# Дисперсия сезонности
var_seasonal_30 <- var(comp_frame_30$seasonal, na.rm = TRUE)

# Дисперсия остатков
var_remainder_30 <- var(comp_frame_30$remainder, na.rm = TRUE)

# Доля шума в общей дисперсии ряда, %
var_remainder_30 / var_total_30 * 100

# Доля сезонности в общей дисперсии ряда, %
var_seasonal_30 / var_total_30 * 100

```

На графике с 30-дневной сезонностью имеется видимый тренд - выручка растет. Сезонность в этой модели куда более значимая - она объясняет 16,2%. Будем считать, что подобная сезонность присутствует Шумы имеют чуть большую долю объясненной дисперсии, чем сезонность - 16,4%. Стоит, однако держать в голове, что количество наблюдаемых периодов - 6 и о наличии сезонности подобного рода нельзя говорить уверенно.

1.2 пункт

Проведем тесты на стационарность - ADF, KPSS, PP

```r

# Проверяем стационарность исходного ряда тремя тестами:
# ADF и PP: H0 = ряд нестационарен
# KPSS: H0 = ряд стационарен
adf_res <- adf.test(zoo_tea_revenue)
kpss_res <- kpss.test(zoo_tea_revenue)
pp_res <- pp.test(zoo_tea_revenue)

adf_res
kpss_res
pp_res

# Собираем результаты в единую таблицу для удобного сравнения
stationarity_table <- tibble(
  test = c("ADF", "KPSS", "PP"),
  statistic = c(
    unname(adf_res$statistic),
    unname(kpss_res$statistic),
    unname(pp_res$statistic)
  ),
  p_value = c(
    adf_res$p.value,
    kpss_res$p.value,
    pp_res$p.value
  ),
  null_hypothesis = c(
    "Ряд нестационарен",
    "Ряд стационарен",
    "Ряд нестационарен"
  ),
  decision = c(
    ifelse(adf_res$p.value < 0.05, "H0 отвергается", "Нет оснований отвергнуть H0"),
    ifelse(kpss_res$p.value < 0.05, "H0 отвергается", "Нет оснований отвергнуть H0"),
    ifelse(pp_res$p.value < 0.05, "H0 отвергается", "Нет оснований отвергнуть H0")
  )
)

stationarity_table

```

Тесты показали неоднозначные результаты по стационарности поскольку ADF и PP показали стационарность, а KPSS - нет

Используем для ответа на вопрос еще один тест - посмотрим, разность какого порядка мы должны будем использовать для получения стационарного ряда - используем arima.auto()

```r

# Дополнительно подбираем показатели для ARIMA-модели 
fit_arima <- auto.arima(zoo_tea_revenue, 
                       seasonal = TRUE,
                       stepwise = FALSE,
                       approximation = FALSE)

fit_arima
```

Мы увидели, что нам нужно про дифференциировать ряд один раз, что указывает в комплексе указывает на нестационарность.

Продифференциируем один раз и проведем те же тесты

```r

zoo_tea_revenue_diff <- diff(zoo_tea_revenue)

adf_res <- adf.test(zoo_tea_revenue_diff)
kpss_res <- kpss.test(zoo_tea_revenue_diff)
pp_res <- pp.test(zoo_tea_revenue_diff)

adf_res
kpss_res
pp_res

stationarity_table <- tibble(
  test = c("ADF", "KPSS", "PP"),
  statistic = c(
    unname(adf_res$statistic),
    unname(kpss_res$statistic),
    unname(pp_res$statistic)
  ),
  p_value = c(
    adf_res$p.value,
    kpss_res$p.value,
    pp_res$p.value
  ),
  null_hypothesis = c(
    "Ряд нестационарен",
    "Ряд стационарен",
    "Ряд нестационарен"
  ),
  decision = c(
    ifelse(adf_res$p.value < 0.05, "H0 отвергается", "Нет оснований отвергнуть H0"),
    ifelse(kpss_res$p.value < 0.05, "H0 отвергается", "Нет оснований отвергнуть H0"),
    ifelse(pp_res$p.value < 0.05, "H0 отвергается", "Нет оснований отвергнуть H0")
  )
)

stationarity_table

fit_arima <- auto.arima(zoo_tea_revenue_diff, 
                       seasonal = TRUE,
                       stepwise = FALSE,
                       approximation = FALSE)

fit_arima

```

Мы видим, что по всем тестам нестационарность пропала (в т.ч. по параметрам ARIMA), тем не менее качество модели не улучшилось. Поэтому будем в дальнейшем использовать данные без первой разности

1.3 пункт

Рассмотрим влияние метрик на нашу выручку - для этого рассмотрим модель ARDL с порядком 3.

```r

# Подготавливаем данные для ARDL-модели:
# оставляем дату, зависимую переменную и выбранные предикторы 
ardl_data <- ts_5_tea_complete %>%
  select(date, revenue, dau_approx, avg_rating, app_order_share) %>%
  filter(
    !is.na(revenue),
    !is.na(dau_approx),
    !is.na(avg_rating),
    !is.na(app_order_share)
  )

# revenue — зависимая переменная
fit_ardl <- auto_ardl(
  revenue ~ dau_approx + avg_rating + app_order_share,
  data = ardl_data,
  max_order = 3
)

# Сохраняем остатки модели для диагностики
ardl_resid <- residuals(fit_ardl$best_model)

```

Модель построена (сводку выведем позже) - оценим ее качество

```r

# Проверяем автокорреляцию остатков визуально
acf(ardl_resid, main = "ACF of ARDL residuals")

# Проверяем остатки формальным тестом Ljung-Box
Box.test(
  ardl_resid,
  lag = 7,
  type = "Ljung-Box"
)

```

Согласно ACF мы можем наблюдать  автокорреляцию в остатках, согласно Box-Ljuing тесту в остатках мы также видим автокорреляцию, следовательно мы должны с большой осторожностью интерпретировать результаты.

```r

# Выводим подробную сводку по лучшей модели
summary(fit_ardl$best_model)

```

Коэффициент при ***L(revenue, 1)*** положительный и статистически значимый. Это значит, что выручка в магазине обладает инерцией: высокий результат предыдущего дня частично переносится на следующий день. Иначе говоря, если вчера продажи были выше обычного, то и сегодня выручка с большой вероятностью тоже будет выше среднего - спрос, таким образом, не обнуляется каждый день, а сохраняет краткосрочную устойчивость.

Коэффициент при ***L(avg_rating, 2)*** тоже положительный и значимый. Это можно интерпретировать так: более высокие оценки клиентов связаны с ростом выручки не сразу, а с задержкой примерно в два дня - качество сервиса и пользовательский опыт начинают отражаться в продажах не мгновенно, а спустя короткое время, то есть хорошие оценки могут быть сигналом того, что в ближайшие дни спрос окажется выше.

Тем не менее, несмотря на красочность выводы нужно использовать ОЧЕНЬ осторожно.

1.4 пункт

Теперь проверим влияние некоего фактора на динамику спроса В нашем случае мы рассмотрим то, какое влияние оказал (оказал ли вообще?) влияние на **dau_approx**

```r
# Задаем дату начала погодного шока
intervention_date <- as.Date("2023-05-25")

# Формируем периоды до и после вмешательства, запишем две переменных
# весь ряд до шока и интервал погодного шока 25.05–27.05
pre_period <- c(min(ts_5_tea_complete$date), intervention_date - 1)
post_period <- c(intervention_date, as.Date("2023-05-27"))

impact_data <- cbind(dau_approx = ts_5_tea_complete$dau_approx)
impact_xts <- zoo(impact_data, order.by = ts_5_tea_complete$date)

impact <- CausalImpact(impact_xts, pre_period, post_period)

summary(impact)

# Визуализируем фактический и контрфактический ряды
plot(impact)

```

Абсолютный эффект погодного шока на показатель dau_approx составил +18 в среднем за день.

Эффект является статистически значимым, p<0.05

Сам вывод такой - результат показывает, что в период погодного шока клиентская активность в точке увеличилась примерно на 19%. Неблагоприятные погодные условия могли стимулировать спрос покупателей на горячие напитки, в том числе на чай - возможно, стоит устраивать какие-то промо в дни со сходными погодными условиями

```r

# Закрываем подключение
dbDisconnect(con)

```

2 Упражнение

Приступим к очень срочному (и своевременному) субботнему запросу от лида. Загрузим данные в .duckdb формат

```r

con <- dbConnect(duckdb(), "panel.duckdb")

panel_raw <- read.csv(csv_path_panel, stringsAsFactors = FALSE)
dbWriteTable(con, "panel_data", panel_raw, overwrite = TRUE)

dbGetQuery(con, "SELECT COUNT(*) AS n_rows FROM panel_data")
dbGetQuery(con, "SELECT * FROM panel_data LIMIT 5")

dbDisconnect(con)

```

Мы видим здесь, что база данных включает в себя данные с 1994 по 2024 год. Схлопнем датасет в двух измерениях (ограничим как установленным временем с 2010 по 2023, так и переменными) и создадим таблицу, в которой будут находиться релевантные по времени наблюдения, а также переменные, которые потенциально будут использоваться в анализе - поскольку анализируются ДХ, то и переменные должны относиться именно к домохозяйства. Подключимся к нашей таблице один раз.

```r

con <- dbConnect(duckdb(), "panel.duckdb")

# Создаем рабочую таблицу:
# оставляем нужный период и нужные переменные
panel_years_query <- "
CREATE OR REPLACE TABLE panel_data_years AS
SELECT
    id_h,             -- id домохозяйства
    id_w,             -- id волны

    e1_48a,           -- покупка чая за 7 дней
    
    e1_49a,           -- покупка кофе за 7 дней
    f14,              -- доход семьи
    nfm,              -- размер домохозяйства
    c1,               -- тип жилья
    c9_624a,          -- высокоскоростной интернет
    panelids          -- ключ дх*волна
FROM panel_data
WHERE id_w BETWEEN 19 AND 32      -- от 2010 до 2023 включительно
"

dbExecute(con, panel_years_query)

panel_to_relevant <- dbGetQuery(con, "SELECT * FROM panel_data_years")

head(panel_to_relevant, 10)

dbDisconnect(con)

```

Данные загружены. Посмотрим теперь на целостность данных.

```r

panel_check <- panel_to_relevant %>%
  group_by(id_h) %>%
  summarise(
    n_waves = n_distinct(id_w),   # в скольких волнах участвовало домохозяйство
    first_wave = min(id_w, na.rm = TRUE),
    last_wave = max(id_w, na.rm = TRUE),
    n_obs = n(),
)

head(panel_check, 10)

```

Число наблюдений **n_obs** всегда будет делиться на **n_waves** без остатка - частным будет число членов ДХ. Отфильтруем теперь базу данных так, чтобы оставить только домохозяйства участвовавшие более чем в 90% волн (получается больше 12 волн). Но нам нужно анализировать домохозяйства - следовательно, нужно агрегировать данные так, чтобы одно наблюдение в базе было равно одному ДХ. Это можно сделать следующим образом - возьмем только "уникальные" строки, а keep_all позволит забрать всю строку из датафрейма.

```r

panel_collapsed <- panel_to_relevant %>%
  distinct(
    id_h, id_w,
    .keep_all = TRUE
  )

panel_check <- panel_collapsed %>%
  group_by(id_h) %>%
  summarise(
    n_waves = n_distinct(id_w),   # в скольких волнах участвовало домохозяйство
    first_wave = min(id_w, na.rm = TRUE),
    last_wave = max(id_w, na.rm = TRUE),
    n_obs = n()
)

head(panel_check, 10)
head(panel_collapsed, 10)
```

Теперь можно и отфильтровать по участию в >12 волнах. Для этого, нужно забрать значения из **panel_check** и заджойнить по **id_h** с нашей базой данных **panel_collapsed**.

```r

panel_final <- panel_collapsed %>% 
  inner_join(panel_check %>% filter(n_waves > 12), by = "id_h")

panel_final %>% 
  head(10)

panel_final %>%
  summarise(
    n_rows = n(),
    n_households = n_distinct(id_h)
  )
```

Данные готовы, очищены. Приступаем к задаче

2.1 Пункт

В этом пункты мы должны были построить последовательность данных, но процессе выполнения код ложился от ошибки "Ошибка: [!] state(s) 2,99999999 found in 'data' should be in 'alphabet'", поэтому сначала перекодирую все используемые переменные, потому что к тому же все они будут использоваться в регрессии.

```r
panel_final_recoded <- panel_final %>%
  mutate(
    
    e1_48a = case_when(
      e1_48a == 1 ~ 1, # покупал чай
      e1_48a == 2 ~ 0, # не покупал чай
      e1_48a %in% c(99999997, 99999998, 99999999) ~ NA_real_,
      TRUE ~ NA_real_
    ),
    
    e1_49a = case_when(
      e1_49a == 1 ~ 1, # покупал кофе
      e1_49a == 2 ~ 0, # не покупал кофе
      e1_49a %in% c(99999997, 99999998, 99999999) ~ NA_real_,
      TRUE ~ NA_real_
    ),
    
    f14 = case_when(
      f14 %in% c(99999997, 99999998, 99999999) ~ NA_real_,
      TRUE ~ as.numeric(f14) # доходы ДХ
    ),
    
    nfm = case_when(
      nfm %in% c(99999997, 99999998, 99999999) ~ NA_real_,
      TRUE ~ as.numeric(nfm) # размер дх
    ),
    
    c1 = case_when(
      c1 %in% c(1, 2, 3) ~ as.numeric(c1),
      c1 %in% c(99999997, 99999998, 99999999) ~ NA_real_,
      TRUE ~ NA_real_
    ) %>% factor(levels = c("1", "2", "3"), labels = c("Свое жилье", "Снимаю", "Общежитие")
    ),
    
    c9_624a = case_when(
      c9_624a == 1 ~ 1, # есть высокоскоростной интернет
      c9_624a == 2 ~ 0,
      c9_624a %in% c(99999997, 99999998, 99999999) ~ NA_real_,
      TRUE ~ NA_real_
    ),
    
    c1_owner = case_when(
      c1 == "Свое жилье" ~ 1, 
      c1 %in% c("Снимаю", "Общежитие") ~ 0, # 1659+679 наблюдений в группе чуть
                                            # лучше чем по отдельности
      TRUE ~ NA_real_
  )
)

panel_final_recoded %>%
  count(e1_48a, sort = TRUE)

panel_final_recoded %>%
  count(e1_49a, sort = TRUE)

panel_final_recoded %>%
  count(c1, sort = TRUE)

panel_final_recoded %>%
  count(c9_624a, sort = TRUE)

panel_final_recoded %>%
  count(c1_owner, sort = TRUE)

panel_final_recoded %>%
  summarise(
    min_f14 = min(f14, na.rm = TRUE),
    max_f14 = max(f14, na.rm = TRUE),
    min_nfm = min(nfm, na.rm = TRUE),
    max_nfm = max(nfm, na.rm = TRUE)
  )
```

2.1.1 подпункт

Переменные правильно перекодированы. Теперь можно точно приступать к дальнейшему анализу. Построим последовательность данных

```r
# Оставляем только id домохозяйства, номер волны и переменную покупки чая
seq_data <- panel_final_recoded %>%
  select(id_h, id_w, e1_48a)

seq_data <- seq_data %>%
  mutate(
    e1_48a = as.character(e1_48a)
  )

seq_wide <- seq_data %>%
  pivot_wider(
    names_from = id_w,
    values_from = e1_48a,
    names_prefix = "wave_"
  ) %>%
  arrange(id_h)


tea_seq <- seqdef(
  seq_wide[, -1],
  id = seq_wide$id_h,
  alphabet = c("0", "1"),
  states = c("0", "1"),
  labels = c("Не покупали чай", "Покупали чай")
)

# Смотрим краткую сводку по объекту последовательностей
summary(tea_seq)
```

2.1.2 подпункт

Ряд последовательностей создан. Некоторые домохозяйства не участвовали в некоторых волнах опроса, однако это у нас отмечено и процент пропусков некритический (13/14 - чуть больше 90%). Построим теперь для покупателей

```r
seqIplot(
  tea_seq,
  sortv = "from.end",
  with.legend = TRUE,
  main = "Траектории покупки чая по волнам"
)

seqiplot(
  tea_seq,
  with.legend = TRUE,
  main = "Траектории покупки чая по волнам"
)

seqdplot(
  tea_seq,
  with.legend = TRUE,
  main = "Распределение доли ДХ купивших чай по волнам"
)

```

Создадим seq*plot'ы для функциональных групп. Рассмотрим на примере доходных групп

```r

# Создадим доходную группу - заберем медиану по всем дх, потом создадим
# переменную с 4квартилями
income_group <- panel_final_recoded %>%
  group_by(id_h) %>%
  summarise(
    f14_median = median(f14, na.rm = TRUE)
  ) %>%
  mutate(
    income_quartile = ntile(f14_median, 4),
    income_quartile = factor(
      income_quartile,
      levels = c(1, 2, 3, 4),
      labels = c("1 квартиль", "2 квартиль", "3 квартиль", "4 квартиль")
    )
)

# приджойним к wide формату данных
seq_wide_group <- seq_wide %>%
  left_join(income_group %>% select(id_h, income_quartile), by = "id_h")

# объект последовательностей
tea_seq_group <- seqdef(
  seq_wide_group %>% select(starts_with("wave_")),
  id = seq_wide_group$id_h,
  alphabet = c("0", "1"),
  states = c("0", "1"),
  labels = c("Не покупали чай", "Покупали чай")
)

# группирующая переменная
group_income <- seq_wide_group$income_quartile

```

Построим сами графики анализа последовательностей
```r

seqIplot(
  tea_seq_group,
  group = group_income,
  border = NA,
  with.legend = TRUE,
  main = "По квартилям дохода"
)

seqiplot(
  tea_seq_group,
  group = group_income,
  border = NA,
  with.legend = TRUE,
  main = "По квартилям дохода"
)

seqdplot(
  tea_seq_group,
  group = group_income,
  with.legend = TRUE,
  main = "По квартилям дохода"
)
```

2.1.3 подпункт

а) Доля ДХ не покупающих чай постепенно растет. Для дохода наблюдается похожая картина - есть небольшие визуальные различия в том, что представители первого квартиля по доходам немного реже, чем другие группы. 

б) Заметны несколько паттернов повеения: ДХ либо стабильно не покупает чай в большинстве волн, либо переключается между покупкой и непокупкой, а устойчивый паттерн регулярной покупки чая во всех волнах встречается, но выглядит менее массовым, чем паттерн непокупки.

в) В разрезе доходных квартилей немного заметно, что более обеспеченные домохозяйства реже покупают чай, но не то что бы различия сильные. Это точно не нормальный товар (поскольку как минимум частота покупки не увеличивается), но и нельзя говорить пока, что она уменьшаяется.

2.2 пункт 

Для регрессии во избежание неудобной интерпретации создадим переменную дохода/10000.

```r

panel_final_recoded <- panel_final_recoded %>%
  mutate(
    f14_10k = f14 / 10000
  )

```

Создадим датасет для регрессий

```r

regression_data <- panel_final_recoded %>%
  select(
    id_h, 
    id_w,
    e1_48a,
    e1_49a,
    f14_10k,
    nfm,
    c1_owner,
    c9_624a,
    panelids
  )
head(regression_data)
```

Посмотрим на долю пропусков

```r
missing_summary <- regression_data %>%
  summarise(
    across(
      .cols = everything(),
      .fns = ~ sum(is.na(.))
    )
  )

missing_summary

miss_table <- missing_summary %>%
  pivot_longer(
    cols = everything(),
    names_to = "variable",
    values_to = "n_missing"
  ) %>%
  mutate(
    pct_missing = round(n_missing / nrow(regression_data) * 100, 2)
  )

miss_table
```

Посмотрим как миссинги разделялись по волнам

```r
miss_by_wave <- regression_data %>%
  group_by(id_w) %>%
  summarise(
    e1_48a = mean(is.na(e1_48a)) * 100,
    e1_49a = mean(is.na(e1_49a)) * 100,
    f14_10k = mean(is.na(f14_10k)) * 100,
    nfm = mean(is.na(nfm)) * 100,
    c1_owner = mean(is.na(c1_owner)) * 100,
    c9_624a = mean(is.na(c9_624a)) * 100
  )

miss_by_wave
```

Самое большое число пропусков, закономерно присутствует в переменной дохода. Тем не менее, представляется, что это не является критическим значением для listwise deletion. Согласно рекомендациям из лекций будем работать с complete cases базой.

```r
vars_for_gee <- c("id_h", "id_w", "e1_48a", "e1_49a",
                  "f14_10k", "nfm", "c1_owner", "c9_624a")

vars_for_logit <- c("id_h", "id_w", "e1_48a", "e1_49a",
                  "f14_10k", "nfm", "c1_owner", "c9_624a")

gee_data <- regression_data %>%
  filter(complete.cases(select(., all_of(vars_for_gee)))) %>%
  arrange(id_h, id_w) # видел, что вроде отсортированно, но все же

logit_data <- regression_data %>%
  filter(complete.cases(select(., all_of(vars_for_logit)))) %>%
  arrange(id_h, id_w)

```

Пропуски очищены - строим модели.

2.2.1 подпункт

Для начала потроим бинарную логистическую регрессию (зависимая переменная 0/1). Правильнее, конечно, было бы использовать переменную времени (factor(id_w)), но поскольку в тз сказано использовать не более 4-7 переменных (а при выводе id_w дадут дополнительно 13 сравниваемых предикторов), то от их включения в модель откажусь. В то же время в тз также указан контроль id_w и id_h. В данном задании будет построена логистическая модель без учета панельной составляющей и времени-представим, что все наблюдения будут не связаны друг с другом.

```r

logit_model <- glm(
  e1_48a ~ e1_49a + f14_10k + nfm + c1_owner + c9_624a,
  data = logit_data,
  family = binomial(link = "logit")
)

vif_logit <- vif(logit_model) # посмотрим на мультиколлинеарность

summary(logit_model)
vif_logit

```

2.2.2 подпункт

Теперь выведем маржинальные эффекты

```r
ame_logit <- avg_slopes(logit_model)
ame_logit
```

2.2.3 подпункт

а) В базовой logit-модели статистически значимы все включенные предикторы:

**e1_49a** - покупка кофе, положительный эффект 
**f14_10k** - доход, отрицательный эффект
**nfm** - размер домохозяйства, положительный эффект 
**c1_owner** - жилье в собственности, отрицательный эффект 
**c9_624a** - высокоскоростной интернет, отрицательный эффект

б) Если интерпретировать по AME, то увеличение дохода на 1 единицу переменной f14_10k, то есть на 10 000 рублей в исходной шкале, связано со снижением вероятности покупки чая в среднем на 0.53 процентного пункта, при прочих равных

в) Нет, не согласуется, потому что для нормального товара ожидался бы положительный эффект дохода

2.3 пункт

2.3.1 подпункт

Теперь мы выберем GEE-GLM модель панельной регрессии - ее выбор будет обоснован тем, что мы хотим посмотреть на средний эффект популяции - как менялся факт покупки чая в среднем во времени. К тому же GEE-GLM более робастна, поэтому остановимся на ней.

Будем использовать корреляционную структуру AR1, подходящую под ежегодное периодичное обследование. Сравнение QIC показало, что вариант структуры exchangeable лучше (QIC меньше (чанки удалили)).

Также построим только без учета времени

```r
gee_model <- geeglm(
  e1_48a ~ e1_49a + f14_10k + nfm + c1_owner + c9_624a,
  id = id_h,
  waves = id_w,
  data = gee_data,
  family = binomial(link = "logit"),
  corstr = "exchangeable"
)

summary(gee_model)
QIC(gee_model)
```

2.3.2 подпункт

Все переменные значимы, но интерпретировать мы будем именно маржинальные эффекты

```r
marginaleffects::avg_slopes(gee_model)
```

Средние маржинальные эффекты GEE-модели показывают, что покупка кофе статистически значимо и положительно связана с покупкой чая: при покупке кофе вероятность покупки чая выше в среднем на 13 пп. Размер домохозяйства также положительно влияет на вероятность покупки чая: увеличение числа членов домохозяйства на 1 человека повышает ее примерно на 2.7 пп. В то же время доход, наличие собственного жилья и высокоскоростного интернета связаны с более низкой вероятностью покупки чая. Наиболее сильный отрицательный эффект среди этих переменных наблюдается у признака собственного жилья: он снижает вероятность покупки чая примерно на 5.5 пп

2.3.3 подпункт

Направления эффектов полностью совпадают: покупка кофе и размер домохозяйства положительно связаны с вероятностью покупки чая, тогда как доход, наличие собственного жилья и высокоскоростного интернета связаны с ее снижением. При этом в GEE-модели, учитывающей панельную структуру данных, почти все эффекты оказываются слабее по модулю, чем в базовом logit. Также, все предикторы остаются статистически значимыми.


2.4 Упражнение

а) Судя по результатам модели, чай является более вероятной покупкой для крупных домохозяйств и для тех домохозяйств, которые уже покупают кофе. Напротив, у более обеспеченных домохозяйств вероятность покупки чая ниже. Значит, в данной спецификации чай выглядит более приоритетным для массовых домохозяйств со средним или более нзким уровнем дохода и с уже сформированной привычкой покупать горячие напитки.

б) Здесь, само собой, напрашивается паттерн потребления горячих напитков в целом (кофе и чая). Поэтому эффективными могут быть наборы чай + кофе, семейные предложения, акции на вторую позицию в заказе и простые ценовые стимулы. С учетом отрицательного эффекта высокоскоростного интернета ставка только на цифровое продвижение выглядит менее убедительно, чем сочетание офлайн-акций, заметной выкладки и промо в точке продаж - не помешает развитие омниканальности.

в) По первой части мы поняли (на сомнительных выводах из-за автокорреляции остатков), что продажи чая зависят от инерции спроса и от клиентского опыта: высокая выручка прошлого дня частично переносится на следующий день, а улучшение оценок клиентов дает положительный эффект с лагом. Панельная модель показывает, кто именно формирует этот спрос: прежде всего более крупные домохозяйства и те, кто уже покупает кофе. В сумме это означает, что для чая важны не только краткосрочные колебания спроса, но и устойчивые потребительские паттерны, которые можно усиливать через кросс-продажи и семейные форматы.
Также было подтверждено предположение, что частота покупок будет скорее зависеть от дохода в обратную сторону (первый квартиль по доходу оказывался чуть менее чаще покупающим чай на глаз).
