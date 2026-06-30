<#
.SYNOPSIS
  TRACE アプリ用 SharePoint リストを自動プロビジョニングするスクリプト。

.DESCRIPTION
  PnP.PowerShell を使い、TRACE の5リスト（仲介業者・既存顧客・案件・訪問履歴・設定）を
  列定義・インデックス付きで作成し、デモ用CSVを取り込む。

.PREREQUISITES
  1. PowerShell 7+ を推奨
  2. PnP.PowerShell モジュール
       Install-Module PnP.PowerShell -Scope CurrentUser
  3. SharePoint サイト（チームサイト）が作成済みであること
  4. Entra ID アプリ登録（PnP既定アプリでも可）

.USAGE
  pwsh ./Provision-TRACE-Lists.ps1 -SiteUrl "https://contoso.sharepoint.com/sites/TRACE" -DataPath "../demo-data"
#>

param(
  [Parameter(Mandatory=$true)][string]$SiteUrl,
  [string]$DataPath = "../demo-data",
  [switch]$ImportData = $true,
  # デモデータの担当者(架空メール)を実テナントのユーザーに割り当てるための既定値。
  # user-map.csv に対応が無い担当者は、この実在メールに割り当てる（空ならその相手は未割当のまま）。
  [string]$DefaultAssignee = ""
)

# ============ 接続 ============
Write-Host "→ $SiteUrl に接続します（ブラウザで認証）" -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -Interactive

# ============ ヘルパー ============
function Ensure-List($Title) {
  $l = Get-PnPList -Identity $Title -ErrorAction SilentlyContinue
  if ($null -eq $l) {
    Write-Host "  リスト作成: $Title" -ForegroundColor Green
    $l = New-PnPList -Title $Title -Template GenericList -EnableVersioning
  } else {
    Write-Host "  既存リスト利用: $Title" -ForegroundColor Yellow
  }
  return $l
}

function Add-Field($List,$Name,$Type,$Indexed=$false,$Choices=$null,$Required=$false) {
  $existing = Get-PnPField -List $List -Identity $Name -ErrorAction SilentlyContinue
  if ($existing) { return }
  switch ($Type) {
    "Choice" {
      Add-PnPField -List $List -DisplayName $Name -InternalName $Name -Type Choice -Choices $Choices -AddToDefaultView | Out-Null
    }
    default {
      Add-PnPField -List $List -DisplayName $Name -InternalName $Name -Type $Type -AddToDefaultView | Out-Null
    }
  }
  if ($Indexed) { Set-PnPField -List $List -Identity $Name -Values @{Indexed=$true} | Out-Null }
  Write-Host "    + $Name ($Type)$([string]::Format('{0}', $(if($Indexed){' [indexed]'}else{''})))"
}

# ============ 担当者(Person列)のマッピング ============
# デモデータの担当者は架空メール(例: sato@ourcompany.example.jp)。実テナントには存在しないため
# そのままでは割り当てできない。demo-data/user-map.csv (DemoEmail,RealEmail) で実ユーザーへ読み替える。
$script:UserMap = @{}
$mapPath = Join-Path $DataPath "user-map.csv"
if (Test-Path $mapPath) {
  Import-Csv $mapPath | ForEach-Object {
    if ($_.DemoEmail -and $_.RealEmail) { $script:UserMap[$_.DemoEmail.Trim().ToLower()] = $_.RealEmail.Trim() }
  }
  Write-Host "  user-map.csv 読込: $($script:UserMap.Count) 件のユーザー対応" -ForegroundColor Cyan
}
# デモ担当者メール → 実メール（無ければ $DefaultAssignee、それも空なら $null=未割当）
function Resolve-User($demoEmail) {
  if ([string]::IsNullOrWhiteSpace($demoEmail)) { return $null }   # デモ上わざと未割当の相手はそのまま
  $key = $demoEmail.Trim().ToLower()
  if ($script:UserMap.ContainsKey($key)) { return $script:UserMap[$key] }
  if (-not [string]::IsNullOrWhiteSpace($DefaultAssignee)) { return $DefaultAssignee }
  Write-Warning "    担当者 '$demoEmail' の実ユーザー対応が無いため未割当にしました（user-map.csv か -DefaultAssignee で指定可）"
  return $null
}

# ============ 1. 仲介業者 ============
$brokers = Ensure-List "TRACE_Intermediaries"
Add-Field $brokers "Company" "Text"
Add-Field $brokers "Department" "Text"
Add-Field $brokers "JobTitle" "Text"
Add-Field $brokers "Phone" "Text"
Add-Field $brokers "Email" "Text"
Add-Field $brokers "Birthday" "DateTime"
Add-Field $brokers "Hobby" "Note"
Add-Field $brokers "Memo" "Note"
Add-Field $brokers "AssignedTo" "User" -Indexed $true   # 空＝未割当
Add-Field $brokers "Status" "Choice" -Choices @("通常","休眠","対応NG")
Add-Field $brokers "Address" "Text"                      # 地図用
Add-Field $brokers "Latitude" "Number"
Add-Field $brokers "Longitude" "Number"
Add-Field $brokers "LastContactDate" "DateTime" -Indexed $true
Add-Field $brokers "DaysSinceContact" "Number"
Add-Field $brokers "AlertStatus" "Choice" -Choices @("正常","黄","赤")
Add-Field $brokers "TotalReferrals" "Number"
Add-Field $brokers "IsActive" "Boolean"
# ※ Title 列を「氏名」として流用

# ============ 2. 既存顧客 ============
$cust = Ensure-List "TRACE_Customers"
Add-Field $cust "ContactName" "Text"
Add-Field $cust "Phone" "Text"
Add-Field $cust "Email" "Text"
Add-Field $cust "Industry" "Choice" -Choices @("商社","製造","IT","コンサル","食品","不動産","物流","教育","卸売","その他")
Add-Field $cust "EmployeeCount" "Number"
Add-Field $cust "OfficeSize" "Text"
Add-Field $cust "ContractEndDate" "DateTime"
Add-Field $cust "FiscalMonth" "Number"
Add-Field $cust "LastMoveDate" "DateTime"
Add-Field $cust "NextFollowDate" "DateTime" -Indexed $true
Add-Field $cust "LastContactDate" "DateTime" -Indexed $true
Add-Field $cust "DaysSinceContact" "Number"
Add-Field $cust "AlertStatus" "Choice" -Choices @("正常","黄","赤")
Add-Field $cust "IsHandling" "Boolean"
Add-Field $cust "AssignedTo" "User" -Indexed $true      # 空＝未割当
Add-Field $cust "Status" "Choice" -Choices @("通常","休眠","対応NG")
Add-Field $cust "Address" "Text"                         # 地図用
Add-Field $cust "Latitude" "Number"
Add-Field $cust "Longitude" "Number"
Add-Field $cust "IsActive" "Boolean"
# ※ Title 列を「会社名」として流用

# ============ 3. 案件 ============
$cases = Ensure-List "TRACE_Cases"
Add-Field $cases "CustomerName" "Text"
Add-Field $cases "BrokerId" "Number"
Add-Field $cases "BrokerName" "Text"
Add-Field $cases "ReferralDate" "DateTime"
Add-Field $cases "IsContracted" "Boolean"
Add-Field $cases "ContractAmount" "Currency"
Add-Field $cases "Description" "Text"
# ※ Title 列を案件名として流用

# ============ 4. 訪問履歴 ============
$visits = Ensure-List "TRACE_VisitHistory"
Add-Field $visits "RelatedType" "Choice" -Choices @("仲介業者","既存顧客")
Add-Field $visits "RelatedId" "Number"
Add-Field $visits "RelatedName" "Text"
Add-Field $visits "VisitDate" "DateTime" -Indexed $true
Add-Field $visits "VisitType" "Choice" -Choices @("訪問アポ","訪問ついで","電話","メモ")
Add-Field $visits "RawText" "Note"
Add-Field $visits "AISummary" "Note"
Add-Field $visits "RecordedBy" "User"

# ============ 5. 設定 ============
$settings = Ensure-List "TRACE_Settings"
Add-Field $settings "SettingValue" "Text"
Add-Field $settings "SettingDescription" "Text"
# ※ Title 列を SettingKey として流用

# 設定値を投入：demo-data/TRACE_Settings.csv があればそれを正本に、無ければ既定値。
# ※ CSV には ManagerEmails（マネジメントモード表示判定）も含まれる。実運用前に実メールへ要変更。
$settingsCsv = Join-Path $DataPath "TRACE_Settings.csv"
if (Test-Path $settingsCsv) {
  $defaults = Import-Csv $settingsCsv | ForEach-Object {
    @{Key=$_.SettingKey; Val=$_.SettingValue; Desc=$_.Description}
  }
} else {
  $defaults = @(
    @{Key="WeeklyReportDay";    Val="Tuesday"; Desc="週次報告の曜日"},
    @{Key="WeeklyReportTime";   Val="13:00";   Desc="週次報告の時刻"},
    @{Key="WeeklyReportEnabled";Val="true";    Desc="週次報告のON/OFF"},
    @{Key="BrokerAlertDays";    Val="60";      Desc="仲介業者アラート日数"},
    @{Key="CustomerAlertYellow";Val="180";     Desc="既存顧客 黄アラート日数"},
    @{Key="CustomerAlertRed";   Val="365";     Desc="既存顧客 赤アラート日数"},
    @{Key="ManagerEmails";      Val="";        Desc="マネジメントモード表示対象（カンマ区切り・実メールに要変更）"}
  )
}
foreach($d in $defaults){
  $found = Get-PnPListItem -List "TRACE_Settings" -Query "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>$($d.Key)</Value></Eq></Where></Query></View>"
  if(-not $found){
    Add-PnPListItem -List "TRACE_Settings" -Values @{Title=$d.Key; SettingValue=$d.Val; SettingDescription=$d.Desc} | Out-Null
    Write-Host "    設定: $($d.Key) = $($d.Val)"
  }
}

# ============ デモデータ取り込み（任意） ============
if ($ImportData) {
  Write-Host "→ デモデータを取り込みます" -ForegroundColor Cyan

  # 名前→ID 対応表（訪問履歴の RelatedId を後で解決するため）
  $brokerIdByName = @{}
  $custIdByName   = @{}

  # 仲介業者（Birthday・AssignedTo も投入）
  Import-Csv "$DataPath/TRACE_Intermediaries.csv" | ForEach-Object {
    $v = @{
      Title=$_.Name; Company=$_.Company; Department=$_.Department; JobTitle=$_.Title;
      Phone=$_.Phone; Email=$_.Email; Hobby=$_.Hobby; Memo=$_.Memo;
      LastContactDate=$_.LastContactDate; IsActive=[bool]::Parse($_.IsActive)
    }
    if($_.Birthday){ $v.Birthday=$_.Birthday }
    if($_.Status){ $v.Status=$_.Status }
    if($_.Address){ $v.Address=$_.Address }
    if($_.Latitude){ $v.Latitude=[double]$_.Latitude; $v.Longitude=[double]$_.Longitude }
    $assignee = Resolve-User $_.AssignedTo
    if($assignee){ $v.AssignedTo=$assignee }
    $item = Add-PnPListItem -List "TRACE_Intermediaries" -Values $v
    $brokerIdByName[$_.Name] = $item.Id
  }
  Write-Host "  仲介業者 取り込み完了（$($brokerIdByName.Count)件）"

  # 既存顧客（AssignedTo も投入）
  Import-Csv "$DataPath/TRACE_Customers.csv" | ForEach-Object {
    $vals = @{
      Title=$_.CompanyName; ContactName=$_.ContactName; Phone=$_.Phone; Email=$_.Email;
      Industry=$_.Industry; EmployeeCount=[int]$_.EmployeeCount; OfficeSize=$_.OfficeSize;
      ContractEndDate=$_.ContractEndDate; FiscalMonth=[int]$_.FiscalMonth; LastMoveDate=$_.LastMoveDate;
      LastContactDate=$_.LastContactDate; IsHandling=[bool]::Parse($_.IsHandling); IsActive=[bool]::Parse($_.IsActive)
    }
    if($_.NextFollowDate){ $vals.NextFollowDate = $_.NextFollowDate }
    if($_.Status){ $vals.Status=$_.Status }
    if($_.Address){ $vals.Address=$_.Address }
    if($_.Latitude){ $vals.Latitude=[double]$_.Latitude; $vals.Longitude=[double]$_.Longitude }
    $assignee = Resolve-User $_.AssignedTo
    if($assignee){ $vals.AssignedTo=$assignee }
    $item = Add-PnPListItem -List "TRACE_Customers" -Values $vals
    $custIdByName[$_.CompanyName] = $item.Id
  }
  Write-Host "  既存顧客 取り込み完了（$($custIdByName.Count)件）"

  # 案件
  Import-Csv "$DataPath/TRACE_Cases.csv" | ForEach-Object {
    Add-PnPListItem -List "TRACE_Cases" -Values @{
      Title=$_.Description; CustomerName=$_.CustomerName; BrokerName=$_.BrokerName;
      ReferralDate=$_.ReferralDate; IsContracted=[bool]::Parse($_.IsContracted);
      ContractAmount=[double]$_.ContractAmount; Description=$_.Description
    } | Out-Null
  }
  Write-Host "  案件 取り込み完了"

  # 訪問履歴（RecordedBy・RelatedId も投入。RelatedId は上で作った名前→ID表で解決）
  Import-Csv "$DataPath/TRACE_VisitHistory.csv" | ForEach-Object {
    $vh = @{
      Title=$_.RelatedName; RelatedType=$_.RelatedType; RelatedName=$_.RelatedName;
      VisitDate=$_.VisitDate; VisitType=$_.VisitType; RawText=$_.RawText; AISummary=$_.AISummary
    }
    $rid = if($_.RelatedType -eq "仲介業者"){ $brokerIdByName[$_.RelatedName] } else { $custIdByName[$_.RelatedName] }
    if($rid){ $vh.RelatedId=[int]$rid }
    $recorder = Resolve-User $_.RecordedBy
    if($recorder){ $vh.RecordedBy=$recorder }
    Add-PnPListItem -List "TRACE_VisitHistory" -Values $vh | Out-Null
  }
  Write-Host "  訪問履歴 取り込み完了"
}

Write-Host "`n✅ TRACE リストのプロビジョニングが完了しました。" -ForegroundColor Green
Write-Host "   次は Power Apps Studio で各リストに接続し、画面を構築してください。" -ForegroundColor Green
