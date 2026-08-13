const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');

class MockRange {
  constructor(sheet, row, column, rowCount, columnCount) {
    this.sheet = sheet;
    this.row = row;
    this.column = column;
    this.rowCount = rowCount;
    this.columnCount = columnCount;
  }
  getDisplayValues() { return this.getValues().map(row => row.map(value => String(value ?? ''))); }
  getValues() {
    return Array.from({ length: this.rowCount }, (_, rowIndex) =>
      Array.from({ length: this.columnCount }, (_, columnIndex) =>
        this.sheet.rows[this.row - 1 + rowIndex]?.[this.column - 1 + columnIndex] ?? ''
      )
    );
  }
  setValues(values) {
    values.forEach((row, rowIndex) => {
      const targetIndex = this.row - 1 + rowIndex;
      while (this.sheet.rows.length <= targetIndex) this.sheet.rows.push([]);
      row.forEach((value, columnIndex) => {
        this.sheet.rows[targetIndex][this.column - 1 + columnIndex] = value;
      });
    });
    return this;
  }
  setFontWeight() { return this; }
  setBackground() { return this; }
  setNumberFormat() { return this; }
}

class MockSheet {
  constructor(name) { this.name = name; this.rows = []; }
  getLastRow() { return this.rows.length; }
  appendRow(row) { this.rows.push([...row]); }
  getRange(row, column, rowCount, columnCount) {
    if (typeof row === 'string') return new MockRange(this, 1, 1, Math.max(this.rows.length, 1), 1);
    return new MockRange(this, row, column, rowCount, columnCount);
  }
  deleteRow(rowNumber) { this.rows.splice(rowNumber - 1, 1); }
  setFrozenRows() {}
  setColumnWidth() {}
  hideColumns() {}
}

class MockSpreadsheet {
  constructor(id = '1Ng1Q4JA9C8thFdKn4zBWertpcOWmH4Tk6KW2w28Pu0A') {
    this.id = id;
    this.sheets = new Map();
  }
  getId() { return this.id; }
  getSheetByName(name) { return this.sheets.get(name) || null; }
  insertSheet(name) {
    const sheet = new MockSheet(name);
    this.sheets.set(name, sheet);
    return sheet;
  }
}

function makeRuntime(spreadsheetID) {
  const spreadsheet = new MockSpreadsheet(spreadsheetID);
  const scriptProperties = new Map([['LUZE_API_TOKEN', 'test-secret']]);
  const context = vm.createContext({
    console,
    Date,
    JSON,
    Number,
    String,
    RegExp,
    PropertiesService: {
      getScriptProperties: () => ({ getProperty: key => scriptProperties.get(key) || null })
    },
    LockService: {
      getDocumentLock: () => ({ waitLock() {}, releaseLock() {} })
    },
    SpreadsheetApp: { getActiveSpreadsheet: () => spreadsheet },
    ContentService: {
      MimeType: { JSON: 'json' },
      createTextOutput: content => ({
        content,
        setMimeType() { return this; },
        getContent() { return this.content; }
      })
    }
  });
  const source = fs.readFileSync(path.join(__dirname, 'Code.gs'), 'utf8');
  vm.runInContext(source, context, { filename: 'Code.gs' });
  return {
    spreadsheet,
    post(body) {
      const raw = typeof body === 'string' ? body : JSON.stringify(body);
      return JSON.parse(context.doPost({ postData: { contents: raw } }).getContent());
    }
  };
}

function row(overrides = {}) {
  return {
    stableID: 'luze_v2_row_1',
    date: '2026-07-31',
    company: '業務委託A',
    content: '業務委託',
    amount: 470000,
    source: 'monthlyInput',
    ...overrides
  };
}

function request(payload, overrides = {}) {
  return {
    apiVersion: 2,
    action: 'syncMonth',
    token: 'test-secret',
    payload,
    ...overrides
  };
}

function payload(incomes = [], expenses = []) {
  return { apiVersion: 2, month: '2026-07', incomes, expenses };
}

test('health succeeds without modifying sheets', () => {
  const runtime = makeRuntime();
  const response = runtime.post({ apiVersion: 2, action: 'health', token: 'test-secret' });
  assert.equal(response.ok, true);
  assert.equal(response.spreadsheetID, '1Ng1Q4JA9C8thFdKn4zBWertpcOWmH4Tk6KW2w28Pu0A');
  assert.equal(runtime.spreadsheet.sheets.size, 0);
});

test('invalid token is rejected', () => {
  const runtime = makeRuntime();
  const response = runtime.post(request(payload(), { token: 'wrong' }));
  assert.deepEqual(response, { ok: false, error: 'unauthorized' });
});

test('a different spreadsheet is rejected before authentication', () => {
  const runtime = makeRuntime('production-spreadsheet-id');
  const response = runtime.post({ apiVersion: 2, action: 'health', token: 'test-secret' });
  assert.deepEqual(response, { ok: false, error: 'spreadsheet_not_allowed' });
});

test('missing stableID is inserted', () => {
  const runtime = makeRuntime();
  const response = runtime.post(request(payload([row()])));
  assert.equal(response.income.inserted, 1);
  assert.equal(runtime.spreadsheet.getSheetByName('収入').rows.length, 2);
});

test('identical payload is skipped', () => {
  const runtime = makeRuntime();
  runtime.post(request(payload([row()])));
  const response = runtime.post(request(payload([row()])));
  assert.equal(response.income.skipped, 1);
  assert.equal(response.income.updated, 0);
});

test('amount change updates the same stableID', () => {
  const runtime = makeRuntime();
  runtime.post(request(payload([row()])));
  const response = runtime.post(request(payload([row({ amount: 480000 })])));
  assert.equal(response.income.updated, 1);
  assert.equal(runtime.spreadsheet.getSheetByName('収入').rows[1][3], 480000);
});

test('content change updates the same stableID', () => {
  const runtime = makeRuntime();
  runtime.post(request(payload([row()])));
  const response = runtime.post(request(payload([row({ content: '追加業務' })])));
  assert.equal(response.income.updated, 1);
  assert.equal(runtime.spreadsheet.getSheetByName('収入').rows[1][2], '追加業務');
});

test('new stableID inserts only the new row', () => {
  const runtime = makeRuntime();
  runtime.post(request(payload([row()])));
  const response = runtime.post(request(payload([row(), row({ stableID: 'luze_v2_row_2', company: '出版収入' })])));
  assert.equal(response.income.inserted, 1);
  assert.equal(response.income.skipped, 1);
});

test('empty payload is safe', () => {
  const runtime = makeRuntime();
  const response = runtime.post(request(payload()));
  assert.deepEqual(response.income, { inserted: 0, updated: 0, skipped: 0, deleted: 0 });
  assert.deepEqual(response.expense, { inserted: 0, updated: 0, skipped: 0, deleted: 0 });
});

test('invalid apiVersion is rejected', () => {
  const runtime = makeRuntime();
  assert.equal(runtime.post(request(payload(), { apiVersion: 1 })).error, 'invalid_api_version');
  assert.equal(runtime.post(request({ ...payload(), apiVersion: 1 })).error, 'invalid_api_version');
});

test('malformed JSON returns JSON error', () => {
  const runtime = makeRuntime();
  assert.deepEqual(runtime.post('{bad'), { ok: false, error: 'malformed_json' });
});

test('partial retry is idempotent', () => {
  const runtime = makeRuntime();
  runtime.post(request(payload([row()], [])));
  const expense = row({ stableID: 'luze_v2_expense_1', company: 'Adobe', amount: 1180, source: 'cardStatement' });
  const recovered = runtime.post(request(payload([row()], [expense])));
  assert.equal(recovered.income.skipped, 1);
  assert.equal(recovered.expense.inserted, 1);
  const retried = runtime.post(request(payload([row()], [expense])));
  assert.equal(retried.income.skipped, 1);
  assert.equal(retried.expense.skipped, 1);
});

test('rows removed from a month payload are reconciled', () => {
  const runtime = makeRuntime();
  const expense = row({ stableID: 'luze_v2_expense_1', company: 'Adobe', amount: 1180, source: 'cardStatement' });
  runtime.post(request(payload([], [expense])));
  const response = runtime.post(request(payload()));
  assert.equal(response.expense.deleted, 1);
  assert.equal(runtime.spreadsheet.getSheetByName('支出').rows.length, 1);
});
