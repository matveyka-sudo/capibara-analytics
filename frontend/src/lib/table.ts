export type Value = string | number | null;
export type Cell = Value | {
    id: string;
} | {
    value: Value;
    display: string;
    exportValue?: Value;
};
export const rawCell = (value: Value, display: string): Cell => ({ value, display });
export const cellValue = (cell: Cell): Value => typeof cell === 'object' && cell !== null ? 'id' in cell ? cell.id : cell.value : cell;
export function compareCells(a: Cell, b: Cell, descending = false): number {
    const x = cellValue(a), y = cellValue(b);
    if (x === null || y === null)
        return x === y ? 0 : x === null ? 1 : -1;
    const result = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y), 'ru', { numeric: true });
    return descending ? -result : result;
}
export const exportCell = (cell: Cell): Value => typeof cell === 'object' && cell !== null && 'exportValue' in cell ? cell.exportValue ?? null : cellValue(cell);
