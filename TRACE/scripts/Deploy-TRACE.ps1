<#
.SYNOPSIS
  TRACE を「ワンコマンド」で会社テナントに展開するための入口スクリプト。

.DESCRIPTION
  この1本を実行するだけで、データ層（SharePoint の5リスト＋デモデータ）が自動で出来上がります。
  内部でやること：
    1. 前提チェック（PowerShell 7+ / PnP.PowerShell モジュール）。無ければ自動インストールを試みる
    2. SharePoint へ接続（ブラウザ認証）
    3. Provision-TRACE-Lists.ps1 を呼び出し → 5リスト作成・インデックス設定・デモデータ投入
    4. 次にやること（画面づくり・フロー）の案内を表示

  ※ Power Apps の「画面」と Power Automate の「フロー」は別ステップです（README参照）。
    このスクリプトは “確実に自動化できるデータ層” を担当します。

.PREREQUISITES
  - SharePoint チームサイトが作成済みであること（例：https://<テナント>.sharepoint.com/sites/TRACE）
  - そのサイトにリストを作れる権限

.USAGE
  # 最小（担当者はデモの架空ユーザーのまま＝未割当扱い）
  pwsh ./Deploy-TRACE.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TRACE"

  # デモの担当者を「自分」にまとめて割り当てて、ダッシュボードを賑やかに見せたいとき
  pwsh ./Deploy-TRACE.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TRACE" -DefaultAssignee "you@contoso.com"

  # デモの担当者を実メンバーに正確に割り当てたいとき → demo-data/user-map.csv を編集してから実行
#>

param(
  [Parameter(Mandatory=$true)][string]$SiteUrl,
  [string]$DefaultAssignee = "",
  [switch]$SkipData          # データ投入をスキップしてリスト作成だけ行う
)

$ErrorActionPreference = "Stop"
$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$dataPath = Join-Path (Split-Path -Parent $here) "demo-data"

function Section($t){ Write-Host "`n==== $t ====" -ForegroundColor Cyan }

# ---------- 1. 前提チェック ----------
Section "1/3 前提チェック"
if ($PSVersionTable.PSVersion.Major -lt 7) {
  Write-Warning "PowerShell 7 以上を推奨します（現在 $($PSVersionTable.PSVersion)）。https://aka.ms/powershell からインストールできます。"
}
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
  Write-Host "PnP.PowerShell が見つかりません。インストールします..." -ForegroundColor Yellow
  Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
}
Import-Module PnP.PowerShell -ErrorAction Stop
Write-Host "OK: PnP.PowerShell 準備完了" -ForegroundColor Green

# user-map の状態を知らせる
$mapPath = Join-Path $dataPath "user-map.csv"
if (Test-Path $mapPath) {
  $mapped = (Import-Csv $mapPath | Where-Object { $_.RealEmail }).Count
  if ($mapped -eq 0 -and -not $DefaultAssignee) {
    Write-Host "ヒント: 担当者は全員『未割当』として取り込まれます（デモの未割当プールが見せられます）。" -ForegroundColor DarkGray
    Write-Host "       実メンバーに割り当てたい場合は demo-data/user-map.csv を編集するか -DefaultAssignee を指定してください。" -ForegroundColor DarkGray
  }
}

# ---------- 2 & 3. プロビジョニング ----------
Section "2/3 SharePoint リスト作成 ＋ データ投入"
$provision = Join-Path $here "Provision-TRACE-Lists.ps1"
$splat = @{ SiteUrl = $SiteUrl; DataPath = $dataPath; DefaultAssignee = $DefaultAssignee }
if ($SkipData) { $splat.ImportData = $false }
& $provision @splat

# ---------- 完了案内 ----------
Section "3/3 完了 — 次のステップ"
Write-Host @"
✅ データ層の自動展開が完了しました。

このあとの作業（手動 or 半自動）:
  A) Power Apps の画面づくり
     → runbook/PowerApps-詳細ビルドガイド.md の「11. 作る順番」に沿って実装
     → 完成イメージは prototype/index.html（ブラウザで開く）
  B) Power Automate のフロー（通知・週次報告・最終接触日更新 など7本）
     → runbook/PowerApps-詳細ビルドガイド.md「9. フロー」
  C) 実運用前に必ず変更:
     - TRACE_Settings の ManagerEmails を実メールに（マネジメントモードの表示判定）
     - 週次報告の曜日/時刻など

詳しくは TRACE/README.md を参照してください。
"@ -ForegroundColor Green
