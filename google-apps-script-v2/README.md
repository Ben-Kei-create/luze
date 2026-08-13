# Luze Spreadsheet API v2 setup

Milestone 4B uses a dedicated test Spreadsheet. Do not deploy this against the production accounting workbook until its acceptance tests pass.

## Workbook structure

The v2 template uses two year-round sheets: `収入` and `支出`. Each sheet has four visible columns:

1. 日付
2. 会社
3. 内容
4. 金額

The script creates and hides management columns for `stableID`, `source`, `対象月`, `更新日時`, and `contentSignature`. A year-round layout avoids creating and maintaining new tabs every month; users can filter the date or target-month column when needed.

## Setup

1. Copy the dedicated Luze v2 template, which contains `収入` and `支出` sheets.
2. Open **Extensions → Apps Script** and replace `Code.gs` with this directory's `Code.gs`.
3. In **Project Settings → Script properties**, create `LUZE_API_TOKEN` with a long random value. Never store this token in a sheet cell.
4. Before deploying a different test workbook, change `LUZE_ALLOWED_SPREADSHEET_ID_` to that workbook's ID. The Milestone 4B source is intentionally pinned to the accepted dedicated test Spreadsheet and rejects every other ID.
5. Deploy as a Web App, executing as the owner. Luze uses token authentication and the server-side Spreadsheet ID allowlist.
6. In Luze Settings, keep the environment on `テスト専用`, then enter the Spreadsheet URL, Web App URL, and the same token.
7. Run **接続テスト**. This performs `health` only and does not change rows.
8. Review the export preview and explicitly choose **テストSpreadsheetへ同期**.

## API v2

- `health`: validates the token and API version without changing data.
- `syncMonth`: reconciles the supplied month into the year-round `収入` and `支出` sheets.

For each `stableID`, `syncMonth` inserts a missing row, skips an identical row, or updates a changed row. Rows previously managed by Luze for the same month but absent from the new payload are removed, so changing a card decision from expense to pending/excluded is reflected on the next sync. Retrying the same payload is safe.

The existing v1 script at `google-apps-script/Code.gs` is a separate contract and must not be replaced in an existing production workflow.
