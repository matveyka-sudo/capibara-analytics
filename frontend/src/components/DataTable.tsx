import { useMemo, useState } from 'react';
import { CopyId } from './Controls';
import { downloadCsv, count } from '../lib/format';
import { cellValue, exportCell, compareCells, type Cell } from '../lib/table';
export { rawCell, type Cell } from '../lib/table';
interface Props {
    name: string;
    headers: string[];
    rows: Cell[][];
    numeric?: number[];
    empty?: string;
}
export function DataTable(props: Props) {
    // A different report/schema gets isolated sorting and pagination state.
    return <TableBody key={JSON.stringify([props.name, props.headers])} {...props}/>;
}
function TableBody({ name, headers, rows, numeric = [], empty = 'Нет подходящих записей' }: Props) {
    const [sort, setSort] = useState<{
        field: string;
        descending: boolean;
    } | null>(null);
    const [pagination, setPagination] = useState({ signature: '', page: 1 });
    const signature = JSON.stringify(rows.map(row => row.map(cellValue)));
    const field = sort ? headers.indexOf(sort.field) : -1;
    const sorted = useMemo(() => field < 0 ? rows : rows.map((row, index) => ({ row, index })).sort((a, b) => compareCells(a.row[field], b.row[field], sort!.descending) || a.index - b.index).map(x => x.row), [rows, field, sort]);
    const pages = Math.max(1, Math.ceil(rows.length / 15));
    const current = Math.min(pagination.signature === signature ? pagination.page : 1, pages);
    const changePage = (page: number) => setPagination({ signature, page });
    const display = (cell: Cell) => {
        if (cell === null)
            return '—';
        if (typeof cell === 'object')
            return 'id' in cell ? <CopyId id={cell.id}/> : cell.display;
        return typeof cell === 'number' ? count(cell) : cell;
    };
    return <div className="data-table">
    <div className="table-actions"><button className="text-button" disabled={!rows.length} onClick={() => downloadCsv(`${name}.csv`, headers, sorted.map(row => row.map(exportCell)))}>Скачать CSV</button></div>
    <div className="table-scroll" tabIndex={0} role="region" aria-label={`Таблица: ${name}`}><table><caption className="sr-only">{name}</caption><thead><tr>{headers.map((header, i) => <th key={header} className={numeric.includes(i) || rows.some(r => typeof cellValue(r[i]) === 'number') ? 'numeric' : ''} aria-sort={sort?.field === header ? sort.descending ? 'descending' : 'ascending' : 'none'}><button onClick={() => { setSort(previous => ({ field: header, descending: previous?.field === header ? !previous.descending : false })); changePage(1); }}>{header}{sort?.field === header ? sort.descending ? ' ↓' : ' ↑' : ''}</button></th>)}</tr></thead>
    <tbody>{sorted.slice((current - 1) * 15, current * 15).map(row => <tr key={JSON.stringify(row.map(cellValue))}>{row.map((cell, i) => <td key={headers[i]} className={numeric.includes(i) || typeof cellValue(cell) === 'number' ? 'numeric' : ''}>{display(cell)}</td>)}</tr>)}{!rows.length && <tr><td colSpan={headers.length} className="empty-cell">{empty}</td></tr>}</tbody></table></div>
    {pages > 1 && <div className="pagination"><span>Страница {current} из {pages}</span><div><button className="button" disabled={current === 1} onClick={() => changePage(current - 1)}>Назад</button><button className="button" disabled={current === pages} onClick={() => changePage(current + 1)}>Далее</button></div></div>}
  </div>;
}
