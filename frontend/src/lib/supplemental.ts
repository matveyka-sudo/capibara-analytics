import type { SupplementalReport } from './types.ts';
import { type Cell } from './table.ts';
const aliases: Record<string, string[]> = {
    product_id: ['product_id'], date: ['date', 'day', 'sale_date', 'purchase_date', 'purchased_on'], price: ['price', 'unit_price'], units: ['units', 'unit_count', 'item_count', 'quantity'],
    state: ['state', 'customer_state', 'buyer_state'], orders: ['orders', 'order_count'], avg_delivery_days: ['average_delivery_days', 'avg_delivery_days', 'average_days', 'avg_delivery_time_days'],
    late_pct: ['late_share_pct', 'late_pct', 'late_order_share_pct', 'late_percentage', 'late_delivery_pct', 'late_rate_percent'], status: ['status', 'order_status'], share_pct: ['share_pct', 'order_share_pct', 'percentage', 'order_share_percent'],
    without_items: ['orders_without_items', 'without_items', 'orders_without_items_count'], payment_type: ['payment_type'], payments: ['payments', 'payment_count'], amount: ['payment_value', 'total_amount', 'amount', 'total_payment_value'],
    avg_installments: ['average_installments', 'avg_installments', 'average_installment_count'], score: ['score', 'review_score'],
};
const schemas: Record<string, string[]> = {
    '6': ['product_id', 'date', 'price', 'units'], '7': ['state', 'orders', 'avg_delivery_days', 'late_pct'], '8': ['status', 'orders', 'share_pct', 'without_items'],
    '9_states': ['state', 'payments', 'amount', 'avg_installments'], '9_methods': ['payment_type', 'payments', 'avg_installments'], '10': ['score', 'orders', 'avg_delivery_days', 'late_pct'],
};
const numeric = new Set(['price', 'units', 'orders', 'avg_delivery_days', 'late_pct', 'share_pct', 'without_items', 'payments', 'amount', 'avg_installments', 'score']);
const integer = new Set(['units', 'orders', 'without_items', 'payments', 'score']);
export function validateSupplemental(report: SupplementalReport, reportId: string): SupplementalReport {
    const id = reportId === '9' ? report.columns.includes('payment_type') ? '9_methods' : '9_states' : reportId;
    const required = schemas[id];
    if (!required)
        throw new Error('Неизвестный отчёт.');
    const columns = report.columns.map(c => Object.keys(aliases).find(key => aliases[key].includes(c.trim().toLowerCase())) ?? c);
    if (required.some(c => !columns.includes(c)) || new Set(columns).size !== columns.length)
        throw new Error(`Неверные поля отчёта ${id}. Ожидаются: ${required.join(', ')}.`);
    const seen = new Set<string>();
    for (const row of report.rows) {
        if (row.length !== columns.length)
            throw new Error('Не совпадает число столбцов.');
        const values = Object.fromEntries(columns.map((c, i) => [c, row[i]]));
        for (const key of required) {
            const v = values[key];
            if (numeric.has(key)) {
                if (!/^\d+(\.\d+)?$/.test(v) || !Number.isFinite(Number(v)) || Number(v) > Number.MAX_SAFE_INTEGER || integer.has(key) && !Number.isSafeInteger(Number(v)))
                    throw new Error(`Некорректное число: ${key}.`);
                if ((key.endsWith('_pct') && Number(v) > 100) || key === 'score' && (Number(v) < 1 || Number(v) > 5))
                    throw new Error(`Значение вне диапазона: ${key}.`);
            }
            else if (!v.trim())
                throw new Error(`Не заполнено поле ${key}.`);
        }
        if (id === '7' && Number(values.orders) < 500)
            throw new Error('Штат не проходит порог 500 заказов.');
        if (id === '8' && Number(values.without_items) > Number(values.orders))
            throw new Error('Заказов без позиций больше общего количества.');
        if (values.date && (!/^\d{4}-\d{2}-\d{2}$/.test(values.date) || !Number.isFinite(Date.parse(values.date)) || new Date(values.date).toISOString().slice(0, 10) !== values.date))
            throw new Error('Некорректная дата продажи.');
        if (values.state && !/^[A-Z]{2}$/.test(values.state))
            throw new Error('Штат должен иметь двухбуквенный код.');
        const key = JSON.stringify(required.filter(c => !numeric.has(c) || c === 'score' || c === 'price').map(c => values[c]));
        if (seen.has(key))
            throw new Error('Повторяется ключ строки отчёта.');
        seen.add(key);
    }
    if (id === '6' && new Set(report.rows.map(r => r[columns.indexOf('product_id')])).size > 1)
        throw new Error('История должна относиться к одному товару.');
    if (id === '8' && report.rows.length && Math.abs(report.rows.reduce((sum, r) => sum + Number(r[columns.indexOf('share_pct')]), 0) - 100) > 0.1)
        throw new Error('Доли статусов не дают 100%.');
    return { ...report, columns };
}
export function supplementalCells(report: SupplementalReport, _currency: string): Cell[][] {
    return report.rows.map(row => row.map((v, i) => {
        const key = report.columns[i];
        if (!numeric.has(key))
            return v;
        const value = Number(v);
        const display = new Intl.NumberFormat('ru-RU', { maximumFractionDigits: integer.has(key) ? 0 : key === 'price' || key === 'amount' ? 2 : 4 }).format(value);
        // Display is rounded; the original decimal string is retained for CSV.
        return { value, display, exportValue: v };
    }));
}
