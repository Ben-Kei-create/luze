/**
 * Luze v0.1 Google Apps Script endpoint.
 * Script Properties に LUZE_API_TOKEN を登録してからウェブアプリとしてデプロイしてください。
 */
function doPost(e) {
  try {
    const payload = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    const expected = PropertiesService.getScriptProperties().getProperty('LUZE_API_TOKEN');
    if (!expected || payload.token !== expected) return json_({ ok: false, error: 'unauthorized' });
    if (payload.action === 'ping') return json_({ ok: true });
    if (payload.action !== 'upsertMonth') return json_({ ok: false, error: 'unknown_action' });

    const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
    const sheet = spreadsheet.getSheetByName('Luze') || spreadsheet.insertSheet('Luze');
    ensureHeader_(sheet);

    const rows = [];
    const month = String(payload.month || '');
    const income = payload.income || {};
    rows.push(row_(month + ':income:techBiz', month, '収入', 'TechBiz', Number(income.techBiz || 0), ''));
    rows.push(row_(month + ':income:helloLinks', month, '収入', 'HelloLinks', Number(income.helloLinks || 0), ''));
    rows.push(row_(month + ':income:kindle', month, '収入', 'Kindle', Number(income.kindle || 0), ''));
    const fixed = payload.fixedExpenses || {};
    rows.push(row_(month + ':fixed:rent', month, '支出', '家賃', Number(fixed.rent || 0), '固定費'));
    rows.push(row_(month + ':fixed:transport', month, '支出', '交通費', Number(fixed.transport || 0), '交通費'));
    (payload.transactions || []).forEach(function(tx) {
      rows.push([String(tx.id), month, '支出', String(tx.merchant || ''), Number(tx.amount || 0), String(tx.purpose || ''), String(tx.date || ''), new Date()]);
    });

    const existing = existingRows_(sheet);
    rows.forEach(function(row) {
      const index = existing[row[0]];
      if (index) sheet.getRange(index, 1, 1, row.length).setValues([row]);
      else { sheet.appendRow(row); existing[row[0]] = sheet.getLastRow(); }
    });
    return json_({ ok: true, count: rows.length });
  } catch (error) {
    return json_({ ok: false, error: String(error) });
  }
}

function row_(id, month, kind, merchant, amount, purpose) {
  return [id, month, kind, merchant, amount, purpose, '', new Date()];
}

function ensureHeader_(sheet) {
  if (sheet.getLastRow() === 0) sheet.appendRow(['Luze ID', '対象月', '区分', '加盟店・項目', '金額', '用途', '利用日', '更新日時']);
}

function existingRows_(sheet) {
  const result = {};
  if (sheet.getLastRow() < 2) return result;
  sheet.getRange(2, 1, sheet.getLastRow() - 1, 1).getValues().forEach(function(row, i) { if (row[0]) result[String(row[0])] = i + 2; });
  return result;
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}
