import type { DetailData, Index, Range, OrderSummary, Buyers, MonthRow, SellerRow, CategoryRow } from './types.ts';
import { validDate } from './validate.ts';

export const ALL: Range = { start: '', end: '' };
export const MONTHS: Range = { start: '2016-09', end: '2018-08' };
export function validRange(r: Range, month = false): boolean {
  if (month && (!r.start || !r.end)) return false;
  const check = (s: string) => !s || validDate(month ? `${s}-01` : s);
  if (!check(r.start) || !check(r.end) || (r.start && r.end && r.start > r.end)) return false;
  if (month && r.start && r.end) {
    const [sy, sm] = r.start.split('-').map(Number); const [ey, em] = r.end.split('-').map(Number);
    if ((ey - sy) * 12 + em - sm >= 1200) return false;
  }
  return true;
}
export function inRange(date: string, r: Range): boolean {
  const day = date.slice(0, 10);
  return (!r.start || day >= r.start) && (!r.end || day <= r.end);
}
export function buildIndex(data: DetailData): Index {
  const orders = new Map(data.orders.map(o => [o.order_id, o]));
  const totals: Index['totals'] = new Map();
  const deliveredItems = [];
  for (const i of data.items) {
    const t = totals.get(i.order_id) ?? { revenue: 0, freight: 0, units: 0 };
    t.revenue += i.price_cents; t.freight += i.freight_cents; t.units++;
    totals.set(i.order_id, t);
    if (orders.get(i.order_id)!.status === 'delivered') deliveredItems.push(i);
  }
  return { data, orders, totals, deliveredItems, sellers: new Map(data.sellers.map(s => [s.seller_id, s])), categories: new Map(data.categories.map(c => [c.category_id, c])) };
}
export function orderSummary(ix: Index, range: Range = ALL): OrderSummary {
  const result = { orders: 0, revenue: 0, freight: 0, units: 0 };
  for (const o of ix.data.orders) if (o.status === 'delivered' && inRange(o.purchased_at, range)) {
    const t = ix.totals.get(o.order_id)!;
    result.orders++; result.revenue += t.revenue; result.freight += t.freight; result.units += t.units;
  }
  return result;
}
export function buyerSummary(ix: Index, range: Range = ALL): Buyers {
  const buyers = new Map<string, number>();
  for (const o of ix.data.orders) if (inRange(o.purchased_at, range)) buyers.set(o.buyer_id, (buyers.get(o.buyer_id) ?? 0) + 1);
  return { total: buyers.size, repeat: [...buyers.values()].filter(n => n >= 2).length };
}
export function calendar(start: string, end: string): string[] {
  if (!validRange({ start, end }, true) || !start || !end) return [];
  const [sy, sm] = start.split('-').map(Number); const [ey, em] = end.split('-').map(Number);
  const count = (ey - sy) * 12 + em - sm + 1;
  if (count > 1200) throw new Error('Выберите диапазон не более 100 лет.');
  return Array.from({ length: count }, (_, i) => { const n = sm - 1 + i; return `${sy + Math.floor(n / 12)}-${String(n % 12 + 1).padStart(2, '0')}`; });
}
export function monthlySales(ix: Index, range: Range): MonthRow[] {
  const map = new Map(calendar(range.start, range.end).map(month => [month, { month, orders: 0, revenue: 0 }]));
  for (const o of ix.data.orders) {
    const row = map.get(o.purchased_at.slice(0, 7));
    if (o.status === 'delivered' && row) { row.orders++; row.revenue += ix.totals.get(o.order_id)!.revenue; }
  }
  return [...map.values()];
}
export function topSellers(ix: Index, range: Range, category = ''): SellerRow[] {
  const groups = new Map<string, { revenue: number; units: number; orders: Set<string> }>();
  for (const i of ix.deliveredItems) if ((!category || category === i.category_id) && inRange(ix.orders.get(i.order_id)!.purchased_at, range)) {
    const g = groups.get(i.seller_id) ?? { revenue: 0, units: 0, orders: new Set<string>() };
    g.revenue += i.price_cents; g.units++; g.orders.add(i.order_id); groups.set(i.seller_id, g);
  }
  return [...groups].map(([id, g]) => ({ ...ix.sellers.get(id)!, revenue: g.revenue, units: g.units, orders: g.orders.size }))
    .sort((a, b) => b.revenue - a.revenue || a.seller_id.localeCompare(b.seller_id)).slice(0, 10);
}
export function categorySales(ix: Index, range: Range, seller = ''): CategoryRow[] {
  const sums = new Map(ix.data.categories.map(c => [c.category_id, 0])); let total = 0;
  for (const i of ix.deliveredItems) if ((!seller || seller === i.seller_id) && inRange(ix.orders.get(i.order_id)!.purchased_at, range)) { sums.set(i.category_id, sums.get(i.category_id)! + i.price_cents); total += i.price_cents; }
  return ix.data.categories.map(c => ({ ...c, revenue: sums.get(c.category_id)!, share: total ? sums.get(c.category_id)! / total : null })).sort((a, b) => b.revenue - a.revenue || a.category_id.localeCompare(b.category_id));
}

export function rangeCovered(range: Range, ix: Index, month = false) {
  const min = ix.data.meta.source_purchase_date_min!.slice(0, month ? 7 : 10);
  const max = ix.data.meta.source_purchase_date_max!.slice(0, month ? 7 : 10);
  return (!range.start || range.start >= min) && (!range.end || range.end <= max);
}
