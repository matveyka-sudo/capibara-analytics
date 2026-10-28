import { useEffect, useRef, useState } from 'react';
import type { Range } from '../lib/types';
import { validRange } from '../lib/analytics';
import { shortId } from '../lib/format';
export function Icon({ name, className = '' }: {
    name: string;
    className?: string;
}) { return <i className={`bi bi-${name} ${className}`} aria-hidden="true"/>; }
export function DateRange({ label, range, onChange, disabled = false, month = false }: {
    label: string;
    range: Range;
    onChange: (r: Range) => void;
    disabled?: boolean;
    month?: boolean;
}) {
    const invalid = !validRange(range, month);
    return <fieldset className="date-range" disabled={disabled}><legend className="sr-only">{label}</legend><div className="range-inputs"><label><span>С {month ? 'месяца' : 'даты'}</span><input aria-label={`${label}: начало`} type={month ? 'month' : 'date'} value={range.start} onChange={e => onChange({ ...range, start: e.target.value })} aria-invalid={invalid}/></label><span className="range-dash" aria-hidden="true">—</span><label><span>По {month ? 'месяц' : 'дату'}</span><input aria-label={`${label}: конец`} type={month ? 'month' : 'date'} value={range.end} onChange={e => onChange({ ...range, end: e.target.value })} aria-invalid={invalid}/></label></div>{invalid && <span className="field-error" role="alert">Начало должно быть не позже конца. Проверьте даты.</span>}</fieldset>;
}
export function SearchSelect({ label, options, value, onChange, allLabel, disabled }: {
    label: string;
    options: {
        value: string;
        label: string;
    }[];
    value: string;
    onChange: (v: string) => void;
    allLabel: string;
    disabled?: boolean;
}) {
    const [query, setQuery] = useState('');
    const ref = useRef<HTMLDetailsElement>(null);
    const selected = options.find(o => o.value === value);
    const filtered = options.filter(o => `${o.label} ${o.value}`.toLowerCase().includes(query.toLowerCase()));
    const visible = filtered.slice(0, 80);
    const choose = (v: string) => { onChange(v); setQuery(''); ref.current?.removeAttribute('open'); };
    return <div className="select-field"><span className="control-label">{label}</span>{disabled ? <button className="select-trigger" disabled>{allLabel}<Icon name="chevron-down"/></button> : <details ref={ref} className="search-select" onKeyDown={e => { if (e.key === 'Escape') {
        ref.current?.removeAttribute('open');
        ref.current?.querySelector('summary')?.focus();
    } }} onBlur={e => { if (!e.currentTarget.contains(e.relatedTarget))
        e.currentTarget.removeAttribute('open'); }}><summary aria-label={label}>{selected?.label ?? allLabel}<Icon name="chevron-down"/></summary><div className="select-menu"><label className="search-box"><Icon name="search"/><input placeholder="Найти по названию или ID" aria-label={`Поиск: ${label}`} value={query} onChange={e => setQuery(e.target.value)}/></label><div className="select-options"><button type="button" onClick={() => choose('')} aria-pressed={!value}>{allLabel}</button>{visible.map(o => <button type="button" key={o.value} onClick={() => choose(o.value)} aria-pressed={value === o.value}>{o.label}</button>)}{filtered.length > visible.length && <p>Первые 80 совпадений. Уточните поиск.</p>}{!filtered.length && <p>Ничего не найдено</p>}</div></div></details>}</div>;
}
export function CopyId({ id }: {
    id: string;
}) {
    const [copied, setCopied] = useState(false);
    const [error, setError] = useState(false);
    useEffect(() => { setCopied(false); setError(false); }, [id]);
    return <span className="id-cell"><span className="id-value" tabIndex={0}><code>{shortId(id)}</code><span className="id-full">{id}</span></span><button className="icon-button" aria-label={`Копировать ID ${id}`} title="Копировать полный ID" onClick={async () => { try {
        await navigator.clipboard.writeText(id);
        setCopied(true);
        setError(false);
    }
    catch {
        setError(true);
    } }}><Icon name={copied ? 'check2' : 'copy'}/></button><span className="sr-only" role="status">{copied ? 'ID скопирован' : error ? `Не удалось скопировать. ID: ${id}` : ''}</span></span>;
}
