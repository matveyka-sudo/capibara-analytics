export interface Meta {
  schema_version: 1;
  snapshot_id: string;
  exported_at: string;
  source_label: string;
  source_purchase_date_min: string | null;
  source_purchase_date_max: string | null;
  record_counts?: { orders: number; items: number; sellers: number; categories: number };
  currency_code: string | null;
}
export interface Order { order_id: string; buyer_id: string; status: string; purchased_at: string }
export interface Item { order_item_id: string; order_id: string; seller_id: string; category_id: string; price_cents: number; freight_cents: number }
export interface Seller { seller_id: string; city: string | null; state: string | null }
export interface Category { category_id: string; category_code: string; category_name_en: string | null; category_label: string }
export interface DetailData { meta: Meta; orders: Order[]; items: Item[]; sellers: Seller[]; categories: Category[] }
export interface MonthRow { month: string; orders: number; revenue: number }
export interface SellerRow extends Seller { orders: number; units: number; revenue: number }
export interface CategoryRow extends Category { revenue: number; share: number | null }
export interface OrderSummary { orders: number; revenue: number; freight: number; units: number }
export interface Buyers { total: number; repeat: number }
export interface SupplementalReport { columns: string[]; rows: string[][]; source: string }
export interface ReportData {
  meta: Meta;
  mode: 'reports';
  reports: { monthly: MonthRow[]; sellers: SellerRow[]; average: OrderSummary; buyers: Buyers; categories: CategoryRow[]; additional?: Record<string, SupplementalReport> };
}
export type LoadedData = { mode: 'detail'; data: DetailData } | { mode: 'reports'; data: ReportData };
export interface Range { start: string; end: string }
export interface Index {
  data: DetailData;
  orders: Map<string, Order>;
  totals: Map<string, { revenue: number; freight: number; units: number }>;
  sellers: Map<string, Seller>;
  categories: Map<string, Category>;
  deliveredItems: Item[];
}
