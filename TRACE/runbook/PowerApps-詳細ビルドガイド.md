# TRACE Power Apps 詳細ビルドガイド

> 対象：キャンバスアプリ（電話レイアウト）＋ SharePoint ＋ Power Automate
> 前提：地図機能は後回し。MVP（仲介業者・既存顧客のフォロー管理＋担当者管理＋AI要約スタブ＋ダッシュボード）を作る
> データ規模：仲介業者〜100・既存顧客〜50（**全件が委任しきい値2000未満なので、委任警告は実質無視してよい**。将来拡大時のみ後述の対策）

---

## 0. 事前準備

1. SharePoint チームサイトに5リストを作成（`scripts/Provision-TRACE-Lists.ps1` を実行、またはガイド末尾の列表で手動作成）
2. [make.powerapps.com](https://make.powerapps.com) → 「アプリ」→「キャンバスアプリを新規作成」→ **電話レイアウト**
3. 左メニュー「データ」→ SharePoint コネクタを追加し、5リストすべてを接続
   - `TRACE_Intermediaries` / `TRACE_Customers` / `TRACE_Cases` / `TRACE_VisitHistory` / `TRACE_Settings`

---

## 1. アプリ共通設定（テーマ・初期化）

### App の OnStart に貼る（テーマ色と設定値の読み込み）

```powerappsfl
// ===== テーマ色（プロトタイプと一致）=====
Set(gPrimary, ColorValue("#0F1923"));
Set(gSurface, ColorValue("#1A2535"));
Set(gSurface2, ColorValue("#212F42"));
Set(gAccent,  ColorValue("#00D4FF"));
Set(gWarning, ColorValue("#FFB800"));
Set(gDanger,  ColorValue("#FF4444"));
Set(gSuccess, ColorValue("#00CC88"));
Set(gText,    ColorValue("#F0F4F8"));
Set(gSub,     ColorValue("#8899AA"));

// ===== ログインユーザー（マネジメント判定用）=====
Set(varMe, User().Email);
Set(varMyName, User().FullName);

// ===== 設定リストから閾値を読み込み（変更に強くする）=====
Set(varBrokerYellow,  Value(LookUp(TRACE_Settings, Title="BrokerAlertDays").SettingValue));
Set(varCustYellow,    Value(LookUp(TRACE_Settings, Title="CustomerAlertYellow").SettingValue));
Set(varCustRed,       Value(LookUp(TRACE_Settings, Title="CustomerAlertRed").SettingValue));

// ===== マネージャー判定 =====
Set(varIsManager, varMe in Split(LookUp(TRACE_Settings, Title="ManagerEmails").SettingValue, ",").Value);

// ===== 初期画面 =====
Set(varTab, "home");
```

> ⚠️ App.OnStart は「設定」→「機能」から `Navigate in App.OnStart` を切るのが推奨。代わりに最初の画面の OnVisible でも可。

### 背景

各スクリーンの `Fill` を `gPrimary` に。カードは四角形（角丸）に `gSurface` を使う。

---

## 2. ナビゲーション（ボトムナビ）

Power Apps にネイティブのボトムナビは無い。**各画面を実体として作り**、画面下部に共通のナビ行を置く。

### 方式A（推奨・シンプル）：画面ごとに作り Navigate で遷移
- スクリーン：`scrHome` `scrBrokers` `scrCustomers` `scrSearch` `scrDetail` `scrPool` `scrDash`
- 各画面の下部に水平コンテナ `cntNav`（高さ72・Fill `RGBA(20,30,42,.95)`）を置き、4つのボタンを配置

各ナビボタン（例：ホーム）
```powerappsfl
// OnSelect
Navigate(scrHome, ScreenTransition.None)
// Color（選択中をアクセント色に）
If(varTab="home", gAccent, gSub)
```
ボタン OnSelect で `Set(varTab,"home"); Navigate(scrHome)` のように varTab も更新。

> コンテナを1つ作って各画面にコピペでOK。後で「コンポーネント化」すると保守が楽。

---

## 3. ホーム画面（scrHome）

### CTA ボタン「＋ 訪問を記録する」
```powerappsfl
// OnSelect → 記録モーダルを開く
UpdateContext({locShowRecord:true, locRecType:"", locRecText:""})
```
（記録モーダルは scrHome 内のオーバーレイcontainer。`Visible = locShowRecord`）

### TODAY ギャラリー（次回フォロー日が今日以前）
ギャラリーの `Items`：
```powerappsfl
Filter(
  TRACE_Customers,
  Status.Value = "通常",
  IsHandling = false,
  !IsBlank(NextFollowDate),
  NextFollowDate <= Today()
)
```

### ALERT ギャラリー（放置されている相手・顧客＋仲介を横断）
2つのギャラリーに分けるのが簡単。**既存顧客アラート**：
```powerappsfl
SortByColumns(
  Filter(
    TRACE_Customers,
    Status.Value = "通常",
    IsHandling = false,
    DateDiff(LastContactDate, Today(), Days) >= varCustYellow
  ),
  "LastContactDate", Ascending   // 古い順＝放置が長い順
)
```
**仲介業者アラート**：
```powerappsfl
SortByColumns(
  Filter(
    TRACE_Intermediaries,
    Status.Value = "通常",
    DateDiff(LastContactDate, Today(), Days) >= varBrokerYellow
  ),
  "LastContactDate", Ascending
)
```

### アラート色（カード左ボーダー＝細い四角形の Fill）
顧客カード内の経過日数で色分け：
```powerappsfl
With({d: DateDiff(ThisItem.LastContactDate, Today(), Days)},
  If(d >= varCustRed, gDanger, d >= varCustYellow, gWarning, gSuccess)
)
```

### 「担当者なし」チップ（カード内ラベル）
```powerappsfl
// Visible
ThisItem.Status.Value="通常" && IsBlank(ThisItem.AssignedTo.Email)
// Text
"担当者なし"
```

### カードをタップ → 詳細へ
```powerappsfl
// ギャラリー OnSelect
Set(varSel, ThisItem); Set(varSelKind, "customer"); Set(varDetailTab,"prof");
Navigate(scrDetail)
```

---

## 4. 一覧画面（scrBrokers / scrCustomers）

### 仲介業者一覧 Items（休眠・対応NGを除外）
```powerappsfl
SortByColumns(
  Filter(TRACE_Intermediaries, Status.Value = "通常"),
  "LastContactDate", Ascending
)
```
フィルタタブ「要フォロー」用に、ボタンで `Set(varBFilter,"need")` を切り替え、Items を：
```powerappsfl
Filter(TRACE_Intermediaries,
  Status.Value="通常",
  varBFilter<>"need" || DateDiff(LastContactDate, Today(), Days) >= varBrokerYellow
)
```

### 既存顧客一覧 Items（案件対応中・休眠・対応NGを除外）
```powerappsfl
Filter(TRACE_Customers,
  Status.Value = "通常",
  IsHandling = false
)
```
並びはアラート重み順にしたい場合、`AddColumns` で重みを付けてソート：
```powerappsfl
SortByColumns(
  AddColumns(
    Filter(TRACE_Customers, Status.Value="通常", IsHandling=false),
    "wDays", DateDiff(LastContactDate, Today(), Days)
  ),
  "wDays", Descending
)
```

---

## 5. 詳細画面（scrDetail）

`varSel`（選択レコード）と `varSelKind`（"broker"/"customer"）を使う。

### 状態バッジ（ラベル Text）
```powerappsfl
Switch(true,
  varSel.Status.Value="対応NG", "⚠️ 対応NG",
  varSel.Status.Value="休眠", "休眠",
  varSelKind="customer" && varSel.IsHandling, "案件対応中",
  With({d:DateDiff(varSel.LastContactDate,Today(),Days)},
    If(d>=varCustRed,"赤 "&d&"日", d>=varCustYellow,"黄 "&d&"日","正常"))
)
```

### 対応NG 警告（赤バナー）と操作ブロック
- 警告ラベルの `Visible`：`varSel.Status.Value="対応NG"`
- 「訪問記録」「メール下書き」ボタンの `DisplayMode`：
```powerappsfl
If(varSel.Status.Value="対応NG", DisplayMode.Disabled, DisplayMode.Edit)
```

### 担当者行と「変更」
担当者表示：
```powerappsfl
If(IsBlank(varSel.AssignedTo.Email), "担当者なし", varSel.AssignedTo.DisplayName)
```
「変更」ボタン → People Picker（コンボボックス `cmbAssignee`、Items = `Office365Users.SearchUser({searchTerm:cmbAssignee.SearchText})`）を表示し、確定時に Patch：
```powerappsfl
Patch(
  If(varSelKind="broker", TRACE_Intermediaries, TRACE_Customers),
  varSel,
  { AssignedTo:
    { '@odata.type':"#Microsoft.Azure.Connectors.SharePoint.SPListExpandedUser",
      Claims: "i:0#.f|membership|" & cmbAssignee.Selected.Mail,
      DisplayName: cmbAssignee.Selected.DisplayName,
      Email: cmbAssignee.Selected.Mail
    }
  }
);
Set(varSel, LookUp(If(varSelKind="broker",TRACE_Intermediaries,TRACE_Customers), ID=varSel.ID));
Notify("担当を変更しました", NotificationType.Success)
```

### 「自分が引き取る」（未割当時）
ボタン Visible：`IsBlank(varSel.AssignedTo.Email) && varSel.Status.Value="通常"`
OnSelect：
```powerappsfl
Patch(
  If(varSelKind="broker", TRACE_Intermediaries, TRACE_Customers),
  varSel,
  { AssignedTo:
    { '@odata.type':"#Microsoft.Azure.Connectors.SharePoint.SPListExpandedUser",
      Claims: "i:0#.f|membership|" & varMe,
      DisplayName: varMyName, Email: varMe }
  }
);
Notify("あなたの担当になりました 🙌", NotificationType.Success);
Set(varSel, LookUp(If(varSelKind="broker",TRACE_Intermediaries,TRACE_Customers), ID=varSel.ID))
```

### タブ切替（プロフ／案件／履歴）
タブボタンで `Set(varDetailTab,"prof")`。各タブのコンテナ Visible = `varDetailTab="prof"` 等。

- 案件タブ Items：`Filter(TRACE_Cases, BrokerName = varSel.Name)`（仲介）／`Filter(TRACE_Cases, CustomerName = varSel.Title)`（顧客）
- 履歴タブ Items：
```powerappsfl
SortByColumns(
  Filter(TRACE_VisitHistory,
    RelatedType.Value = If(varSelKind="broker","仲介業者","既存顧客"),
    RelatedId = varSel.ID),
  "VisitDate", Descending
)
```

---

## 6. 訪問記録モーダル（scrHome 内オーバーレイ）

`Visible = locShowRecord` のコンテナ。中に：相手検索・種別4択・日時・本文・保存。

### 種別4択（4ボタン）
各ボタン OnSelect：`UpdateContext({locRecType:"訪問アポ"})`、選択中の枠色を `If(locRecType="訪問アポ",gAccent,gSub)`。

### 「記録して保存」→ Patch ＋ AI要約フロー呼び出し
```powerappsfl
// 1) 履歴を保存
Patch(TRACE_VisitHistory, Defaults(TRACE_VisitHistory),
  { Title: varSel.Title,
    RelatedType: {Value: If(varSelKind="broker","仲介業者","既存顧客")},
    RelatedId: varSel.ID,
    RelatedName: If(varSelKind="broker", varSel.Name, varSel.Title),
    VisitDate: Now(),
    VisitType: {Value: locRecType},
    RawText: locRecText
  }
);
// 2) AI要約フローを呼ぶ（Power Automate）。結果を提案として表示
Set(varAI, TRACE_Summarize.Run(locRecText));
UpdateContext({locShowRecord:false, locShowAI:true})
```
> AI要約が Week1検証で不可なら、`Set(varAI, {summary:"（要約スタブ）", nextFollow:DateAdd(Today(),90)})` の固定値スタブにする。

### 最終接触日の更新
- 簡単：上の Patch の後に対象レコードも更新
```powerappsfl
Patch(If(varSelKind="broker",TRACE_Intermediaries,TRACE_Customers), varSel, {LastContactDate: Now()})
```
- 堅牢：Power Automate（VisitHistory 作成トリガー）で更新（複数端末・整合性に強い／後述）

### AI提案パネル（locShowAI）
`varAI.summary` を表示。「次回フォロー日を適用」ボタン：
```powerappsfl
Patch(TRACE_Customers, varSel, {NextFollowDate: varAI.nextFollow});
Notify("更新しました", NotificationType.Success)
```

---

## 7. 未割当プール（scrPool）

### Items（未割当＝Status通常かつ担当空）
仲介・顧客を分けて2ギャラリー、または結合。仲介の例：
```powerappsfl
Filter(TRACE_Intermediaries, Status.Value="通常", IsBlank(AssignedTo.Email))
```
顧客：
```powerappsfl
Filter(TRACE_Customers, Status.Value="通常", IsBlank(AssignedTo.Email))
```
各カードに「自分が引き取る」（上記 claim と同じ Patch）と「休眠にする」：
```powerappsfl
Patch(TRACE_Intermediaries, ThisItem, {Status:{Value:"休眠"}});
Notify("休眠にしました", NotificationType.Success)
```

---

## 8. マネジメントダッシュボード（scrDash）

`scrDash` への遷移はマネジメント用ボタン（`Visible = varIsManager`）から。

### KPIカード（ラベルの Text）
```powerappsfl
// 黄アラート件数
CountRows(Filter(TRACE_Customers, Status.Value="通常", IsHandling=false,
  DateDiff(LastContactDate,Today(),Days)>=varCustYellow,
  DateDiff(LastContactDate,Today(),Days)<varCustRed))
+ CountRows(Filter(TRACE_Intermediaries, Status.Value="通常",
  DateDiff(LastContactDate,Today(),Days)>=varBrokerYellow))

// 赤アラート件数
CountRows(Filter(TRACE_Customers, Status.Value="通常", IsHandling=false,
  DateDiff(LastContactDate,Today(),Days)>=varCustRed))

// 担当者なし件数
CountRows(Filter(TRACE_Intermediaries, Status.Value="通常", IsBlank(AssignedTo.Email)))
+ CountRows(Filter(TRACE_Customers, Status.Value="通常", IsBlank(AssignedTo.Email)))
```

### 担当者別カード
担当者リストを `colReps`（コレクション or 固定）にして、ギャラリー Items = `colReps`。各カード内：
```powerappsfl
// その担当の未フォロー件数
CountRows(Filter(TRACE_Customers, AssignedTo.Email=ThisItem.Email, Status.Value="通常", IsHandling=false,
  DateDiff(LastContactDate,Today(),Days)>=varCustYellow))
+ CountRows(Filter(TRACE_Intermediaries, AssignedTo.Email=ThisItem.Email, Status.Value="通常",
  DateDiff(LastContactDate,Today(),Days)>=varBrokerYellow))
```

### 紹介ランキング
```powerappsfl
FirstN(SortByColumns(Filter(TRACE_Intermediaries, TotalReferrals>0), "TotalReferrals", Descending), 5)
```

### 一括移管（担当者A→B）
2つのコンボボックス（cmbFrom / cmbTo）＋実行ボタン：
```powerappsfl
ForAll(
  Filter(TRACE_Customers, AssignedTo.Email = cmbFrom.Selected.Mail),
  Patch(TRACE_Customers, ThisRecord,
    { AssignedTo:{'@odata.type':"#Microsoft.Azure.Connectors.SharePoint.SPListExpandedUser",
      Claims:"i:0#.f|membership|"&cmbTo.Selected.Mail, DisplayName:cmbTo.Selected.DisplayName, Email:cmbTo.Selected.Mail} })
);
// 仲介業者も同様に ForAll で更新
Notify("一括移管しました", NotificationType.Success)
```
> 件数が多い場合は Power Automate に逃がすと UI が固まらない（後述）。

---

## 9. Power Automate フロー

### ① 最終接触日の自動更新
- トリガー：**SharePoint「項目が作成されたとき」** `TRACE_VisitHistory`
- アクション：条件で RelatedType を分岐 → **「項目の更新」** で対象リストの `LastContactDate` を `VisitDate` に更新

### ② 毎日アラート計算（DaysSinceContact/AlertStatus を更新）※将来の委任対策
- トリガー：**スケジュール（毎朝7:00）**
- 「複数項目の取得」→「Apply to each」で `DaysSinceContact = ticks差から日数`、`AlertStatus` を更新
- ※MVP（小規模）では省略可。アプリ内 DateDiff で十分

### ③ マネージャー通知（毎朝8:00）
- スケジュール → アラート対象＋担当者なしを集計 → **Teams「チャットまたはチャネルでメッセージを投稿」**

### ④ 営業向け朝の通知（毎朝8:30）
- スケジュール → 担当者ごとに本日フォロー予定を集計 → 各担当へ Teams 個別投稿

### ⑤ 週次報告（毎日チェック→設定曜日・時刻で実行）
- スケジュール（毎朝） → `TRACE_Settings` の `WeeklyReportDay`/`Time` を取得
- 条件：`formatDateTime(utcNow(),'dddd')` が設定曜日と一致 → サマリーを Teams 送信
- これで**フロー改修なしで曜日・時刻変更可**

### ⑥ AI要約（Power Apps から呼ぶ）
- トリガー：**PowerApps（V2）** 入力：訪問テキスト
- アクション：AI Builder「テキストを要約」or「GPTでプロンプト実行」→ 要約・次回フォロー候補を返す
- **Week1で利用可否を検証。不可ならアプリ内スタブに切替**
- 返却：`Respond to a PowerApp` で `summary` 等を返す → アプリ側 `TRACE_Summarize.Run()`

### ⑦ メール下書き
- PowerApps（V2）トリガー → **Outlook「メールの下書きを作成」**（標準コネクタ）
- 顧客情報＋履歴＋人となりをプロンプトに含めて Copilot/AI Builder で本文生成 → 下書き保存
- 不可なら本文だけ返してアプリでコピー表示

---

## 10. 委任（Delegation）について

- 本MVPは全リスト2000件未満 → **`DateDiff`・`IsBlank(Person.Email)` の委任警告は無視してOK**（全件ロードされ正しく動く）
- 将来1000件超になったら：
  - `DaysSinceContact`（数値）をフロー②で毎日更新し、`Filter(..., DaysSinceContact >= varCustYellow)` に置き換え（数値比較は委任可能）
  - 担当者は `AssignedToEmail`（テキスト列）を別途持ち、テキスト等価比較でフィルタ

---

## 11. 作る順番（このガイドの歩き方）

1. App.OnStart（テーマ・設定読み込み）
2. scrHome（CTA＋TODAY＋ALERT）＋ボトムナビ
3. scrBrokers / scrCustomers（一覧・除外フィルタ）
4. scrDetail（タブ・担当者変更・状態バッジ・NGブロック）
5. 記録モーダル（Patch）＋フロー①最終接触日更新
6. scrPool（未割当・引き取り・休眠）
7. フロー⑥AI要約（or スタブ）→ AI提案パネル
8. フロー⑦メール下書き
9. scrDash（KPI・担当者別・ランキング・一括移管）
10. フロー③④⑤（通知・週次報告）
11. 設定画面（TRACE_Settings 編集）

各ステップで保存・プレビュー（▶）して動作確認しながら進める。
