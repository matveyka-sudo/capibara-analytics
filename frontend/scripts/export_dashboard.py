#!/usr/bin/env python3
"""Read-only export from published core; alternatively package saved SQL answers."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from uuid import UUID
from datetime import datetime, timezone
from decimal import Decimal

FRONTEND = Path(__file__).resolve().parents[1]
RESULTS = FRONTEND.parent / 'model' / 'results'


def cents(value):
    amount = Decimal(value) * 100
    if amount != amount.to_integral_value() or amount < 0 or amount > 9007199254740991:
        raise ValueError('Сумма не представима безопасными целыми сотыми.')
    return int(amount)


def reports():
    def rows(name):
        with (RESULTS / name).open(encoding='utf-8', newline='') as f:
            return list(csv.DictReader(f))
    monthly = rows('01_monthly_sales.csv')
    sellers = rows('02_top_sellers.csv')
    avg = rows('03_average_order_value.csv')[0]
    buyers = rows('04_repeat_buyers.csv')[0]
    categories = rows('05_category_revenue.csv')
    report = (RESULTS / 'validation.txt').read_text(encoding='utf-8')
    timestamp = next(line.split(': ', 1)[1] for line in report.splitlines() if line.startswith('Время UTC: '))
    digest = hashlib.sha256(b''.join(p.read_bytes() for p in sorted(RESULTS.glob('*.csv')))).hexdigest()[:20]
    additional = {}
    for number in range(6, 11):
        matches = sorted(RESULTS.glob(f'{number:02d}_*.csv'))
        if number != 9 and len(matches) > 1:
            raise ValueError(f'У отчёта {number} несколько CSV: выберите один итоговый файл.')
        for path in matches:
            with path.open(encoding='utf-8-sig', newline='') as f:
                table = list(csv.reader(f))
            if not table or not table[0] or any(len(row) != len(table[0]) for row in table[1:]):
                raise ValueError(f'Некорректный CSV отчёта {number}.')
            key = str(number)
            if number == 9:
                key = '9_methods' if 'payment_type' in table[0] or 'method' in path.stem else '9_states'
            if key in additional:
                raise ValueError(f'Несколько CSV для среза {key}.')
            additional[key] = {'columns': table[0], 'rows': table[1:], 'source': path.name}
    return {
        'mode': 'reports',
        'meta': {'schema_version': 1, 'snapshot_id': f'sql-reports-{digest}',
                 'exported_at': timestamp, 'source_label': 'Olist · сохранённые SQL-отчёты Capibara',
                 # Exact raw boundaries are not recoverable from five aggregates.
                 'source_purchase_date_min': None, 'source_purchase_date_max': None,
                 'currency_code': 'BRL'},
        'reports': {
            'additional': additional,
            'monthly': [{'month': r['month'][:7], 'orders': int(r['order_count']), 'revenue': cents(r['revenue'])} for r in monthly],
            'sellers': [{'seller_id': str(UUID(r['seller_id'])), 'city': r['seller_city'] or None, 'state': r['seller_state'] or None,
                         'orders': int(r['order_count']), 'units': int(r['item_unit_count']), 'revenue': cents(r['revenue'])} for r in sellers],
            'average': {'orders': int(avg['order_count']), 'revenue': cents(avg['item_revenue']),
                        'freight': cents(avg['freight_value']), 'units': int(avg['item_unit_count'])},
            'buyers': {'total': int(buyers['customer_count']), 'repeat': int(buyers['repeat_customer_count'])},
            'categories': [{'category_id': r['category_code'], 'category_code': r['category_code'],
                            'category_name_en': r['category_name_english'] or None,
                            'category_label': ('Неизвестная категория' if r['category_code'] == 'category:unknown' else r['category_label']),
                            'revenue': cents(r['revenue'])} for r in categories],
        },
    }


SQL = """
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL datestyle = 'ISO, YMD';
SET LOCAL timezone = 'UTC';
SELECT jsonb_build_object(
 'meta', jsonb_build_object('schema_version',1,'snapshot_id','pending',
   'exported_at',current_timestamp,'source_label','Olist · опубликованная модель Capibara',
   'source_purchase_date_min',(SELECT min(purchased_at)::date FROM core.orders),
   'source_purchase_date_max',(SELECT max(purchased_at)::date FROM core.orders),'currency_code','BRL',
   'record_counts',jsonb_build_object('orders',(SELECT count(*) FROM core.orders),
     'items',(SELECT count(*) FROM core.order_item),'sellers',(SELECT count(*) FROM core.seller),
     'categories',(SELECT count(*) FROM core.category))),
 'orders',coalesce((SELECT jsonb_agg(jsonb_build_object('order_id',o.order_id,'buyer_id',c.buyer_id,
   'status',o.status,'purchased_at',o.purchased_at) ORDER BY o.order_id)
   FROM core.orders o JOIN core.customer_snapshot c USING(customer_id)),'[]'::jsonb),
 'items',coalesce((SELECT jsonb_agg(jsonb_build_object('order_item_id',i.order_item_id,'order_id',i.order_id,
   'seller_id',i.seller_id,'category_id',p.category_id,'price_cents',i.price*100,
   'freight_cents',i.freight_value*100) ORDER BY i.order_item_id)
   FROM core.order_item i JOIN core.product p USING(product_id)),'[]'::jsonb),
 'sellers',coalesce((SELECT jsonb_agg(jsonb_build_object('seller_id',seller_id,'city',city,'state',state)
   ORDER BY seller_id) FROM core.seller),'[]'::jsonb),
 'categories',coalesce((SELECT jsonb_agg(jsonb_build_object('category_id',category_id,
   'category_code',coalesce(category_name_pt,'category:unknown'),'category_name_en',category_name_en,
   'category_label',coalesce(category_name_en,category_name_pt,'Неизвестная категория')) ORDER BY category_id)
   FROM core.category),'[]'::jsonb));
COMMIT;
"""


def detailed(container):
    options = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1']
    if container:
        command = ['docker', 'exec', '-i', container, 'sh', '-c',
                   'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"', 'psql', *options]
    else:
        command = ['psql', *options]  # PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSFILE.
    result = subprocess.run(command, input=SQL, text=True, capture_output=True, timeout=180)
    if result.returncode:
        raise RuntimeError('Не удалось прочитать опубликованную модель. Проверьте доступ к PostgreSQL; предыдущая выгрузка сохранена.')
    data = json.loads(result.stdout, parse_float=Decimal)
    for item in data['items']:
        for k in ('price_cents', 'freight_cents'):
            amount = Decimal(item[k])
            if amount != amount.to_integral_value() or not 0 <= amount <= 9007199254740991:
                raise ValueError('Некорректная денежная сумма в опубликованном снимке.')
            item[k] = int(amount)
    fingerprint = hashlib.sha256(json.dumps({k: data[k] for k in ('orders', 'items', 'sellers', 'categories')}, sort_keys=True).encode()).hexdigest()[:20]
    data['meta']['snapshot_id'] = f'core-{fingerprint}'
    if not data['orders']:
        raise ValueError('Модель пуста: определите границы снимка перед публикацией выгрузки.')
    return data


def main():
    parser = argparse.ArgumentParser(description='Выгрузка данных Capibara без изменения базы.')
    parser.add_argument('--results-only', action='store_true', help='Упаковать существующие пять CSV, без PostgreSQL и Docker')
    parser.add_argument('--container', help='Необязательно: читать через psql указанного уже запущенного контейнера')
    args = parser.parse_args()
    data = reports() if args.results_only else detailed(args.container)
    path = FRONTEND / 'public' / 'data' / ('reports.json' if args.results_only else 'dashboard.json')
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
        temporary = f.name
    os.replace(temporary, path)
    # Publish the pointer only after the complete file is safely in place.
    manifest = path.parent / 'index.json'
    with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as f:
        json.dump({'file': path.name}, f)
        pointer = f.name
    os.replace(pointer, manifest)
    print(f'Сохранено: {path} ({path.stat().st_size:,} байт). База не изменялась.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        raise SystemExit(str(error))
