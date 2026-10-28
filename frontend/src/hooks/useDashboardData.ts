import { useEffect, useRef, useState } from 'react';
import { parseData } from '../lib/validate';
import type { LoadedData } from '../lib/types';
const BASE = import.meta.env.BASE_URL;
export function useDashboardData() {
    const [loaded, setLoaded] = useState<LoadedData | null>(null);
    const [status, setStatus] = useState<'loading' | 'ready' | 'missing' | 'error'>('loading');
    const [error, setError] = useState('');
    const [attempt, setAttempt] = useState(0);
    const request = useRef(0);
    const accept = (value: LoadedData) => { setLoaded(value); setStatus('ready'); setError(''); };
    useEffect(() => {
        const id = ++request.current;
        const controller = new AbortController();
        let active = true;
        const current = () => active && id === request.current;
        const timer = setTimeout(() => { if (current()) {
            controller.abort();
            setStatus('error');
            setError('Загрузка заняла слишком много времени. Повторите попытку.');
        } }, 25000);
        setStatus('loading');
        setLoaded(null);
        setError('');
        (async () => {
            const pointer = await fetch(`${BASE}data/index.json`, { signal: controller.signal });
            if (pointer.status === 404) {
                if (current())
                    setStatus('missing');
                return;
            }
            if (!pointer.ok)
                throw new Error('Не удалось открыть выгрузку.');
            const manifest = await pointer.json();
            if (!['reports.json', 'dashboard.json'].includes(manifest.file))
                throw new Error('Неверный указатель на файл данных.');
            const response = await fetch(`${BASE}data/${manifest.file}`, { signal: controller.signal });
            if (!response.ok)
                throw new Error('Файл данных недоступен.');
            const result = parseData(await response.json());
            if (current())
                accept(result);
        })().catch(e => { if (current() && !controller.signal.aborted) {
            setStatus('error');
            setError(e instanceof SyntaxError ? 'В файле некорректный JSON.' : e instanceof Error ? e.message : 'Ошибка загрузки.');
        } }).finally(() => clearTimeout(timer));
        return () => { active = false; controller.abort(); clearTimeout(timer); };
    }, [attempt]);
    return { loaded, status, error, retry: () => setAttempt(n => n + 1) };
}
