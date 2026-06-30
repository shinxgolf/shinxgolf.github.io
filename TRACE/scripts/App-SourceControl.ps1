<#
.SYNOPSIS
  Power Apps キャンバスアプリを「コード（ソース）」として git 管理するための round-trip ヘルパー。

.DESCRIPTION
  Power Platform CLI (pac) を使い、.msapp を YAML ソースへ展開(unpack)／ソースから .msapp へ再構築(pack) する。
  これにより「画面をコードで差分レビュー・再生成」できる。
  ※ ゼロから手書きでアプリ全体を生成するのは壊れやすいため非推奨。
    まず Cの手順書でアプリを作り、Studio から .msapp を Export → このスクリプトで Unpack して取り込むのが安全。

.PREREQUISITES
  - Power Platform CLI (pac)。未導入なら:
      dotnet tool install --global Microsoft.PowerApps.CLI.Tool
    （または winget install Microsoft.PowerPlatformCLI / VS Code 拡張 "Power Platform Tools"）
  - 認証: pac auth create --environment "https://<env>.crm.dynamics.com"

.USAGE
  # .msapp → ソース（src/canvas/ 配下に YAML 展開）。git にコミットして差分管理する
  pwsh ./App-SourceControl.ps1 -Unpack -MsappPath "..\TRACE.msapp"

  # ソース → .msapp（再構築。Studio から Import して反映）
  pwsh ./App-SourceControl.ps1 -Pack -MsappPath "..\TRACE-rebuilt.msapp"
#>

param(
  [switch]$Unpack,
  [switch]$Pack,
  [string]$MsappPath = "../TRACE.msapp",
  [string]$SourceDir = "../src/canvas"
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $here $SourceDir
$msapp= Join-Path $here $MsappPath

# pac の存在チェック
if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
  Write-Error @"
pac (Power Platform CLI) が見つかりません。先にインストールしてください:
  dotnet tool install --global Microsoft.PowerApps.CLI.Tool
詳細: https://learn.microsoft.com/power-platform/developer/cli/introduction
"@
  exit 1
}

if (-not ($Unpack -or $Pack)) { Write-Error "-Unpack か -Pack のどちらかを指定してください"; exit 1 }

if ($Unpack) {
  if (-not (Test-Path $msapp)) { Write-Error "msapp が見つかりません: $msapp（Studio から Export してパスを指定）"; exit 1 }
  New-Item -ItemType Directory -Force -Path $src | Out-Null
  Write-Host "→ Unpack: $msapp → $src" -ForegroundColor Cyan
  pac canvas unpack --msapp $msapp --sources $src
  Write-Host "✅ 展開完了。git add で差分管理できます。" -ForegroundColor Green
}

if ($Pack) {
  if (-not (Test-Path $src)) { Write-Error "ソースが見つかりません: $src"; exit 1 }
  Write-Host "→ Pack: $src → $msapp" -ForegroundColor Cyan
  pac canvas pack --sources $src --msapp $msapp
  Write-Host "✅ 再構築完了。Power Apps Studio から Import してください。" -ForegroundColor Green
}
