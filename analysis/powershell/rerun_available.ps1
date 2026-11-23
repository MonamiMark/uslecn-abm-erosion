#requires -Version 7
<#
  rerun_available.ps1 - prepocet vsech experimentu, pro ktere mame kompletni CSV.

  Resume v run_all.ps1 povazuje experiment za hotovy, kdyz pocet datovych radku
  CSV rovna se poctu kombinaci. Stare CSV pochazeji z modelu s P + 0.85S a
  chybnym L-faktorem, proto se musi znovu spustit s -Force.

  Vyber: z run_status.csv se berou experimenty se rows == combos, alespon
  100 radku (vylouci se mikro-testy) a s existujicim CSV v out/. Seznam se
  jeste overi proti nazvum experimentu v modelu.

  Priklad:
    pwsh -File rerun_available.ps1 -Parallel 10 -CapHours 6
#>
param(
    [int]$Parallel = 10,
    [double]$CapHours = 6,
    [string]$Heap = "1g"
)

$ErrorActionPreference = "Stop"
$here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$model     = Join-Path $here "usle_abm_model_LE_LFIX_RUN.nlogo"
$outDir    = Join-Path $here "out"
$statusCsv = Join-Path $here "run_status.csv"
$runner    = Join-Path $here "run_all.ps1"

$txt = [System.IO.File]::ReadAllText($model, [System.Text.Encoding]::UTF8)
$names = @([regex]::Matches($txt, '<experiment name="([^"]+)"') |
           ForEach-Object { $_.Groups[1].Value })

$list = @()
foreach ($r in (Import-Csv -Path $statusCsv)) {
    if ([int]$r.rows -ne [int]$r.combos) { continue }
    if ([int]$r.rows -lt 100) { continue }
    $csv = Join-Path $outDir (($r.experiment -replace '[\\/:*?"<>|]', '_') + ".csv")
    if (-not (Test-Path $csv)) { continue }
    if ($names -notcontains $r.experiment) {
        Write-Warning "Experiment v modelu nenalezen, preskakuji: $($r.experiment)"
        continue
    }
    $list += $r.experiment
}

if ($list.Count -eq 0) { throw "Zadne kompletni experimenty k prepoctu." }

$combos = 0
foreach ($r in (Import-Csv -Path $statusCsv)) {
    if ($list -contains $r.experiment) { $combos += [int]$r.rows }
}

Write-Host ("PREDPOCTET: {0} experimentu, {1} kombinaci, model s P + 0.8S a opravenym L-faktorem." -f $list.Count, $combos)
Write-Host ("Experimenty: " + ($list -join ", "))
Write-Host "Spoustim run_all.ps1 s -Force (stare CSV budou smazany a prepocitany)."

& $runner -Force -Only $list -Parallel $Parallel -CapHours $CapHours -Heap $Heap
