import test from 'node:test';
import assert from 'node:assert/strict';
import { parseCsv, csvCell } from './csv.ts';

test('CSV сохраняет кавычки, запятые и переносы внутри ячеек', () => {
  const r = parseCsv('\uFEFFdate,price,note\r\n2018-01-01,12.50,"текст, с запятой"\r\n2018-01-02,13,"две\nстроки и ""кавычки"""\r\n', '06_prices.csv');
  assert.equal(r.rows.length, 2);
  assert.equal(r.rows[0][2], 'текст, с запятой');
  assert.equal(r.rows[1][2], 'две\nстроки и "кавычки"');
  assert.equal(csvCell('12.50', 'price'), '12,5');
});
test('CSV поддерживает точку с запятой и блокирует испорченные строки', () => {
  assert.deepEqual(parseCsv('state;orders\nSP;500\n', '07.csv').rows, [['SP', '500']]);
  assert.throws(() => parseCsv('a,b\n"x,y', 'x.csv'), /кавычка/);
  assert.throws(() => parseCsv('a,b\nx\n', 'x.csv'), /столбцов/);
  assert.throws(() => parseCsv('a,a\nx,y\n', 'x.csv'), /заголовки/);
  assert.equal(csvCell('00012345678901234567', 'product_id'), '00012345678901234567');
});
