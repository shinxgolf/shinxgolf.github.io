# TRACE — 構築・自動化キット

> Total Relationship & AI Customer Engine — ティーズブレインの顧客フォロー基盤（Power Apps）
> このフォルダは「設計・資料」＋「自動で展開するための道具」を1か所にまとめたものです。

---

## これは何？

営業の顧客フォローを「最終接触日」で見える化するアプリ **TRACE** を、
**できるだけ手作業を減らして** 会社の Microsoft 365 上に立ち上げるためのキットです。

アプリは3つの層でできています。層ごとに「自動化の度合い」が違います。

| 層 | 中身 | 自動化 | 担当ファイル |
|---|---|---|---|
| ① データ | SharePoint 5リスト＋サンプルデータ | ✅ **ワンコマンドで自動** | `scripts/Deploy-TRACE.ps1` |
| ② 画面 | Power Apps（スマホ／PC） | △ 半自動（ガイド＋完成見本） | `runbook/PowerApps-詳細ビルドガイド.md` / `prototype/index.html` |
| ③ 自動化 | Power Automate フロー7本（通知・週次報告 等） | △ 取り込み式（仕様は確定済み） | `runbook/PowerApps-詳細ビルドガイド.md`「9.」 |

> なぜ②③は「△」？ → Power Apps の画面はコードからの一発生成が壊れやすく、実テナントでの動作確認が要るためです。
> このキットは **「確実に自動化できる①を完全自動化」** し、②③は迷わず作れる材料を揃える方針です。

---

## まず実行する：①データ層をワンコマンドで

会社PC（Microsoft 365 にログインできる環境）で：

```powershell
# 1. 前提モジュール（初回のみ・Deploy が自動でやってくれる）
#    手動で入れる場合: Install-Module PnP.PowerShell -Scope CurrentUser

# 2. SharePoint チームサイトを先に1つ作っておく（例: /sites/TRACE）

# 3. ワンコマンド実行（TRACE/scripts/ の中で）
pwsh ./Deploy-TRACE.ps1 -SiteUrl "https://<テナント>.sharepoint.com/sites/TRACE"
```

これで **5リスト作成 → インデックス設定 → デモデータ投入** まで自動で終わります。

### 担当者（Person列）について大事なこと
デモデータの担当者は架空メール（`sato@ourcompany.example.jp` 等）です。実テナントには存在しないので、
そのままだと **全員「未割当」** として取り込まれます（これはこれで「未割当プール」機能のデモになります）。

実メンバーに割り当てたい場合は、どちらか：

- `demo-data/user-map.csv` に「架空メール → 実メール」を書く（正確に割り当て）
- `-DefaultAssignee "you@contoso.com"` を付けて全部を自分に寄せる（手早くデモ映え）

```powershell
pwsh ./Deploy-TRACE.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TRACE" -DefaultAssignee "you@contoso.com"
```

### 実運用前に必ず変更
- `TRACE_Settings` の **`ManagerEmails`** を実メールに（マネジメントモードの表示判定に使う）
- 週次報告の曜日・時刻（既定：火曜13:00）

---

## 次にやる：②画面 ③フロー

1. **画面**：`runbook/PowerApps-詳細ビルドガイド.md` の「11. 作る順番」に沿って実装。
   コピペできる Power Fx 数式が画面ごとに載っています。完成イメージは `prototype/index.html` をブラウザで開いて確認。
2. **フロー**：同ガイド「9. フロー」の7本。MVP優先は ①最終接触日更新／③④通知／⑤週次報告。
3. **AIの可否**：`runbook/TRACE-構築手順書.md` の「Week1 技術検証」で、Copilot要約・Outlook下書きが使えるか先に判定（不可ならスタブ）。

> プロトタイプはおまけで `https://<ユーザー名>.github.io/TRACE/prototype/` からスマホでも開けます（GitHub Pages）。

---

## フォルダ構成

```
TRACE/
├ README.md                      ← このファイル（最初に読む）
├ 引き継ぎ書-会社PC用.md          ← 背景・確定仕様（設計の正本）
├ scripts/
│  ├ Deploy-TRACE.ps1            ← ★ワンコマンド入口（前提チェック＋展開）
│  └ Provision-TRACE-Lists.ps1   ← リスト定義・データ取り込みの本体
├ demo-data/
│  ├ TRACE_*.csv                 ← サンプルデータ5種
│  └ user-map.csv               ← 担当者の「架空→実メール」対応表（任意）
├ runbook/
│  ├ PowerApps-詳細ビルドガイド.md ← 画面・フローの作り方（数式の正本）
│  ├ 画面づくり-コピペ手順.md       ← ★作る順に「1ステップ=1コピペ」で並べた手順書
│  └ TRACE-構築手順書.md          ← 3週間の進め方・つまずき早見表
├ prototype/index.html           ← 目指す完成形（動く見本）
├ proposal/                      ← 役員向け提案（pptx＋構成）
├ flows/                         ← Power Automate フロー7本の作成仕様（式入り）
│  ├ README.md / 01〜07 各フロー
└ docs/自動化の進め方.md          ← 何がどこまで自動化されるか（やさしい説明）
```

---

## 進捗

- [x] 資料・データ・スクリプトをリポジトリに集約
- [x] ①データ層：ワンコマンド展開（担当者マッピング・RelatedId 連結・全列取り込みに対応）
- [x] ③フロー：7本の作成仕様（式入り）を `flows/` に用意
- [x] ②画面：コピペ手順書 `runbook/画面づくり-コピペ手順.md` を整備
- [ ] ②画面：コード生成（`pac` ソース化）の検証 ※あなたのPCでの取り込み確認が前提
