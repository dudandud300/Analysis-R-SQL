# Зависимости

Список составлен по `library()` и обращениям `package::function` в исходниках. Версии пакетов в исходных архивах не зафиксированы.

| Работа | Пакеты |
| --- | --- |
| 1 | DBI, duckdb |
| 2 | tidyverse, lubridate, forecast, tseries, ARDL, CausalImpact, TraMineR, geepack, plm, DBI, duckdb, zoo, naniar, mice, marginaleffects, car, DescTools, knitr |
| 3 | tidyverse, lubridate, FactoMineR, factoextra, cluster, randomForest, xgboost, lightgbm, shapviz, caret, pROC, car, knitr, rpart, rpart.plot, catboost, GGally, corrplot, skimr, tibble |
| 4 | tidyverse, lubridate, plm, geepack, survival, pwr, zoo, marginaleffects, survminer, scales |


Для сборки отчётов дополнительно требуется `rmarkdown` и Pandoc. Для PDF работы 2 нужны XeLaTeX и шрифты, перечисленные в YAML-заголовке исходника.

