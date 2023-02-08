﻿param (
  [string]$FilterPath, #Stats folder on repo, replicated locally, default='sydney/staging'
  [String]$FilterFile, #If null search all files in last 48ish hours that are not processed
  [string]$OutFolder,  #Path of ouput JSON and HTML
  [switch]$LatestFile, #Last modified file only (from the filtered list)
  [int]   $LimitMins,  #Only access files from last X minutes (sum of days and mins)(sum of days and mins)
  [int]   $LimitDays,  #Only access files from last X days (sum of days and mins)
  [switch]$Overwrite,  #Force re-download do the FO_stats again even when file exists
  [int]   $RoundTime,  #Passed to FO_Stats
  [switch]$TextSave,   #Passed to FO_Stats
  [switch]$TextOnly    #Passed to FO_Stats
)

if (!$OutFolder) { $OutFolder = "$PSScriptRoot" }
if (!(Test-Path -LiteralPath "$OutFolder" )) { $OutFolder = (New-Item $OutFolder -ItemType Directory -Force) }
else { $OutFolder = Get-Item -LiteralPath $OutFolder}

$timeUTC = (Get-Date).ToUniversalTime()

if (!$FilterPath) { $FilterPath = 'sydney/staging/' }
if ($FilterPath -notmatch '.*/$') { $FilterPath = "$FilterPath/" }
  

function New-UrlStatFile { return [PSCustomObject]@{ Name=$args[0]; DateTime=$args[1] } }
$statFiles = @()

if ($LimitMins -eq 0 -or $LimitDays -eq 0) {
  $LimitDays = 1
}

if ($FilterFile) {
  $xml = [xml](invoke-webrequest -Uri "https://fortressone-stats.s3.amazonaws.com/?prefix=$FilterPath$FilterFile") 
  if (($xml.ListBucketResult.Contents.Count) -ne 0) {
    $xml.ListBucketResult.Contents | foreach { $statFiles += (New-UrlStatFile $_.Key $_.LastModified) }
  }
} else {
  $startDate = $timeUTC.AddMinutes($LimitMins * -1).AddDays($LimitDays * -1)
  $tempDate  = $startDate
  while ($tempDate.Year -le $timeUTC.Year -and $tempDate.Month -le $timeUTC.Month) {
    $xml = [xml](invoke-webrequest -Uri "https://fortressone-stats.s3.amazonaws.com/?prefix=$FilterPath$($startDate.Year)-$('{0:d2}' -f $startDate.Month)") 
    if (($xml.ListBucketResult.Contents.Count) -ne 0) {
      $xml.ListBucketResult.Contents | foreach { $statFiles += (New-UrlStatFile $_.Key $_.LastModified) }
    }
    $tempDate = $tempDate.AddMonths(1)
  }
}

#LatestFileOnly
if ($LatestFile) { $statFiles = ($statFiles | Sort DateTime -Descending)[0] }

write-host "FO Stats Downloader: `n"`
            "Date Limiter:`t$('{0:yyyy-MM-dd-HH-mm-ss}' -f $startDate)`n"`
            "-LimitDays:`t$LimitDays`n" `
            "-LimitMins:`t$LimitMins`n" `
            "-FilterFile:`t$FilterFile`n" `
            "-FilterPath:`t$FilterPath`n" `
            "-OutFolder:`t$OutFolder`n"`
            "-Overwrite:`t$Overwrite`n"`

foreach ($f in $statFiles) {
  if ($LimitMins -gt 0 -or $LimitDays -gt 0)  {
    if ($f.Name -notmatch '20[1-3][0-9]-[0-1][0-9]-[0-3][0-9]-[0-2][0-9]-[0-5][0-9]-[0-5][0-9]') {
      Write-Host "ERROR: Minute/Day limit not possible - file has invalid date/time [$($f.Name)]"
      continue
    } else {
      $f_date = ([DateTime]::ParseExact($matches[0],'yyyy-MM-dd-HH-mm-ss',$null))
      if ($f_date -lt $timeUTC.AddMinutes($LimitMins * -1).AddDays($LimitDays * -1)) { continue }
    }
  }

  $filePath  = "$OutFolder\$(Split-Path $f.Name)"
  $fileName  = "$OutFolder\$($f.Name)"
  
  if (!$Overwrite -and (Test-Path -LiteralPath $fileName)) {
    write-host "===================================================================================================="
    write-host "SKIPPED: File Already exists [$($f.Name)]"
    write-host "----------------------------------------------------------------------------------------------------"
    continue
  } 

  if (!(Test-Path -LiteralPath $filePath)) { New-Item -Path $filePath -ItemType Directory }
  write-host "===================================================================================================="
  write-host "Downloading:- $($f.Name)"
  ([string](invoke-webrequest -Uri "https://fortressone-stats.s3.amazonaws.com/$($f.Name)")) | Out-File -LiteralPath  $fileName


  $param = @{ StatFile=$fileName }
  if ($RoundTime) { $param.RoundTime = $RoundTime }
  if ($TextOnly)  { $param.TextOnly = $true }
  if ($TextSave)  { $param.TextSave = $true }

  write-host "FO Stats Start:- `t$($f.Name)"
  if ($param.Count -gt 1) { Write-Host "Parameters: $($param.GetEnumerator() | foreach { if ($_.Name -ne 'StatFile') { " -$($_.Name): $($_.Value)" } })" }
  write-host "----------------------------------------------------------------------------------------------------"
  & H:\_stats\FO_stats_v2.ps1 @param
  write-host "----------------------------------------------------------------------------------------------------"
  write-host "FO Stats Completed:-`t$($f.Name)"
  write-host "----------------------------------------------------------------------------------------------------"
}

