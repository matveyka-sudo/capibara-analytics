#!/usr/bin/env bash

set -euo pipefail

BASE="https://raw.githubusercontent.com/olist/work-at-olist-data/master/datasets"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data"

FILES=(
  olist_orders_dataset.csv
  olist_order_items_dataset.csv
  olist_order_payments_dataset.csv
  olist_order_reviews_dataset.csv
  olist_products_dataset.csv
  olist_sellers_dataset.csv
  olist_customers_dataset.csv
  product_category_name_translation.csv
)

mkdir -p "$DIR"

for f in "${FILES[@]}"; do
  if [ -s "$DIR/$f" ]; then
    echo "уже есть: $f"
    continue
  fi
  echo "качаю:    $f"
  curl -fsSL --retry 3 -o "$DIR/$f" "$BASE/$f"
done

echo
echo "Готово. Файлы в $DIR"
du -sh "$DIR"
