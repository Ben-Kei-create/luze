# Luze

フリーランス・個人事業主向けの、月次経理準備をシンプルに進めるmacOSアプリです。会計ソフトではなく、収入入力、証憑確認、Vpass明細分類、Google Sheets反映、提出メール作成を一本化します。

## 動作環境

- macOS 15以降
- Xcode 16以降
- SwiftUI

## 起動

1. `luze.xcodeproj` をXcodeで開きます。
2. Scheme `luze` と実行先 `My Mac` を選択します。
3. Runします。

コマンドラインでの確認:

```sh
xcodebuild -project luze.xcodeproj -scheme luze -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Google Sheetsの準備（v2テスト環境）

1. 本番経理とは別のテスト用Google Spreadsheetを作成し、`収入`と`支出`の2シートを用意します。
2. 「拡張機能」→「Apps Script」を開き、`google-apps-script-v2/Code.gs` の内容を貼り付けます。
3. Apps Scriptの「プロジェクトの設定」→「スクリプト プロパティ」に `LUZE_API_TOKEN` を追加し、十分に長いランダム値を設定します。
4. 「デプロイ」→「新しいデプロイ」→「ウェブアプリ」を選び、アクセスできるユーザーを設定します。
5. Luzeの接続先が`テスト専用`であることを確認し、ウェブアプリURL、Spreadsheet URL、同じAPI Tokenを設定画面へ入力します。
6. 「接続テスト」を実行します。
7. 集計画面で内容をプレビューし、明示的に「テストSpreadsheetへ同期」を実行します。

v2は`stableID`を論理行IDとしてUPSERTします。未登録行はINSERT、内容が同じ行はSKIP、金額・内容等が変わった行はUPDATEされます。同じ月から削除されたLuze管理行も同期時に反映されるため、同じPayloadを再実行しても安全です。

既存の`google-apps-script/Code.gs`はPythonおよび本番フロー用のv1契約として維持しています。v2テスト環境へ置き換えたり、既存本番Sheetへデプロイしないでください。

## データとセキュリティ

- 月次入力・判断履歴・設定はMac内に保存します。
- Apps Script API TokenはmacOS Keychainに保存します。
- Luzeからメールを送信しません。本文のコピーとGmail作成画面の表示のみ行います。
- Dropbox APIは使わず、ユーザーが選択したローカル同期フォルダだけを参照します。
