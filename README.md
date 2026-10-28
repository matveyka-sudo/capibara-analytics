# Capibara Analytics

Аналитическая база маркетплейса на PostgreSQL: модель core v2.1 и пять SQL-отчётов
по продажам, продавцам, среднему чеку, повторным заказам и категориям.
Данные — [Olist](https://github.com/olist/work-at-olist-data).

Нужны Docker и Python 3.10+. Команды выполняются из корня проекта.

## Запуск

Если raw уже загружен:

```bash
docker compose up -d postgres
python3 model/run.py --check
```

Только для первой установки на новой базе:

```bash
bash scripts/setup.sh
python3 model/run.py --check
```

`setup.sh` перезагружает raw; для обычного запуска он не нужен.
`--check` сверяет контрольные значения Olist; без флага выполняются обычные проверки.
Для вывода всех строк добавьте `--details`.

Результаты: `model/results/*.csv`, отчёт проверки: `model/results/validation.txt`.
По умолчанию используется контейнер `hack_postgres`; другой задаётся переменной
`ANALYTICS_PSQL_CONTAINER`. Для локального psql задайте её пустой и используйте переменные libpq.

[Модель и решения](docs/model.md) · [Задание](docs/handout.md) · [Вопросы](docs/tasks.md)
