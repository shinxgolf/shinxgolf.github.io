# TRACE 構築手順書（Runbook）

> 対象：Power Apps 初〜中級者・1人開発
> 環境：Microsoft 365 Business Basic + Copilot for Microsoft 365
> ゴール：6月末の事業推進会議で「動くもの」をデモする
> 関連：設計プラン `~/.claude/plans/concurrent-popping-wozniak.md` / プロトタイプ `TRACE/prototype/index.html`

---

## 0. 全体像

```
SharePoint（データ） → Power Apps（UI） → Power Automate（自動化・AI・通知）
```

- 5リスト：仲介業者 / 既存顧客 / 案件 / 訪問履歴 / 設定
- 2モード：営業（スマホ）/ マネジメント（PC）
- AI：テキスト→Copilot要約・メール下書き（音声はMVPではスタブ）
- 状態モデル：通常 / 未割当（担当空欄）/ 休眠 / 対応NG
- 担当者管理：1件変更・一括移管・未割当プール（手挙げ引き取り）
- 地図／ついで訪問：**優先度「後」。本MVPには含めず後フェーズ**（住所＋Azure Maps）

各ステップに ☑ 完了チェックを付けながら進めること。

---

## Week 1 — 技術検証 ＋ 基盤構築

### Day 1〜2：技術検証スプリント（最重要・ここで作るか諦めるかを決める）

この2日間の検証結果で、後続の作り方が決まる。先に必ず潰すこと。

#### 検証① Copilot/Power Automate でテキスト要約ができるか
1. [make.powerautomate.com](https://make.powerautomate.com) を開く
2. 「インスタント クラウド フロー」を新規作成
3. アクション検索で「AI」系コネクタを確認：
   - `AI Builder`（GPT プロンプト）が使えるか → **Premium / AI Builder クレジット要否を確認**
   - 使えない場合：HTTP アクションで Azure OpenAI を叩く（別途 Azure 契約が必要）
4. **結論を出す**：
   - ◯ 使える → テキスト要約を本実装
   - × 使えない → MVPは「要約済みの固定文を返すスタブ」でデモ（プロトタイプ同様）

> 📌 判定基準：追加コストなしで動かなければ MVP はスタブ。経営会議では「本番では Azure OpenAI 連携で実現」と説明する。

#### 検証② Outlook 下書き保存ができるか
1. Power Automate で「Office 365 Outlook」コネクタ（**標準コネクタ**）を確認
2. `下書きの作成` または `メールの送信(V2)`＋下書きフラグ を検証
3. 不可なら **フォールバック**：PC版で本文テキストを生成して画面表示 → コピーして手動貼り付け

#### 検証③ 音声録音 → Power Automate 連携
1. Power Apps の `Microphone` コントロールで録音 → `画像/音声` を Power Automate に渡せるか
2. ほぼ確実に追加サービスが必要 → **MVPは録音ボタンUIのみ用意し、処理はスタブ**で割り切る

☑ Day 1-2 完了条件：①②③それぞれ「本実装 or スタブ」の判断が確定している

---

### Day 3：SharePoint リスト構築

1. SharePoint チームサイトを作成（例：`/sites/TRACE`）
2. PnP PowerShell でリストを自動作成：
   ```powershell
   Install-Module PnP.PowerShell -Scope CurrentUser
   pwsh ./scripts/Provision-TRACE-Lists.ps1 `
     -SiteUrl "https://<テナント>.sharepoint.com/sites/TRACE" `
     -DataPath "../demo-data"
   ```
   → 5リスト作成＋インデックス設定＋デモデータ投入まで自動
3. 手動で作る場合は `runbook/列定義一覧` 末尾の表を参照

☑ 完了条件：5リストが作成され、デモデータが入っている

### Day 3（続き）：委任問題の確認
1. Power Apps Studio で新規キャンバスアプリ（電話レイアウト）を作成
2. SharePoint コネクタで `TRACE_Customers` を接続
3. ギャラリーに `Filter(TRACE_Customers, DaysSinceContact > 180)` を設定
4. **委任の警告（青い下線）が出ないこと**を確認
   - 出る場合：`DateDiff` を使わず、`DaysSinceContact`（数値列）でフィルタする設計を徹底
   - 日付計算は Power Automate（毎朝バッチ）で `DaysSinceContact` を更新して回避

☑ 完了条件：500件規模で委任エラーなくフィルタできる

### Day 4〜5：ホーム＋仲介業者画面
1. **ボトムナビ**：画面下部に `Container` を置き、4つの `Button`（ホーム/仲介/顧客/検索）を配置。`変数 navSelected` で表示画面を切替（プロトタイプの挙動を再現）
2. **ホーム画面**：
   - 上部に「＋訪問を記録する」ボタン（後でモーダルに接続）
   - TODAY ギャラリー：`Filter(TRACE_Customers, NextFollowDate <= Today() && !IsHandling)`
   - ALERT ギャラリー：`AlertStatus in ["黄","赤"]`
3. **仲介業者一覧**：`SortByColumns(Filter(TRACE_Intermediaries, IsActive), "DaysSinceContact", Descending)`
   - アラート色：`DaysSinceContact >= 60` で黄ボーダー

☑ 完了条件：実データでアラートが色分け表示される

---

## Week 2 — コア機能

### 訪問記録モーダル
1. 全画面オーバーレイの `Container`（背景は半透明矩形で近似）
2. 相手検索 → 種別4択（アポ/ついで/電話/メモ）→ 日時（既定 `Now()`・編集可）→ テキスト入力
3. 保存：`Patch(TRACE_VisitHistory, Defaults(...), {...})`
4. 保存ボタン押下時にローディング表示、失敗時はエラートースト（`IfError` で捕捉）

### 詳細画面（タブ切替）
1. プロフ/案件/履歴の3タブを `変数 detailTab` で切替
2. 案件：`Filter(TRACE_Cases, BrokerName = selected.Title)`
3. 履歴：`Filter(TRACE_VisitHistory, RelatedId = selected.ID)` を時系列表示
4. 各履歴に `⋮` → 編集・削除（削除後は最終接触日を再計算 → Power Automate）
5. **担当者行**：`AssignedTo` を表示し「変更」で People Picker から選び直し → `Patch`
6. **状態バッジ**：`Status` が「対応NG」なら赤警告を最上部に表示し、訪問記録・引き取りボタンを無効化（`DisplayMode.Disabled`）。「休眠」はグレーバッジ＋「復活」ボタン

### 既存顧客一覧・検索
- 顧客一覧：`IsHandling` が true のものはアラート一覧から除外
- 検索：仲介・顧客を横断検索（種別フィルタ付き）

### Power Automate（4本）
1. **最終接触日更新**：`TRACE_VisitHistory` 作成時トリガー → RelatedId の `LastContactDate` を更新
2. **毎朝アラート計算**（7:00）：全レコードの `DaysSinceContact` と `AlertStatus` を再計算
3. **マネージャー通知**（8:00）：アラート対象をマネージャーへ Teams 送信
4. **営業通知**（8:30）：担当者ごとの本日フォロー予定を Teams 個別送信

☑ Week2 完了条件：登録〜記録〜アラート〜通知が一気通貫で動く

---

## Week 3 — AI機能・ダッシュボード・仕上げ

### 前半
1. **AI要約・提案**：Week1判定に従い本実装 or スタブ（プロトタイプの提案UIを再現）
2. **メール下書き**：本実装 or PC版「文章生成→コピー」フォールバック
3. **マネジメントダッシュボード**：
   - KPIカード（訪問件数・未フォロー・黄/赤・**⚠️担当者なし**）
   - 担当者カード（未フォロー件数順）
   - 月別推移グラフ（`Chart` コントロール）・紹介ランキング
   - 期間フィルタ（今月/先月/四半期/年間）
4. **担当者管理**：
   - 1件変更（詳細画面）
   - **一括移管**：マネジメントで「担当者A→B」を選び、`Filter(... AssignedTo=A)` を `Patch` で一括更新（Power Automate or アプリ内 `ForAll`）
   - **未割当プール**：`Filter(リスト, Status="通常" && IsBlank(AssignedTo))` を「今なら取れる相手」として表示。営業が「引き取る」→ 自分を `Patch`
   - 割当候補の提案（任意・後回し可）：エリア／最後に接触した人／担当件数の偏りでサジェスト
5. **状態モデル**：`Status`（通常/休眠/対応NG）。一覧・アラートは `Status="通常"` のみ対象。休眠/対応NGは除外、対応NGは検索結果で赤警告
6. **設定画面**：`TRACE_Settings` を編集（週次報告の曜日・時刻、アラート閾値）
7. **週次報告フロー**：毎日実行→設定値と照合→該当時のみ送信（既定 火曜13:00）
8. **訪問記録 編集・削除**

> 📍 **地図／ついで訪問は本MVPに含めない**（優先度：後）。後フェーズで Address→緯度経度のジオコーディング（Power Automate＋Azure Maps・無料枠）＋ Power Apps 地図コントロールで「現在地の近くの要フォロー相手」を実装する。リスト設計には Address/Latitude/Longitude 列を先に入れてあるので、後から地図を足すだけで済む。

### 後半（新機能追加禁止・固める期間）
1. デモシナリオを固定（後述）
2. デモデータを会議映え用に微調整
3. バグ修正のみ
4. 役員資料に「将来ロードマップ（音声全自動化・Kintone連携）」を明記

---

## デモシナリオ（会議で見せる順番）

1. **課題提示**：マネジメントモードで「未フォロー◯件・赤アラート◯件」を見せる（＝現状の機会損失）
2. **営業モード**：スマホ画面で「訪問を記録」→ 種別選択 → テキスト → ✨AI提案 → 保存（30秒）
3. **AIの価値**：詳細画面で「メール下書き作成」→ 趣味・履歴を反映した文面が一瞬で生成
4. **マネジメント**：担当者別カード・ランキング・週次報告（火曜13:00に自動送信）を見せる
5. **将来像**：音声ワンボタン全自動・Kintoneスケジュール連携を口頭で提示

---

## つまずきポイント早見表

| 症状 | 原因 | 対処 |
|---|---|---|
| ギャラリーに青い下線（委任警告） | `DateDiff` 等の非委任関数 | `DaysSinceContact` 数値列でフィルタ |
| 「89日未接触」がずれる | SharePoint日付がUTC保存 | `DateAdd` でローカル補正 or バッチ計算に統一 |
| AIコネクタが使えない | Premium/AI Builderクレジット未付与 | MVPはスタブで割り切る |
| メール下書きが作れない | Graph APIがPremium扱い | Outlook標準コネクタ or PC版コピー方式 |
| 通知が来ない | フロー所有者の権限/接続切れ | サービスアカウントで所有、接続を再認証 |
| 5000件で一覧が出ない | リストビューしきい値 | フィルタ列にインデックス設定 |

---

## 列定義一覧（手動作成する場合の参照）

→ `scripts/Provision-TRACE-Lists.ps1` 内の `Add-Field` 呼び出しが正本。
各リストの列名・型・インデックス設定はスクリプトを参照すること。
