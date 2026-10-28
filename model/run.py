#!/usr/bin/env python3
"""Build Capibara core v3.1, check it, and print ten concise answers."""

import argparse
import csv
import io
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

MODEL = Path(__file__).resolve().parent
ANSWER_REGISTRY = (
    ('1', '01_monthly_sales'),
    ('2', '02_top_sellers'),
    ('3', '03_average_order_value'),
    ('4', '04_repeat_buyers'),
    ('5', '05_category_revenue'),
    ('6', '06_product_price_history'),
    ('7', '07_delivery_by_state'),
    ('8', '08_order_statuses'),
    ('9a', '09a_payments_by_state_2018'),
    ('9b', '09b_payments_by_type'),
    ('10', '10_delivery_by_review_score'),
)
ANSWERS = tuple(name for _, name in ANSWER_REGISTRY)


def read_sql(name):
    return (MODEL / name).read_text(encoding='utf-8').strip().removesuffix(';')


def export(name, query):
    return (f'\n\\echo __CAPIBARA_BEGIN_{name}\n'
            f'COPY ({query}) TO STDOUT WITH (FORMAT csv, HEADER true);\n'
            f'\\echo __CAPIBARA_END_{name}\n')


def build_sql(check=False):
    sql = f'\\set reviewed_snapshot {"true" if check else "false"}\n'
    for name in ('schema.sql', 'load.sql', 'marts.sql'):
        sql += '\n' + (MODEL / name).read_text(encoding='utf-8')
    for number, name in ANSWER_REGISTRY:
        sql += f'\nCREATE TEMP VIEW answer_{number} AS {read_sql(f"answers/{name}.sql")};\n'
    sql += '\n' + (MODEL / 'checks.sql').read_text(encoding='utf-8')
    for number, name in ANSWER_REGISTRY:
        sql += export(name, f'SELECT * FROM answer_{number}')
    sql += export('summary', read_sql('summary.sql'))
    return sql + '\nCOMMIT;\n'


def execute(sql):
    container = os.environ.get('ANALYTICS_PSQL_CONTAINER', 'hack_postgres')
    options = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1']
    env = os.environ.copy()
    database = env.get('ANALYTICS_DATABASE')
    if container:
        command = ['docker', 'exec', '-i']
        if database:
            command += ['-e', f'PGDATABASE={database}']
        command += [container, 'sh', '-c',
                    'exec psql -U "$POSTGRES_USER" -d "${PGDATABASE:-$POSTGRES_DB}" "$@"',
                    'psql', *options]
    else:
        command = ['psql', *options]
        if database:
            env['PGDATABASE'] = database
    result = subprocess.run(command, input=sql, text=True, capture_output=True, env=env)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() + '\nСборка не завершена; CSV не обновлены.')
    return result.stdout


def parse_exports(output):
    exports = {}
    for name in (*ANSWERS, 'summary', 'report'):
        pattern = rf'^__CAPIBARA_BEGIN_{name}\n(.*?)^__CAPIBARA_END_{name}\n'
        matches = re.findall(pattern, output, flags=re.M | re.S)
        if len(matches) != 1:
            raise RuntimeError(f'Нет корректного SQL-результата: {name}')
        rows = list(csv.reader(io.StringIO(matches[0]), strict=True))
        if not rows or not rows[0] or any(len(row) != len(rows[0]) for row in rows[1:]):
            raise RuntimeError(f'Некорректный CSV: {name}')
        exports[name] = matches[0]
    return exports


def validation_text(report, summary, check):
    lines = ['Capibara core v3.1 — успешная сборка',
             f'Время UTC: {datetime.now(timezone.utc).isoformat()}',
             f'Сервер: {report["database_version"]}',
             'Проверки типов, ключей, связей и сохранности строк/сумм: OK',
             f'Исторические контрольные значения Olist: {"OK" if check else "не запрашивались"}',
             '', *summary, '', 'Строки и отпечатки таблиц (включая source metadata):']
    for table in report['snapshot']:
        lines.append(f'{table["layer"]}.{table["name"]}: {table["rows"]}; {table["fingerprint"]}')
    lines += ['', 'Аномалии источника (сохранены без исправлений):']
    lines += [f'{key}: {value}' for key, value in report['warnings'].items()]
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description='Собрать core v3.1, проверить данные и вывести десять ответов.')
    parser.add_argument('--check', action='store_true', help='Сверить контрольные значения снимка Olist')
    parser.add_argument('--details', action='store_true', help='Дополнительно показать все строки одиннадцати отчётов')
    args = parser.parse_args()
    print('Собираю модель и проверяю данные PostgreSQL...', flush=True)
    exports = parse_exports(execute(build_sql(args.check)))
    report = json.loads(next(csv.DictReader(io.StringIO(exports['report'])))['report'])
    summary = [row['answer'] for row in csv.DictReader(io.StringIO(exports['summary']))]
    results = MODEL / 'results'
    results.mkdir(exist_ok=True)
    # Publish only after PostgreSQL COMMIT; leave the last successful files on failure.
    with tempfile.TemporaryDirectory(prefix='.results-', dir=MODEL) as temporary:
        stage = Path(temporary)
        for name in ANSWERS:
            (stage / f'{name}.csv').write_text(exports[name], encoding='utf-8')
        (stage / 'validation.txt').write_text(validation_text(report, summary, args.check), encoding='utf-8')
        for name in [*(f'{name}.csv' for name in ANSWERS), 'validation.txt']:
            os.replace(stage / name, results / name)
    print('\n' + '\n'.join(summary))
    if args.details:
        for name in ANSWERS:
            print(f'\n{name}:')
            for row in csv.DictReader(io.StringIO(exports[name])):
                print('  ' + '; '.join(f'{key}: {value}' for key, value in row.items()))
    print(f'\nПолные ответы и отчёт: {results}')
    print('Аномалии источника сохранены и перечислены в validation.txt.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError) as error:
        sys.exit(str(error))
