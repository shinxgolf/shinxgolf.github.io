# アプリ画面の「コード化」— 現実的なやり方（pac）

> 結論：**ゼロから完成アプリを自動生成するのは非推奨**。
> 代わりに「Cの手順書で素早く作る → コード化してgit管理 → 以降は差分で回す」が一番確実で速い。

## なぜ「ゼロから自動生成」を推さないのか

- Power Apps のソース形式（`pac canvas` の YAML）は**バージョン依存で壊れやすい**。
- 生成物は**実テナントで import → 微修正の往復**をしないと完成しない。
- 私（AI側）はあなたのテナントに入れないため、その往復ができない。
  → 未検証の「完成品」を渡すと import 失敗で逆に遅くなる。

だから安全策として **C（コピペ手順書）で実体を作り**、その後コードにする。

## 推奨ワークフロー（round-trip）

```
[1] C手順書で Power Apps Studio に画面を作る（速い・確実）
        ↓ Studio: ファイル → 名前を付けて保存 → このコンピューター → .msapp を書き出し
[2] pac でソースに展開（unpack）→ git にコミット
        pwsh ./App-SourceControl.ps1 -Unpack -MsappPath "../TRACE.msapp"
        → src/canvas/ に画面ごとの YAML が出る → git add で差分管理
        ↓ 以降の修正
[3-a] 細かい修正は Studio で行い、再度 Export → Unpack（[2]を繰り返す）
[3-b] まとめてコードで直したいときは src/canvas/ を編集 → pack → Import
        pwsh ./App-SourceControl.ps1 -Pack -MsappPath "../TRACE-rebuilt.msapp"
```

これで「画面の変更履歴が git に残る／レビューできる／別環境へ再現できる」状態になる。

## pac の準備（初回のみ）

```powershell
# インストール（いずれか）
dotnet tool install --global Microsoft.PowerApps.CLI.Tool
#   または winget install Microsoft.PowerPlatformCLI
#   または VS Code 拡張 "Power Platform Tools"

# 認証（あなたの環境URLに合わせる）
pac auth create --environment "https://<your-env>.crm.dynamics.com"
pac auth list
```

> ⚠️ このリポジトリの環境からはあなたのテナントに接続できないため、上記コマンドは**会社PCで**実行してください。

## さらに自動化したい場合（将来）

- **ソリューション化**：アプリ＋フロー＋接続参照を1つの Solution にまとめ、`pac solution import` で別環境へ一括展開。
  ただし接続参照の繋ぎ直しが要るため、まずは round-trip（上記）で十分。
- **CI**：git push 時に `pac canvas pack` で検証する GitHub Actions も組めるが、まずは手元 round-trip を固めてから。

## 「それでもゼロ生成を試したい」人へ（実験・自己責任）

1. C手順書で**1画面だけ**作って Export → Unpack し、`src/canvas/` の YAML 構造を確認
2. その構造を雛形に、他画面の YAML を追記
3. `-Pack` して Import し、**必ず動作確認**
4. 壊れたら C手順書に戻す（実体づくりの正解はC）

→ 構造サンプルが手に入ったら、その YAML をこのリポジトリに置いてくれれば、
   以降の画面ぶんを**あなたのバージョンに合わせて**生成を手伝えます。
