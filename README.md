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

## Google Sheetsの準備

1. Google Spreadsheetを作成します。
2. 「拡張機能」→「Apps Script」を開き、`google-apps-script/Code.gs` の内容を貼り付けます。
3. Apps Scriptの「プロジェクトの設定」→「スクリプト プロパティ」に `LUZE_API_TOKEN` を追加し、十分に長いランダム値を設定します。
4. 「デプロイ」→「新しいデプロイ」→「ウェブアプリ」を選び、アクセスできるユーザーを設定します。
5. ウェブアプリURL、Spreadsheet URL、同じAPI TokenをLuzeの設定画面へ入力します。
6. 「接続テスト」を実行します。

Sheetsへの書き込みは `Luze ID` をキーに更新されるため、同じ月を再実行しても二重登録されません。

## データとセキュリティ

- 月次入力・判断履歴・設定はMac内に保存します。
- Apps Script API TokenはmacOS Keychainに保存します。
- Luzeからメールを送信しません。本文のコピーとGmail作成画面の表示のみ行います。
- Dropbox APIは使わず、ユーザーが選択したローカル同期フォルダだけを参照します。
