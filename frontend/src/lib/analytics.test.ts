import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { ALL, buildIndex, buyerSummary, categorySales, monthlySales, orderSummary, topSellers, validRange } from './analytics.ts';
import { parseData } from './validate.ts';
import type { DetailData } from './types.ts';

const id = (n: number) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
function fixture(): DetailData {
  return {
    meta: { schema_version: 1, snapshot_id: 'test-fixture-only', exported_at: '2026-10-28T10:00:00Z', source_label: 'Тестовый набор, не для интерфейса', source_purchase_date_min: '2016-09-01', source_purchase_date_max: '2018-10-31', currency_code: 'BRL' },
    orders: [
      { order_id: id(1), buyer_id: id(100), status: 'delivered', purchased_at: '2016-09-30T23:59:59' },
      { order_id: id(2), buyer_id: id(100), status: 'canceled', purchased_at: '2016-10-01T00:00:00' },
      { order_id: id(3), buyer_id: id(101), status: 'delivered', purchased_at: '2016-10-02T12:00:00' },
    ],
    items: [
      { order_item_id: id(11), order_id: id(1), seller_id: id(20), category_id: id(30), price_cents: 10000, freight_cents: 1000 },
      { order_item_id: id(12), order_id: id(1), seller_id: id(20), category_id: id(30), price_cents: 5000, freight_cents: 500 },
      { order_item_id: id(13), order_id: id(1), seller_id: id(21), category_id: id(31), price_cents: 5000, freight_cents: 500 },
      { order_item_id: id(14), order_id: id(3), seller_id: id(21), category_id: id(32), price_cents: 0, freight_cents: 0 },
    ],
    sellers: [{ seller_id: id(20), city: 'a', state: 'SP' }, { seller_id: id(21), city: 'b', state: 'BA' }],
    categories: [
      { category_id: id(30), category_code: 'sem_traducao', category_name_en: null, category_label: 'sem_traducao' },
      { category_id: id(31), category_code: 'category:unknown', category_name_en: null, category_label: 'Неизвестная категория' },
      { category_id: id(32), category_code: 'zero', category_name_en: 'zero', category_label: 'zero' },
      { category_id: id(33), category_code: 'no_sales', category_name_en: null, category_label: 'no_sales' },
    ],
  };
}
test('полный заказ усредняется один раз; заказы продавцов не суммируются как заказы площадки', () => {
  const ix = buildIndex(fixture()); const avg = orderSummary(ix);
  assert.deepEqual(avg, { orders: 2, revenue: 20000, freight: 2000, units: 4 });
  assert.equal((avg.revenue + avg.freight) / avg.orders, 11000);
  const sellers = topSellers(ix, ALL);
  assert.equal(sellers.find(s => s.seller_id === id(20))!.orders, 1);
  assert.equal(sellers.reduce((n, s) => n + s.orders, 0), 3);
});
test('покупатель с delivered и canceled повторный только при двух заказах внутри окна', () => {
  const ix = buildIndex(fixture());
  assert.deepEqual(buyerSummary(ix), { total: 2, repeat: 1 });
  assert.deepEqual(buyerSummary(ix, { start: '2016-10-01', end: '2016-10-31' }), { total: 2, repeat: 0 });
  assert.deepEqual(buyerSummary(ix, { start: '2016-09-30', end: '2016-09-30' }), { total: 1, repeat: 0 });
});
test('календарь сохраняет нулевой месяц и исходный день без часового сдвига', () => {
  const rows = monthlySales(buildIndex(fixture()), { start: '2016-09', end: '2016-11' });
  assert.deepEqual(rows.map(r => r.orders), [1, 1, 0]);
  assert.equal(rows[0].revenue, 20000);
});
test('неизвестная категория, отсутствие перевода и нулевая категория остаются разными', () => {
  const data = parseData(fixture()); assert.equal(data.mode, 'detail');
  if (data.mode !== 'detail') return;
  const rows = categorySales(buildIndex(data.data), ALL);
  assert.equal(rows.length, 4);
  assert.equal(rows.find(c => c.category_id === id(30))!.category_label, 'sem_traducao');
  assert.equal(rows.find(c => c.category_id === id(31))!.revenue, 5000);
  assert.equal(rows.reduce((s, c) => s + c.revenue, 0), 20000);
  const empty = categorySales(buildIndex(data.data), { start: '2018-01-01', end: '2018-12-31' });
  assert.equal(empty.length, 4); assert.ok(empty.every(c => c.revenue === 0 && c.share === null));
});
test('фильтрация всех продавцов происходит до top-10', () => {
  const d = fixture(); d.orders = []; d.items = []; d.sellers = [];
  for (let i = 0; i < 12; i++) {
    d.sellers.push({ seller_id: id(200 + i), city: null, state: null });
    d.orders.push({ order_id: id(300 + i), buyer_id: id(400 + i), status: 'delivered', purchased_at: '2017-01-01T00:00:00' });
    d.items.push({ order_item_id: id(500 + i), order_id: id(300 + i), seller_id: id(200 + i), category_id: i === 11 ? id(31) : id(30), price_cents: 1200 - i * 100, freight_cents: 0 });
  }
  const ix = buildIndex(d);
  assert.ok(!topSellers(ix, ALL).some(s => s.seller_id === id(211)));
  assert.equal(topSellers(ix, ALL, id(31))[0].seller_id, id(211));
});
test('неполный delivered, дубликаты и потерянные FK блокируют данные', () => {
  const d = fixture(); d.items = [];
  assert.throws(() => parseData(d), /без позиций/);
  const duplicate = fixture(); duplicate.orders.push({ ...duplicate.orders[0] }); assert.throws(() => parseData(duplicate), /Дубликат/);
  const broken = fixture(); broken.items[0].seller_id = id(999); assert.throws(() => parseData(broken), /связь/);
  const unsafe = fixture(); unsafe.items[0].price_cents = Number.MAX_SAFE_INTEGER; assert.throws(() => parseData(unsafe), /точность/);
});
test('пустая валидная выборка отличается от испорченного JSON и неверного периода', () => {
  const ix = buildIndex(fixture());
  assert.deepEqual(orderSummary(ix, { start: '2018-01-01', end: '2018-01-31' }), { orders: 0, revenue: 0, freight: 0, units: 0 });
  assert.deepEqual(buyerSummary(ix, { start: '2018-01-01', end: '2018-01-31' }), { total: 0, repeat: 0 });
  assert.throws(() => parseData({}), /meta/);
  assert.equal(validRange({ start: '2017-02-30', end: '2017-03-02' }), false);
  assert.equal(validRange({ start: '2018-01', end: '2017-02' }, true), false);
});
test('сохранённые реальные SQL-отчёты сходятся с независимыми контролями', () => {
  const loaded = parseData(JSON.parse(readFileSync(new URL('../../public/data/reports.json', import.meta.url), 'utf8')));
  assert.equal(loaded.mode, 'reports'); if (loaded.mode !== 'reports') return;
  const r = loaded.data.reports;
  assert.equal(r.monthly.length, 24); assert.equal(r.monthly.reduce((n, m) => n + m.revenue, 0), 1322149811);
  assert.deepEqual(r.monthly.find(m => m.month === '2016-11'), { month: '2016-11', orders: 0, revenue: 0 });
  assert.equal(r.sellers[0].revenue, 22698793); assert.equal(r.sellers[0].orders, 1124);
  assert.equal(r.average.orders, 96478); assert.equal(r.average.units, 110197);
  assert.equal(r.average.freight, 220296554); assert.equal(r.buyers.total, 96096); assert.equal(r.buyers.repeat, 2997);
  assert.equal(r.categories.length, 74); assert.equal(r.categories.find(c => c.category_code === 'category:unknown')!.revenue, 17072663);
});

test('все готовые ответы блока Б загружаются с фактическими SQL-заголовками', () => {
  const parsed = parseData(JSON.parse(readFileSync(new URL('../../public/data/reports.json', import.meta.url), 'utf8')));
  assert.equal(parsed.mode, 'reports');
  if (parsed.mode !== 'reports') return;
  const additional = parsed.data.reports.additional!;
  for (const key of ['6','7','8','9_states','9_methods','10']) {
    assert.ok(additional[key], `Нет отчёта ${key}`);
    assert.equal(additional[key].error, undefined, `Ошибка отчёта ${key}`);
    assert.ok(additional[key].rows.length > 0);
  }
  const sum = (key: string, column: string) => additional[key].rows.reduce((n,r) => n + Number(r[additional[key].columns.indexOf(column)]), 0);
  assert.equal(sum('6','units'), 151);
  assert.equal(sum('8','orders'), 99441);
  assert.equal(sum('9_states','payments'), 56015);
  assert.equal(sum('9_methods','payments'), 103886);
});
