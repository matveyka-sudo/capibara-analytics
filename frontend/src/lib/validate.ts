import type { DetailData, LoadedData, Meta, ReportData } from './types.ts';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const STATUSES = new Set(['approved', 'canceled', 'created', 'delivered', 'invoiced', 'processing', 'shipped', 'unavailable']);
function fail(message: string): never { throw new Error(message); }
function record(value: unknown, name: string): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`Неверная структура: ${name}.`);
  return value as Record<string, unknown>;
}
function text(v: unknown, label: string): asserts v is string { if (typeof v !== 'string' || !v.trim()) fail(`Не заполнено поле ${label}.`); }
function integer(v: unknown, label: string): asserts v is number { if (typeof v !== 'number' || !Number.isSafeInteger(v) || v < 0) fail(`Поле ${label} должно быть безопасным целым числом ≥ 0.`); }
function nullableText(v: unknown, label: string) { if (v !== null && typeof v !== 'string') fail(`Некорректное поле ${label}.`); }
function array(v: unknown, label: string): Record<string, unknown>[] {
  if (!Array.isArray(v)) fail(`Нет массива ${label}.`);
  return v.map((x) => record(x, label));
}
function key(v: unknown, label: string): asserts v is string { if (typeof v !== 'string' || !UUID.test(v)) fail(`Некорректный UUID: ${label}.`); }
export function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d;
}
function metadata(v: unknown, reports: boolean): Meta {
  const m = record(v, 'meta');
  if (m.schema_version !== 1) fail('Версия формата не поддерживается. Ожидается schema_version: 1.');
  for (const k of ['snapshot_id', 'source_label', 'exported_at']) text(m[k], `meta.${k}`);
  if (!Number.isFinite(Date.parse(m.exported_at as string))) fail('Некорректная дата выгрузки.');
  for (const k of ['source_purchase_date_min', 'source_purchase_date_max']) {
    if (reports && m[k] === null) continue;
    if (typeof m[k] !== 'string' || !validDate((m[k] as string).slice(0, 10))) fail('Некорректные границы снимка.');
  }
  if (m.source_purchase_date_min && m.source_purchase_date_max && (m.source_purchase_date_min as string) > (m.source_purchase_date_max as string)) fail('Границы снимка перепутаны.');
  if (m.currency_code !== null && (typeof m.currency_code !== 'string' || !/^[A-Z]{3}$/.test(m.currency_code))) fail('Некорректный код валюты.');
  return m as unknown as Meta;
}
function unique(rows: Record<string, unknown>[], field: string, label: string): Set<string> {
  const keys = new Set<string>();
  for (const row of rows) { key(row[field], `${label}.${field}`); if (keys.has(row[field])) fail(`Дубликат ключа в ${label}.`); keys.add(row[field]); }
  return keys;
}
export function parseData(value: unknown): LoadedData {
  const root = record(value, 'выгрузка');
  const meta = metadata(root.meta, root.mode === 'reports');
  if (root.mode === 'reports') return parseReports(root, meta);
  const orders = array(root.orders, 'orders'); const items = array(root.items, 'items');
  const sellers = array(root.sellers, 'sellers'); const categories = array(root.categories, 'categories');
  if (meta.record_counts) {
    for (const [name, rows] of Object.entries({ orders, items, sellers, categories })) {
      const expected = record(meta.record_counts, 'record_counts')[name];
      integer(expected, `record_counts.${name}`);
      if (expected !== rows.length) fail(`Потеря строк при выгрузке: ${name}.`);
    }
  }
  const orderKeys = unique(orders, 'order_id', 'orders'); unique(items, 'order_item_id', 'items');
  const sellerKeys = unique(sellers, 'seller_id', 'sellers'); const categoryKeys = unique(categories, 'category_id', 'categories');
  for (const s of sellers) { nullableText(s.city, 'city'); nullableText(s.state, 'state'); }
  for (const c of categories) {
    text(c.category_code, 'category_code'); nullableText(c.category_name_en, 'category_name_en');
    text(c.category_label, 'category_label');
    c.category_label = c.category_name_en || (c.category_code === 'category:unknown' ? 'Неизвестная категория' : c.category_code);
  }
  for (const o of orders) {
    key(o.buyer_id, 'buyer_id'); if (!STATUSES.has(o.status as string)) fail('Неизвестный статус заказа.');
    text(o.purchased_at, 'purchased_at');
    if (!/^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?$/.test(o.purchased_at) || !validDate(o.purchased_at.slice(0, 10)) || o.purchased_at.slice(11, 19) > '23:59:59' || Number(o.purchased_at.slice(14, 16)) > 59 || Number(o.purchased_at.slice(17, 19)) > 59) fail('Некорректная дата покупки или неожиданный часовой пояс.');
    const date = o.purchased_at.slice(0, 10);
    if (date < meta.source_purchase_date_min!.slice(0, 10) || date > meta.source_purchase_date_max!.slice(0, 10)) fail('Заказ выходит за границы снимка.');
  }
  let moneyTotal = 0; const withItems = new Set<string>();
  for (const item of items) {
    key(item.order_id, 'item.order_id'); key(item.seller_id, 'item.seller_id'); key(item.category_id, 'item.category_id');
    if (!orderKeys.has(item.order_id) || !sellerKeys.has(item.seller_id) || !categoryKeys.has(item.category_id)) fail('Нарушена связь позиции с заказом, продавцом или категорией.');
    integer(item.price_cents, 'price_cents'); integer(item.freight_cents, 'freight_cents');
    moneyTotal += item.price_cents + item.freight_cents;
    if (!Number.isSafeInteger(moneyTotal)) fail('Суммы превышают безопасную точность JavaScript.');
    withItems.add(item.order_id);
  }
  for (const o of orders) if (o.status === 'delivered' && !withItems.has(o.order_id as string)) fail('Неполные данные: доставленный заказ без позиций. Итоги не опубликованы.');
  return { mode: 'detail', data: { meta, orders, items, sellers, categories } as unknown as DetailData };
}
function parseReports(root: Record<string, unknown>, meta: Meta): LoadedData {
  const r = record(root.reports, 'reports');
  const monthly = array(r.monthly, 'monthly'); const sellers = array(r.sellers, 'sellers'); const categories = array(r.categories, 'categories');
  const avg = record(r.average, 'average'); const buyers = record(r.buyers, 'buyers');
  unique(sellers, 'seller_id', 'reports.sellers');
  const months = new Set<string>();
  for (const m of monthly) {
    if (typeof m.month !== 'string' || !/^\d{4}-(0[1-9]|1[0-2])$/.test(m.month) || months.has(m.month)) fail('Неверный или повторяющийся месяц отчёта.');
    months.add(m.month); integer(m.orders, 'monthly.orders'); integer(m.revenue, 'monthly.revenue');
  }
  for (const s of sellers) { key(s.seller_id, 'seller_id'); nullableText(s.city, 'city'); nullableText(s.state, 'state'); for (const k of ['orders', 'units', 'revenue']) integer(s[k], `seller.${k}`); }
  const cats = new Set<string>();
  for (const c of categories) { text(c.category_id, 'category_id'); text(c.category_code, 'category_code'); text(c.category_label, 'category_label'); nullableText(c.category_name_en, 'category_name_en'); integer(c.revenue, 'category.revenue'); if (cats.has(c.category_id)) fail('Дубликат категории.'); cats.add(c.category_id); }
  for (const k of ['orders', 'revenue', 'freight', 'units']) integer(avg[k], `average.${k}`);
  integer(buyers.total, 'buyers.total'); integer(buyers.repeat, 'buyers.repeat');
  if (buyers.repeat > buyers.total) fail('Повторных покупателей больше, чем всего покупателей.');
  const total = categories.reduce((a, c) => a + (c.revenue as number), 0);
  if (total !== avg.revenue || !Number.isSafeInteger(total + (avg.freight as number))) fail('Итог категорий не совпадает с общей выручкой.');
  for (const c of categories) c.share = total ? (c.revenue as number) / total : null;
  if (r.additional !== undefined) {
    const additional = record(r.additional, 'additional');
    for (const [id, v] of Object.entries(additional)) {
      if (!['6', '7', '8', '9', '9_states', '9_methods', '10'].includes(id)) fail('Неизвестный номер дополнительного отчёта.');
      const report = record(v, `additional.${id}`); text(report.source, 'source');
      if (!Array.isArray(report.columns) || !report.columns.length || !report.columns.every(c => typeof c === 'string' && c.trim()) || new Set(report.columns).size !== report.columns.length) fail('Неверные заголовки дополнительного отчёта.');
      if (!Array.isArray(report.rows) || report.rows.some(row => !Array.isArray(row) || row.length !== (report.columns as string[]).length || row.some(c => typeof c !== 'string'))) fail('Неверные строки дополнительного отчёта.');
    }
  }
  return { mode: 'reports', data: { meta, mode: 'reports', reports: r } as unknown as ReportData };
}
