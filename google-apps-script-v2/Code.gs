/**
 * Luze Spreadsheet API v2.
 *
 * Bound to the Luze v2 template spreadsheet. Set LUZE_API_TOKEN in Script
 * Properties before deploying as a Web App. The token is never written to a
 * cell, response, or application log.
 */
const LUZE_API_VERSION_ = 2;
const LUZE_TOKEN_PROPERTY_ = 'LUZE_API_TOKEN';
const LUZE_ALLOWED_SPREADSHEET_ID_ = '1Ng1Q4JA9C8thFdKn4zBWertpcOWmH4Tk6KW2w28Pu0A';
const LUZE_SHEETS_ = { income: '収入', expense: '支出' };
const LUZE_HEADERS_ = ['日付', '会社', '内容', '金額', 'stableID', 'source', '対象月', '更新日時', 'contentSignature'];

function doPost(e) {
  try {
    const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
    if (!spreadsheet || spreadsheet.getId() !== LUZE_ALLOWED_SPREADSHEET_ID_) {
      return json_({ ok: false, error: 'spreadsheet_not_allowed' });
    }
    const request = parseRequest_(e);
    const expectedToken = PropertiesService.getScriptProperties().getProperty(LUZE_TOKEN_PROPERTY_);
    if (!expectedToken || request.token !== expectedToken) {
      return json_({ ok: false, error: 'unauthorized' });
    }
    if (Number(request.apiVersion) !== LUZE_API_VERSION_) {
      return json_({ ok: false, error: 'invalid_api_version' });
    }
    if (request.action === 'health') {
      return json_({
        ok: true,
        apiVersion: LUZE_API_VERSION_,
        spreadsheetID: spreadsheet.getId(),
        message: 'Luze Apps Script v2'
      });
    }
    if (request.action !== 'syncMonth') {
      return json_({ ok: false, error: 'unknown_action' });
    }

    const payload = validatePayload_(request.payload);
    const lock = LockService.getDocumentLock();
    lock.waitLock(30000);
    try {
      const income = syncSheet_(spreadsheet, LUZE_SHEETS_.income, payload.month, payload.incomes);
      const expense = syncSheet_(spreadsheet, LUZE_SHEETS_.expense, payload.month, payload.expenses);
      return json_({
        ok: true,
        spreadsheetID: spreadsheet.getId(),
        month: payload.month,
        income: income,
        expense: expense
      });
    } finally {
      lock.releaseLock();
    }
  } catch (error) {
    return json_({ ok: false, error: safeErrorCode_(error) });
  }
}

function parseRequest_(e) {
  const contents = e && e.postData && e.postData.contents;
  if (!contents) throw new Error('malformed_json');
  try {
    return JSON.parse(contents);
  } catch (_) {
    throw new Error('malformed_json');
  }
}

function validatePayload_(payload) {
  if (!payload || Number(payload.apiVersion) !== LUZE_API_VERSION_) throw new Error('invalid_api_version');
  if (!/^\d{4}-\d{2}$/.test(String(payload.month || ''))) throw new Error('invalid_month');
  if (!Array.isArray(payload.incomes) || !Array.isArray(payload.expenses)) throw new Error('invalid_payload');

  const ids = {};
  payload.incomes.concat(payload.expenses).forEach(function(row) {
    validateRow_(row, payload.month);
    if (ids[row.stableID]) throw new Error('duplicate_stable_id');
    ids[row.stableID] = true;
  });
  return payload;
}

function validateRow_(row, month) {
  if (!row || !String(row.stableID || '') || !/^\d{4}-\d{2}-\d{2}$/.test(String(row.date || ''))) {
    throw new Error('invalid_row');
  }
  if (!String(row.company || '').trim() || !String(row.content || '').trim()) throw new Error('invalid_row');
  if (!Number.isFinite(Number(row.amount)) || Number(row.amount) <= 0) throw new Error('invalid_row');
  if (!String(row.source || '').trim() || String(row.date).slice(0, 7) !== month) throw new Error('invalid_row');
}

function syncSheet_(spreadsheet, sheetName, month, incomingRows) {
  const sheet = ensureSheet_(spreadsheet, sheetName);
  const existing = existingRows_(sheet);
  const incomingIDs = {};
  const result = { inserted: 0, updated: 0, skipped: 0, deleted: 0 };

  incomingRows.forEach(function(row) {
    const id = String(row.stableID);
    const signature = contentSignature_(month, row);
    const values = sheetValues_(month, row, signature);
    incomingIDs[id] = true;
    if (!existing[id]) {
      sheet.appendRow(values);
      existing[id] = { rowNumber: sheet.getLastRow(), signature: signature, month: month };
      result.inserted += 1;
    } else if (existing[id].signature === signature) {
      result.skipped += 1;
    } else {
      sheet.getRange(existing[id].rowNumber, 1, 1, LUZE_HEADERS_.length).setValues([values]);
      result.updated += 1;
    }
  });

  const staleRowNumbers = Object.keys(existing)
    .filter(function(id) { return existing[id].month === month && !incomingIDs[id]; })
    .map(function(id) { return existing[id].rowNumber; })
    .sort(function(a, b) { return b - a; });
  staleRowNumbers.forEach(function(rowNumber) {
    sheet.deleteRow(rowNumber);
    result.deleted += 1;
  });
  return result;
}

function ensureSheet_(spreadsheet, sheetName) {
  const sheet = spreadsheet.getSheetByName(sheetName) || spreadsheet.insertSheet(sheetName);
  if (sheet.getLastRow() === 0) sheet.appendRow(LUZE_HEADERS_);
  const currentHeaders = sheet.getRange(1, 1, 1, LUZE_HEADERS_.length).getDisplayValues()[0];
  if (JSON.stringify(currentHeaders) !== JSON.stringify(LUZE_HEADERS_)) throw new Error('invalid_sheet_header');

  sheet.setFrozenRows(1);
  sheet.getRange(1, 1, 1, LUZE_HEADERS_.length)
    .setFontWeight('bold')
    .setBackground('#E8F0FE');
  sheet.setColumnWidth(1, 110);
  sheet.setColumnWidth(2, 220);
  sheet.setColumnWidth(3, 220);
  sheet.setColumnWidth(4, 110);
  sheet.getRange('A:A').setNumberFormat('yyyy-mm-dd');
  sheet.getRange('D:D').setNumberFormat('#,##0');
  sheet.hideColumns(5, 5);
  return sheet;
}

function existingRows_(sheet) {
  const result = {};
  if (sheet.getLastRow() < 2) return result;
  const values = sheet.getRange(2, 1, sheet.getLastRow() - 1, LUZE_HEADERS_.length).getValues();
  values.forEach(function(row, index) {
    const id = String(row[4] || '');
    if (id) result[id] = { rowNumber: index + 2, signature: String(row[8] || ''), month: String(row[6] || '') };
  });
  return result;
}

function sheetValues_(month, row, signature) {
  return [
    localDate_(String(row.date)),
    String(row.company),
    String(row.content),
    Number(row.amount),
    String(row.stableID),
    String(row.source),
    month,
    new Date(),
    signature
  ];
}

function contentSignature_(month, row) {
  return JSON.stringify([
    String(row.date),
    String(row.company),
    String(row.content),
    Number(row.amount),
    String(row.source),
    month
  ]);
}

function localDate_(value) {
  const parts = value.split('-').map(Number);
  return new Date(parts[0], parts[1] - 1, parts[2]);
}

function safeErrorCode_(error) {
  const allowed = [
    'malformed_json', 'invalid_api_version', 'invalid_month', 'invalid_payload',
    'invalid_row', 'duplicate_stable_id', 'invalid_sheet_header'
  ];
  const message = error && error.message ? String(error.message) : '';
  return allowed.indexOf(message) >= 0 ? message : 'internal_error';
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}
