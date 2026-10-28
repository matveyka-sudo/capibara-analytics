import type { SupplementalReport } from './types.ts';

// Handles quoted cells, escaped quotes and line breaks without changing raw values.
export function parseCsv(source: string, filename: string): SupplementalReport {
  const text = source.replace(/^\uFEFF/, '');
  let quotedHeader = false; const counts = { ',': 0, ';': 0 };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') { if (quotedHeader && text[i + 1] === '"') i++; else quotedHeader = !quotedHeader; }
    if (!quotedHeader && (c === '\r' || c === '\n')) break;
    if (!quotedHeader && (c === ',' || c === ';')) counts[c]++;
  }
  const separator = counts[';'] > counts[','] ? ';' : ',';
  const rows: string[][] = []; let row: string[] = []; let cell = ''; let quoted = false; let closed = false;
  const finishCell = () => { row.push(cell); cell = ''; closed = false; };
  const finishRow = () => { finishCell(); if (row.some(s => s.trim())) rows.push(row); row = []; };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else { quoted = false; closed = true; } }
      else cell += c;
    } else if (c === separator) finishCell();
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; finishRow(); }
    else if (c === '"') { if (cell || closed) throw new Error('Неожиданная кавычка в CSV.'); quoted = true; }
    else { if (closed) throw new Error('Лишний текст после закрытой кавычки CSV.'); cell += c; }
  }
  if (quoted) throw new Error('В CSV не закрыта кавычка.');
  finishRow();
  const columns = rows.shift()?.map(s => s.trim());
  if (!columns?.length || columns.some(c => !c) || new Set(columns).size !== columns.length) throw new Error('В CSV нужны уникальные непустые заголовки.');
  if (rows.some(r => r.length !== columns.length)) throw new Error('В строках CSV разное число столбцов.');
  return { columns, rows, source: filename };
}

const LABELS: Record<string, string> = {
  date: 'Дата', day: 'Дата', sale_date: 'Дата', purchase_date: 'Дата', purchased_on: 'Дата', price: 'Цена', unit_price: 'Цена',
  units: 'Продано единиц', unit_count: 'Продано единиц', item_count: 'Единицы', quantity: 'Продано единиц', product_id: 'ID товара',
  state: 'Штат покупателя', customer_state: 'Штат покупателя', buyer_state: 'Штат покупателя', order_count: 'Заказы', orders: 'Заказы',
  average_delivery_days: 'Средний срок, дней', avg_delivery_days: 'Средний срок, дней', average_days: 'Средний срок, дней',
  late_share_pct: 'Опоздания, %', late_pct: 'Опоздания, %', late_order_share_pct: 'Опоздания, %', late_percentage: 'Опоздания, %',
  status: 'Статус', order_status: 'Статус', share_pct: 'Доля, %', order_share_pct: 'Доля, %', percentage: 'Доля, %',
  orders_without_items: 'Без позиций', without_items: 'Без позиций', orders_without_items_count: 'Без позиций',
  payment_type: 'Способ оплаты', payment_count: 'Платежи', payments: 'Платежи', payment_value: 'Сумма', total_amount: 'Сумма',
  amount: 'Сумма', total_payment_value: 'Сумма', average_installments: 'Среднее число платежей в рассрочке', avg_installments: 'Среднее число платежей в рассрочке',
  score: 'Оценка', review_score: 'Оценка', avg_delivery_time_days: 'Средний срок, дней', late_delivery_pct: 'Опоздания, %',
};
export const columnLabel = (key: string) => key === 'late_pct' ? 'Опоздания, %' : LABELS[key] ?? key;
export function csvCell(value: string, column: string): string {
  if (column.endsWith('_id') || !/^-?\d+(\.\d+)?$/.test(value) || value.replace(/[^0-9]/g, '').length > 15) return value;
  return new Intl.NumberFormat('ru-RU', { maximumFractionDigits: value.includes('.') ? Math.min(20, value.split('.')[1].length) : 0 }).format(Number(value));
}
