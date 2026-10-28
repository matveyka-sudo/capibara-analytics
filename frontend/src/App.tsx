import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import type { Buyers, Index, LoadedData, Range, SellerRow, SupplementalReport } from './lib/types';
import { parseData } from './lib/validate';
import { ALL, MONTHS, buildIndex, buyerSummary, categorySales, inRange, monthlySales, orderSummary, topSellers, validRange } from './lib/analytics';
import { count, dateLabel, downloadCsv, money, number, percent, shortId } from './lib/format';
import { columnLabel, csvCell, parseCsv } from './lib/csv';
import { CopyId, DateRange, SearchSelect } from './components/Controls';

const BASE = import.meta.env.BASE_URL;
const FEATURES = [
  ['sales', 'Пульс продаж'], ['seller', 'Профиль продавца'], ['canceled', 'Отмены'],
  ['delivery', 'Доставка'], ['repeat', 'Возвращаются к продавцу'], ['recommendations', 'Рекомендации'],
];
const QUESTIONS = [
  { id: 1, label: 'Продажи по месяцам', question: 'Как менялись выручка и количество заказов?', note: 'Доставленные заказы. Выручка от товаров без доставки.' },
  { id: 2, label: 'Топ-10 продавцов', question: 'Какие продавцы принесли больше всего выручки?', note: 'У каждого продавца учитываются только его товарные позиции.' },
  { id: 3, label: 'Средний чек', question: 'Какова средняя стоимость и состав заказа?', note: 'Полные доставленные заказы. Средний чек включает доставку.' },
  { id: 4, label: 'Повторные заказы площадки', question: 'Сколько покупателей оформили второй заказ?', note: 'Все статусы заказов. Это повторные заказы внутри периода, а не удержание.' },
  { id: 5, label: 'Категории товаров', question: 'Какие категории формируют выручку?', note: 'Доставленные заказы. Поиск по таблице не меняет знаменатель долей.' },
  { id: 6, label: 'История цены товара', question: 'Как менялась цена товара с наибольшим числом разных цен?', note: 'История одного выбранного товара: дата, цена и проданные единицы.' },
  { id: 7, label: 'Доставка по штатам', question: 'Как отличаются сроки доставки и опоздания по штатам?', note: 'Только штаты покупателей с числом заказов не меньше 500.' },
  { id: 8, label: 'Воронка статусов', question: 'Сколько заказов находится в каждом статусе?', note: 'Все статусы. Отдельно показываются заказы без товарных позиций.' },
  { id: 9, label: 'Оплата и рассрочка', question: 'Какими способами платят и какую рассрочку выбирают?', note: 'По штатам покупателей за 2018 год и по способам оплаты за весь снимок.' },
  { id: 10, label: 'Оценка и срок доставки', question: 'Как связана оценка покупателя со сроком доставки?', note: 'Для оценок от 1 до 5: заказы, средний срок доставки и доля опозданий.' },
];
const PENDING_HEADERS: Record<number, string[]> = {
  6: ['Дата', 'Цена', 'Продано единиц'],
  7: ['Штат', 'Заказы', 'Средний срок, дней', 'Опоздания, %'],
  8: ['Статус', 'Заказы', 'Доля, %', 'Без позиций'],
  9: ['Штат / способ оплаты', 'Платежи', 'Сумма', 'Средняя рассрочка'],
  10: ['Оценка', 'Заказы', 'Средний срок, дней', 'Опоздания, %'],
};
type Cell = string | number | null | { id: string };
const STATUS_LABELS: Record<string, string> = { delivered: 'Доставлен', canceled: 'Отменён', unavailable: 'Недоступен', approved: 'Подтверждён', created: 'Создан', invoiced: 'Выставлен счёт', processing: 'Обрабатывается', shipped: 'В пути' };

export default function App() {
  const [feature, setFeature] = useState('sales');
  const [block, setBlock] = useState<'A' | 'B'>('A'); const [questionId, setQuestionId] = useState(1);
  const [loaded, setLoaded] = useState<LoadedData | null>(null);
  const [status, setStatus] = useState<'loading' | 'ready' | 'missing' | 'error'>('loading');
  const [error, setError] = useState(''); const [attempt, setAttempt] = useState(0);
  const [ranges, setRanges] = useState<Record<number, Range>>({ 1: { ...MONTHS } });
  const [category, setCategory] = useState(''); const [categorySeller, setCategorySeller] = useState('');
  const [search, setSearch] = useState(''); const [profileSeller, setProfileSeller] = useState('');
  const [repeatSeller, setRepeatSeller] = useState(''); const [repeatRange, setRepeatRange] = useState<Range>({ ...ALL });
  const [paymentSlice, setPaymentSlice] = useState<'states' | 'methods'>('states');
  const [localReports, setLocalReports] = useState<Record<string, SupplementalReport>>({}); const [csvError, setCsvError] = useState('');
  const fileRef = useRef<HTMLInputElement>(null); const csvRef = useRef<HTMLInputElement>(null); const dialog = useRef<HTMLDialogElement>(null); const request = useRef(0);
  const resetFilters = () => { setRanges({ 1: { ...MONTHS } }); setCategory(''); setCategorySeller(''); setSearch(''); setRepeatRange({ ...ALL }); };
  const accept = (value: LoadedData) => { setLoaded(value); setStatus('ready'); setError(''); resetFilters(); setProfileSeller(''); setRepeatSeller(''); setLocalReports({}); };
  useEffect(() => {
    const id = ++request.current; const controller = new AbortController(); let active = true;
    const current = () => active && id === request.current;
    const timer = setTimeout(() => { if (current()) { controller.abort(); setStatus('error'); setError('Загрузка заняла слишком много времени. Повторите попытку.'); } }, 25000);
    setStatus('loading'); setLoaded(null); setError('');
    (async () => {
      const pointer = await fetch(`${BASE}data/index.json`, { signal: controller.signal });
      if (pointer.status === 404) { if (current()) setStatus('missing'); return; }
      if (!pointer.ok) throw new Error('Не удалось открыть выгрузку.');
      const manifest = await pointer.json();
      if (!['reports.json', 'dashboard.json'].includes(manifest.file)) throw new Error('Неверный указатель на файл данных.');
      const response = await fetch(`${BASE}data/${manifest.file}`, { signal: controller.signal });
      if (!response.ok) throw new Error('Файл данных недоступен.');
      const result = parseData(await response.json()); if (current()) accept(result);
    })().catch(e => { if (current() && !controller.signal.aborted) { setStatus('error'); setError(e instanceof SyntaxError ? 'В файле некорректный JSON.' : e instanceof Error ? e.message : 'Ошибка загрузки.'); } }).finally(() => clearTimeout(timer));
    return () => { active = false; controller.abort(); clearTimeout(timer); };
  }, [attempt]);
  const upload = async (file?: File) => {
    if (!file) return; const id = ++request.current;
    setError(''); setLoaded(null); setStatus('loading');
    try { if (file.size > 150 * 1024 * 1024) throw new Error('Максимальный размер файла — 150 МБ.'); const value = parseData(JSON.parse(await file.text())); if (id === request.current) accept(value); }
    catch (e) { if (id === request.current) { setStatus('error'); setError(e instanceof SyntaxError ? 'В файле некорректный JSON.' : e instanceof Error ? e.message : 'Не удалось открыть файл.'); } }
  };
  const ix = useMemo(() => loaded?.mode === 'detail' ? buildIndex(loaded.data) : null, [loaded]);
  const reports = loaded?.mode === 'reports' ? loaded.data.reports : null;
  const meta = loaded?.data.meta; const currency = meta?.currency_code ?? 'ден. ед.';
  const ready = status === 'ready'; const range = ranges[questionId] ?? ALL;
  const updateRange = (r: Range) => setRanges(previous => ({ ...previous, [questionId]: r }));
  const categoryOptions = useMemo(() => ix ? ix.data.categories.map(c => ({ value: c.category_id, label: c.category_label })) : [], [ix]);
  const sellerOptions = useMemo(() => ix ? ix.data.sellers.map(s => ({ value: s.seller_id, label: `${shortId(s.seller_id)} · ${s.city ?? 'Город неизвестен'} / ${s.state ?? '—'}` })) : (reports?.sellers ?? []).map(s => ({ value: s.seller_id, label: `${shortId(s.seller_id)} · ${s.city ?? '—'} / ${s.state ?? '—'}` })), [ix, reports]);
  const months = useMemo(() => ix ? validRange(ranges[1] ?? MONTHS, true) ? monthlySales(ix, ranges[1] ?? MONTHS) : [] : reports?.monthly ?? [], [ix, reports, ranges]);
  const sellerRows = useMemo(() => ix ? validRange(ranges[2] ?? ALL) ? topSellers(ix, ranges[2] ?? ALL, category) : [] : reports?.sellers ?? [], [ix, reports, ranges, category]);
  const average = useMemo(() => ix ? validRange(ranges[3] ?? ALL) ? orderSummary(ix, ranges[3] ?? ALL) : null : reports?.average ?? null, [ix, reports, ranges]);
  const buyers = useMemo(() => ix ? validRange(ranges[4] ?? ALL) ? buyerSummary(ix, ranges[4] ?? ALL) : null : reports?.buyers ?? null, [ix, reports, ranges]);
  const categories = useMemo(() => ix ? validRange(ranges[5] ?? ALL) ? categorySales(ix, ranges[5] ?? ALL, categorySeller) : [] : reports?.categories ?? [], [ix, reports, ranges, categorySeller]);
  const currentQuestion = QUESTIONS.find(q => q.id === questionId)!;
  const reportKey = questionId === 9 ? `9_${paymentSlice}` : String(questionId);
  const legacyPayment = reports?.additional?.['9'];
  const additional = localReports[reportKey] ?? reports?.additional?.[reportKey] ?? (questionId === 9 && legacyPayment && (legacyPayment.columns.includes('payment_type') ? paymentSlice === 'methods' : paymentSlice === 'states') ? legacyPayment : questionId !== 9 ? reports?.additional?.[String(questionId)] : undefined);
  const allSummary = useMemo(() => ix ? orderSummary(ix) : reports?.average ?? null, [ix, reports]);
  const chooseQuestion = (id: number) => { setQuestionId(id); setSearch(''); setCsvError(''); };

  function reportContent(): ReactNode {
    if (questionId === 1) return <><p className="report-total">Месяцев: {months.length} · {count(months.reduce((n, r) => n + r.orders, 0))} заказов · {money(months.reduce((n, r) => n + r.revenue, 0))} {currency}</p><DataTable name="Продажи по месяцам" headers={['Месяц', 'Заказы', `Выручка, ${currency}`]} rows={months.map(m => [m.month, count(m.orders), money(m.revenue)])} numeric={[1, 2]} /></>;
    if (questionId === 2) return <DataTable name="Топ-10 продавцов" headers={['ID продавца', 'Город', 'Штат', 'Заказы', 'Единицы', `Выручка, ${currency}`]} rows={sellerRows.map(s => [{ id: s.seller_id }, s.city ?? 'Неизвестно', s.state ?? '—', count(s.orders), count(s.units), money(s.revenue)])} numeric={[3, 4, 5]} />;
    if (questionId === 3) return <KeyValues name="Средний чек" rows={[
      ['Средний чек с доставкой', average ? `${money(average.orders ? (average.revenue + average.freight) / average.orders : null)} ${currency}` : '—'],
      ['Строк товара на заказ', average ? number(average.orders ? average.units / average.orders : null, 3) : '—'],
      ['Единиц товара на заказ', average ? number(average.orders ? average.units / average.orders : null, 3) : '—'],
      ['Заказов в расчёте', average ? count(average.orders) : '—'],
    ]} />;
    if (questionId === 4) return <KeyValues name="Повторные заказы площадки" rows={[
      ['Покупателей с заказами', buyers ? count(buyers.total) : '—'],
      ['Покупателей с двумя и более заказами', buyers ? count(buyers.repeat) : '—'],
      ['Доля повторных покупателей', buyers ? percent(buyers.total ? buyers.repeat / buyers.total : null) : '—'],
    ]} />;
    if (questionId === 5) { const rows = categories.filter(c => `${c.category_label} ${c.category_code}`.toLowerCase().includes(search.toLowerCase())); return <><label className="search-label">Найти категорию<input type="search" value={search} onChange={e => setSearch(e.target.value)} placeholder="Название или исходный код" /></label><DataTable name="Категории" headers={['Категория', `Выручка, ${currency}`, 'Доля']} rows={rows.map(c => [c.category_label, money(c.revenue), percent(c.share)])} numeric={[1, 2]} /><p className="muted small">Всего в справочнике: {categories.length}. Поиск не меняет доли.</p></>; }
    if (additional) return <><p className="source-note">Источник: {additional.source}. Показаны значения из файла, расчёт в браузере не выполняется.</p><DataTable name={`Вопрос ${questionId}`} headers={additional.columns.map(columnLabel)} rows={additional.rows.map(r => r.map((v, i) => csvCell(v, additional.columns[i])))} /></>;
    if (questionId === 8 && ix) {
      const groups = new Map<string, { orders: number; without: number }>();
      for (const o of ix.data.orders) { const g = groups.get(o.status) ?? { orders: 0, without: 0 }; g.orders++; if (!ix.totals.has(o.order_id)) g.without++; groups.set(o.status, g); }
      return <DataTable name="Воронка статусов" headers={PENDING_HEADERS[8]} rows={[...groups].sort((a, b) => b[1].orders - a[1].orders).map(([s, g]) => [`${STATUS_LABELS[s] ?? s} (${s})`, count(g.orders), percent(ix.data.orders.length ? g.orders / ix.data.orders.length : null), count(g.without)])} numeric={[1, 2, 3]} />;
    }
    return <><div className="pending"><strong>Результат ещё не подключён</strong><p>Когда SQL-запрос будет готов, его CSV можно открыть здесь. Числа не подставляем вручную.</p><button className="button" onClick={() => csvRef.current?.click()}>Загрузить результат CSV</button></div><DataTable name={`Ожидаемый формат вопроса ${questionId}`} headers={questionId === 9 ? paymentSlice === 'states' ? ['Штат', 'Платежи', 'Сумма', 'Средняя рассрочка'] : ['Способ оплаты', 'Платежи', 'Средняя рассрочка'] : PENDING_HEADERS[questionId]} rows={[]} empty="Ожидается выгрузка результата" /></>;
  }

  return <><a className="skip-link" href="#content">К отчёту</a><header className="app-header"><div className="header-inner"><div><a className="wordmark" href="#" onClick={e => { e.preventDefault(); setFeature('sales'); }}>Capibara</a><span className="header-caption">Аналитика маркетплейса</span></div><div className="header-actions"><button className="text-button" onClick={() => dialog.current?.showModal()}>Как считаем</button><button className="button" onClick={() => fileRef.current?.click()}>Загрузить данные</button></div></div></header>
  <div className="app-container"><nav className="feature-nav" aria-label="Возможности системы">{FEATURES.map(([id, label]) => <button key={id} className={feature === id ? 'selected' : ''} aria-current={feature === id ? 'page' : undefined} onClick={() => setFeature(id)}>{label}</button>)}</nav>
  <div className="data-line"><span>{status === 'loading' ? 'Загрузка данных…' : ready && meta ? `${loaded?.mode === 'reports' ? 'Сохранённые SQL-отчёты' : 'Подробный снимок'} · ${dateLabel(meta.exported_at)}` : 'Данные не подключены'}</span><button className="text-button" onClick={resetFilters} disabled={!ready}>Сбросить фильтры</button></div>
  {status === 'loading' && <div className="notice" role="status">Загружаем и проверяем файл…</div>}
  {(status === 'missing' || status === 'error') && <div className="notice error" role="alert"><strong>{status === 'missing' ? 'Нет файла данных' : 'Не удалось открыть данные'}</strong><p>{error || 'Загрузите JSON снимка или опубликованных отчётов.'}</p><button className="button" onClick={() => setAttempt(n => n + 1)}>Повторить</button></div>}
  <main id="content" className="workspace">
  {feature === 'sales' && <><div className="page-heading"><div><h1>Пульс продаж</h1><p>Бизнес-вопросы и результаты расчётов.</p></div><div className="block-switch" aria-label="Блок вопросов"><button aria-pressed={block === 'A'} onClick={() => { setBlock('A'); chooseQuestion(1); }}>Блок А · 1–5</button><button aria-pressed={block === 'B'} onClick={() => { setBlock('B'); chooseQuestion(6); }}>Блок Б · 6–10</button></div></div>
    <div className="report-picker"><label>Отчёт<select aria-label="Отчёт" value={questionId} onChange={e => chooseQuestion(Number(e.target.value))}>{QUESTIONS.filter(q => block === 'A' ? q.id <= 5 : q.id >= 6).map(q => <option key={q.id} value={q.id}>{q.id}. {q.label}</option>)}</select></label></div>
    {questionId === 9 && <label className="search-label payment-slice">Разрез оплаты<select aria-label="Разрез оплаты" value={paymentSlice} onChange={e => setPaymentSlice(e.target.value as 'states' | 'methods')}><option value="states">Штаты покупателей · 2018 год</option><option value="methods">Способы оплаты · весь снимок</option></select></label>}
    <div className="question-heading"><h2>{currentQuestion.question}</h2><p>{currentQuestion.note}</p></div>
    {ix && questionId <= 5 && <div className="filters"><DateRange label={currentQuestion.label} range={range} onChange={updateRange} month={questionId === 1} />{questionId === 2 && <SearchSelect label="Категория" options={categoryOptions} value={category} onChange={setCategory} allLabel="Все категории" />}{questionId === 5 && <SearchSelect label="Продавец" options={sellerOptions} value={categorySeller} onChange={setCategorySeller} allLabel="Все продавцы" />}</div>}
    {!ix && ready && questionId <= 5 && <p className="source-note">Показан сохранённый ответ SQL за исходный период. Фильтры появятся после загрузки подробного снимка.</p>}
    {ready ? validRange(range, questionId === 1) ? reportContent() : <div className="notice error">Проверьте диапазон дат.</div> : <div className="empty">Отчёт появится после подключения данных.</div>}
    {questionId >= 6 && additional && <button className="text-button" onClick={() => csvRef.current?.click()}>Заменить CSV этого отчёта</button>}
    {csvError && <p className="error-text" role="alert">{csvError}</p>}
  </>}
  {feature === 'seller' && <><PageHeading title="Профиль продавца" description="Продажи выбранного продавца, его город и штат." /><SearchSelect label="Продавец" options={sellerOptions} value={profileSeller} onChange={setProfileSeller} allLabel="Выберите продавца" disabled={!ready} />{!ix && ready && <p className="source-note">Доступны продавцы из сохранённого топ-10. Подробная динамика и ассортимент требуют отдельной выгрузки.</p>}{profileSeller && ready ? <SellerProfile id={profileSeller} ix={ix} summary={reports?.sellers.find(s => s.seller_id === profileSeller)} currency={currency} /> : <div className="empty">Выберите продавца, чтобы посмотреть показатели.</div>}</>}
  {feature === 'canceled' && <><PageHeading title="Отмены и недоступность" description="Два статуса считаются отдельно. Это отмены заказов, а не возвраты после получения." />{ix ? <CancellationTable ix={ix} currency={currency} /> : <PendingFeature text="В пяти базовых отчётах нет статистики отмен. Нужен подробный снимок или результат дополнительного SQL-запроса." />}<p className="source-note">Сравнение регионов покупателей появится после подключения регионального отчёта. Стоимость известных позиций не равна доказанной потере выручки.</p></>}
  {feature === 'delivery' && <><PageHeading title="Доставка под контролем" description="Стоимость доставки и отчёты о сроках." />{ready && allSummary ? <KeyValues name="Стоимость доставки" rows={[
    ['Средняя доставка на доставленный заказ', `${money(allSummary.orders ? allSummary.freight / allSummary.orders : null)} ${currency}`],
    ['Доля доставки в стоимости покупки', percent(allSummary.revenue + allSummary.freight ? allSummary.freight / (allSummary.revenue + allSummary.freight) : null)],
    ['Доставленных заказов в расчёте', count(allSummary.orders)],
  ]} /> : <PendingFeature text="Для расчёта стоимости подключите данные." />}<div className="related-reports"><h2>Сроки доставки</h2><button className="report-link" onClick={() => { setFeature('sales'); setBlock('B'); chooseQuestion(7); }}>7. Доставка по штатам покупателя <span>Открыть отчёт →</span></button><button className="report-link" onClick={() => { setFeature('sales'); setBlock('B'); chooseQuestion(10); }}>10. Оценка покупателя и срок доставки <span>Открыть отчёт →</span></button><p className="source-note">Медиана и P90 положительной задержки будут доступны после подключения дополнительного расчёта. Стоимость доставки — историческая сумма для покупателя, не себестоимость логистики.</p></div></>}
  {feature === 'repeat' && <><PageHeading title="Возвращаются к продавцу" description="Доля покупателей с двумя разными доставленными заказами у одного продавца за выбранный период." />{ix ? <><div className="filters"><SearchSelect label="Продавец" options={sellerOptions} value={repeatSeller} onChange={setRepeatSeller} allLabel="Выберите продавца" /><DateRange label="Возвращаются к продавцу" range={repeatRange} onChange={setRepeatRange} /></div>{repeatSeller && validRange(repeatRange) ? <SellerRepeat ix={ix} id={repeatSeller} range={repeatRange} /> : <div className="empty">Выберите продавца и корректный период.</div>}</> : <PendingFeature text="Общая повторность площадки не заменяет этот показатель. Нужен подробный снимок или отдельный расчёт по продавцам." />}</>}
  {feature === 'recommendations' && <><PageHeading title="С этим товаром покупают" description="Товары, которые покупали вместе с выбранным, с объяснением связи." /><PendingFeature text="Рекомендации ещё не подключены. После готовности расчёта здесь появятся товар, связанные товары и число совместных заказов." /><p className="source-note">Если истории недостаточно, выдача будет пустой с пояснением. Случайные товары вместо рекомендаций не показываем.</p></>}
  </main><footer>Учебные данные Olist. Masha &amp; The Bears · 2026</footer></div>
  <input className="sr-only" type="file" accept=".json,application/json" ref={fileRef} aria-label="Файл данных JSON" onChange={e => { void upload(e.target.files?.[0]); e.target.value = ''; }} />
  <input className="sr-only" type="file" accept=".csv,text/csv" ref={csvRef} aria-label="Файл результата CSV" onChange={async e => { const file = e.target.files?.[0]; const key = reportKey; e.target.value = ''; if (!file) return; try { if (file.size > 20 * 1024 * 1024) throw new Error('Максимум — 20 МБ.'); const result = parseCsv(await file.text(), file.name); setLocalReports(p => ({ ...p, [key]: result })); setCsvError(''); } catch (error) { setCsvError(error instanceof Error ? error.message : 'Не удалось открыть CSV.'); } }} />
  <dialog ref={dialog} className="method-dialog" onClick={e => { if (e.target === e.currentTarget) dialog.current?.close(); }}><div className="dialog-heading"><h2>Как считаем</h2><button className="text-button" autoFocus onClick={() => dialog.current?.close()}>Закрыть</button></div><dl><dt>Выручка</dt><dd>Цены товаров доставленных заказов без доставки. Это не прибыль площадки.</dd><dt>Средний чек</dt><dd>Товары и доставка: сначала сумма каждого доставленного заказа, затем среднее по заказам.</dd><dt>Повторность площадки</dt><dd>Все статусы. Один покупатель с минимум двумя разными заказами внутри периода считается повторным. Это не когортное удержание.</dd><dt>Возвращение к продавцу</dt><dd>Только доставленные заказы одного продавца. Оба заказа должны попадать в выбранный период.</dd><dt>Период и доли</dt><dd>Дата оформления без сдвига часового пояса. Средние, проценты и уникальных покупателей нельзя складывать. Один заказ может содержать товары нескольких продавцов.</dd><dt>Источник</dt><dd>{meta ? `${meta.source_label}. Снимок ${dateLabel(meta.exported_at)}. Валюта: ${currency}.` : 'Данные пока не подключены.'}</dd><dt>Доступность результатов</dt><dd>Сохранённые SQL-ответы показываются как есть. Подробный JSON включает пересчёт базовых отчётов. Для новых вопросов можно загрузить CSV; его значения не объявляются проверенными SQL-моделью автоматически.</dd></dl></dialog>
  </>;
}

function PageHeading({ title, description }: { title: string; description: string }) { return <div className="page-heading"><div><h1>{title}</h1><p>{description}</p></div></div>; }
function PendingFeature({ text }: { text: string }) { return <div className="pending"><strong>Расчёт ещё не подключён</strong><p>{text}</p></div>; }
function KeyValues({ name, rows }: { name: string; rows: Cell[][] }) { return <DataTable name={name} headers={['Показатель', 'Значение']} rows={rows} numeric={[1]} />; }
function DataTable({ name, headers, rows, numeric = [], empty = 'Нет подходящих записей' }: { name: string; headers: string[]; rows: Cell[][]; numeric?: number[]; empty?: string }) {
  const [page, setPage] = useState(1); const [sort, setSort] = useState<{ col: number; descending: boolean } | null>(null);
  useEffect(() => { setPage(1); }, [rows]);
  const sorted = useMemo(() => !sort ? rows : [...rows].sort((a, b) => {
    const value = (c: Cell) => typeof c === 'object' && c ? c.id : String(c ?? '');
    const x = value(a[sort.col]), y = value(b[sort.col]); const xn = Number(x.replace(/[\s\u00a0\u202f%]/g, '').replace(',', '.')), yn = Number(y.replace(/[\s\u00a0\u202f%]/g, '').replace(',', '.'));
    const result = numeric.includes(sort.col) && Number.isFinite(xn) && Number.isFinite(yn) ? xn - yn : x.localeCompare(y, 'ru', { numeric: true }); return sort.descending ? -result : result;
  }), [rows, sort, numeric]);
  const pages = Math.max(1, Math.ceil(sorted.length / 15)); const current = Math.min(page, pages);
  return <div className="data-table"><div className="table-actions"><span>Строк: {count(rows.length)}</span><button className="text-button" disabled={!rows.length} onClick={() => downloadCsv(`${name}.csv`, headers, sorted.map(row => row.map(c => typeof c === 'object' && c ? c.id : c)))}>Скачать CSV</button></div><div className="table-scroll"><table><caption className="sr-only">{name}</caption><thead><tr>{headers.map((h, i) => <th key={i} className={numeric.includes(i) ? 'numeric' : ''} aria-sort={sort?.col === i ? sort.descending ? 'descending' : 'ascending' : 'none'}><button onClick={() => { setSort(s => ({ col: i, descending: s?.col === i ? !s.descending : false })); setPage(1); }}>{h}{sort?.col === i ? sort.descending ? ' ↓' : ' ↑' : ''}</button></th>)}</tr></thead><tbody>{sorted.slice((current - 1) * 15, current * 15).map((row, i) => <tr key={i}>{row.map((c, j) => <td className={numeric.includes(j) ? 'numeric' : ''} key={j}>{typeof c === 'object' && c ? <CopyId id={c.id} /> : c ?? '—'}</td>)}</tr>)}{!rows.length && <tr><td colSpan={headers.length} className="empty-cell">{empty}</td></tr>}</tbody></table></div>{pages > 1 && <div className="pagination"><span>Страница {current} из {pages}</span><div><button className="button" disabled={current === 1} onClick={() => setPage(current - 1)}>Назад</button><button className="button" disabled={current === pages} onClick={() => setPage(current + 1)}>Далее</button></div></div>}</div>;
}
function SellerProfile({ id, ix, summary, currency }: { id: string; ix: Index | null; summary?: SellerRow; currency: string }) {
  const result = useMemo(() => {
    if (!ix) return summary ?? null;
    const seller = ix.sellers.get(id); if (!seller) return null;
    let revenue = 0, units = 0; const orders = new Set<string>();
    for (const i of ix.deliveredItems) if (i.seller_id === id) { revenue += i.price_cents; units++; orders.add(i.order_id); }
    return { ...seller, revenue, units, orders: orders.size };
  }, [id, ix, summary]);
  if (!result) return <div className="empty">Продавец не найден.</div>;
  return <><p className="seller-id">ID: <CopyId id={id} /></p><KeyValues name="Профиль продавца" rows={[
    ['Город / штат продавца', `${result.city ?? 'Неизвестно'} / ${result.state ?? '—'}`], ['Выручка от товаров', `${money(result.revenue)} ${currency}`], ['Доставленные заказы', count(result.orders)], ['Проданные единицы', count(result.units)],
  ]} /><p className="source-note">Показатели за весь снимок. Подробные товары, категории и динамика профиля будут подключены после готовности соответствующей выгрузки.</p></>;
}
function CancellationTable({ ix, currency }: { ix: Index; currency: string }) {
  const rows = ['canceled', 'unavailable'].map(status => {
    let orders = 0, known = 0, revenue = 0;
    for (const o of ix.data.orders) if (o.status === status) { orders++; const total = ix.totals.get(o.order_id); if (total) { known++; revenue += total.revenue; } }
    return [`${STATUS_LABELS[status]} (${status})`, count(orders), percent(ix.data.orders.length ? orders / ix.data.orders.length : null), known ? `${money(revenue)} ${currency}` : 'Неизвестно', `${known} из ${orders}`];
  });
  return <DataTable name="Отмены и недоступность" headers={['Статус', 'Заказы', 'Доля всех заказов', 'Стоимость известных позиций', 'Покрытие']} rows={rows} numeric={[1, 2, 3]} />;
}
function SellerRepeat({ ix, id, range }: { ix: Index; id: string; range: Range }) {
  const stats = useMemo<Buyers>(() => {
    const buyers = new Map<string, Set<string>>();
    for (const i of ix.deliveredItems) if (i.seller_id === id) { const o = ix.orders.get(i.order_id)!; if (inRange(o.purchased_at, range)) { const set = buyers.get(o.buyer_id) ?? new Set<string>(); set.add(o.order_id); buyers.set(o.buyer_id, set); } }
    return { total: buyers.size, repeat: [...buyers.values()].filter(s => s.size >= 2).length };
  }, [ix, id, range]);
  return <KeyValues name="Возвращаются к продавцу" rows={[
    ['Покупателей с доставленным заказом', count(stats.total)], ['Покупателей минимум с двумя заказами', count(stats.repeat)], ['Доля повторных покупателей продавца', percent(stats.total ? stats.repeat / stats.total : null)],
  ]} />;
}
