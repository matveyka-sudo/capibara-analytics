export const count = (v: number | null) => v === null ? '—' : new Intl.NumberFormat('ru-RU', { maximumFractionDigits: 0 }).format(v);
export const number = (v: number | null, digits = 2) => v === null ? '—' : new Intl.NumberFormat('ru-RU', { minimumFractionDigits: digits, maximumFractionDigits: digits }).format(v);
export const percent = (v: number | null) => v === null ? '—' : `${number(v * 100)} %`;
export const money = (cents: number | null) => cents === null ? '—' : number(cents / 100);
export const compact = (v: number) => new Intl.NumberFormat('ru-RU', { notation: 'compact', maximumFractionDigits: 1 }).format(v);
export const shortId = (id: string) => `${id.slice(0, 8)}…${id.slice(-4)}`;
export const dateLabel = (v: string) => { const [y, m, d] = v.slice(0, 10).split('-'); return `${d}.${m}.${y}`; };
export const monthLabel = (v: string) => { const [y, m] = v.split('-').map(Number); return new Intl.DateTimeFormat('ru-RU', { month: 'short', year: '2-digit', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, 1))); };
export function downloadCsv(name: string, columns: string[], rows: (string | number | null)[][]) {
  const cell = (v: string | number | null) => { let s = String(v ?? ''); if (/^[=+@\-\t\r]/.test(s)) s = `'${s}`; return `"${s.replaceAll('"', '""')}"`; };
  const body = [columns, ...rows].map(r => r.map(cell).join(';')).join('\r\n');
  const url = URL.createObjectURL(new Blob(['\uFEFF', body], { type: 'text/csv;charset=utf-8' }));
  const a = document.createElement('a'); a.href = url; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
