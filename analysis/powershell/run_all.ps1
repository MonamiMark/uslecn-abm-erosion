#requires -Version 7
<#
  run_all.ps1 - headless BehaviorSpace runner pro usle_abm_model_LE_LFIX_RUN.nlogo

  Kazdy experiment = samostatny proces JVM s 1 vlaknem. Experimenty se pousteji
  paralelne (parametr -Parallel), takze se nevyuziva --threads (ten v NetLogo 7
  zrychleni neprinasi a do logu pise zduplikovane radky).

  PROC SE VOLA JAVA PRIMO (ne NetLogo_Console.exe):
  Instalace ma v app\NetLogo_Console.cfg -XX:MaxRAMPercentage=50, takze si kazdy
  proces narokuje polovinu RAM (na 32 GB stroji ~5 GB virtualniho prostoru).
  Pri 8 paralelnich procesech pak selze commit_memory (DOS error 1455) a beh
  skonci po 2-4 radcich. Primy java.exe s -Xmx1g to obchazi; 72x72 svety
  potrebuji ~1,1 GB pracovni sady.

  - resume: hotovy experiment (pocet datovych radku == ocekavany pocet kombinaci) se preskoci
  - casovy strop na experiment; po prekroceni se proces zabije a oznaci TIMEOUT
  - "MISSING INPUT RASTER" v logu => okamzite zabiti a stav BROKEN
  - "OutOfMemoryError" / "insufficient memory" => stav OOM
  - zapis do run_log.txt a run_status.csv

  Priklady:
    pwsh -File run_all.ps1
    pwsh -File run_all.ps1 -Only pasy_srazky,p500p -Parallel 4
    pwsh -File run_all.ps1 -Force -CapHours 4
#>
param(
    [int]$Parallel = 10,
    [double]$CapHours = 6,
    [string[]]$Only = @(),
    [switch]$Force,
    [string]$Heap = "1g",
    [string]$JavaExe = ""
)

$ErrorActionPreference = "Stop"
$here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$model     = Join-Path $here "usle_abm_model_LE_LFIX_RUN.nlogo"
$outDir    = Join-Path $here "out"
$logFile   = Join-Path $here "run_log.txt"
$statusCsv = Join-Path $here "run_status.csv"
$jar       = "C:\Program Files\NetLogo 7.0.2\app\netlogo-7.0.2.jar"
$extDir    = "C:\Program Files\NetLogo 7.0.2\extensions\.bundled"
$modelsDir = "C:\Program Files\NetLogo 7.0.2\models"
$nativeDir = "C:\Program Files\NetLogo 7.0.2\natives\windows-amd64"

if (-not $JavaExe) {
    if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) {
        $JavaExe = Join-Path $env:JAVA_HOME "bin\java.exe"
    } elseif (Test-Path "C:\Program Files\Java\jdk-25\bin\java.exe") {
        $JavaExe = "C:\Program Files\Java\jdk-25\bin\java.exe"
    } else {
        $JavaExe = (Get-Command java -ErrorAction SilentlyContinue).Source
    }
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (-not (Test-Path $model))   { throw "Model nenalezen: $model" }
if (-not (Test-Path $jar))     { throw "NetLogo jar nenalezen: $jar" }
if (-not $JavaExe -or -not (Test-Path $JavaExe)) { throw "java.exe nenalezen (nastav -JavaExe)" }

# jadro designu = synteticke DEMy; 4 experimenty s chybejicimi rastry tu zamerne nejsou
$active = @(
    "pasy_srazky", "eKPnt", "ePKnt", "p400s1p", "p400s1k", "p500p", "p500k",
    "ePKnt288", "eKPnt288_2", "p288p", "p288k",
    "eKPntTwo", "eKPntTwo (copy)", "ex_pasy_obracene", "ex_pasy_obracene_25",
    "experiment2", "experiment", "exp_two_angles_standard", "pasy_srazky_test"
)

function Write-Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -Path $logFile -Value $line -Encoding utf8
    Write-Host $line
}

# --- parser BehaviorSpace XML -------------------------------------------------
$txt = [System.IO.File]::ReadAllText($model, [System.Text.Encoding]::GetEncoding(1250))

function Get-ExperimentInfo {
    param([string]$name)
    $rx = [regex]("(?s)<experiment name=`"$([regex]::Escape($name))`"([^>]*)>(.*?)</experiment>")
    $m = $rx.Match($txt)
    if (-not $m.Success) { return $null }
    $attr = $m.Groups[1].Value
    $body = $m.Groups[2].Value
    $reps = if ($attr -match 'repetitions="(\d+)"') { [int]$matches[1] } else { 1 }

    $vars = [ordered]@{}
    foreach ($mm in [regex]::Matches($body, '(?s)<enumeratedValueSet variable="([^"]+)">(.*?)</enumeratedValueSet>')) {
        $vals = @([regex]::Matches($mm.Groups[2].Value, '<value value="([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
        $vars[$mm.Groups[1].Value] = $vals
    }
    foreach ($mm in [regex]::Matches($body, '<steppedValueSet variable="([^"]+)" first="([^"]+)" step="([^"]+)" last="([^"]+)"')) {
        $f = [double]$mm.Groups[2].Value; $s = [double]$mm.Groups[3].Value; $l = [double]$mm.Groups[4].Value
        $vals = @(); for ($v = $f; $v -le $l + 1e-9; $v += $s) { $vals += [string]([math]::Round($v, 6)) }
        $vars[$mm.Groups[1].Value] = $vals
    }

    $combos = $reps
    foreach ($v in $vars.Values) { $combos *= [math]::Max(1, $v.Count) }
    [pscustomobject]@{ Name = $name; Combos = $combos; Vars = $vars }
}

# NetLogo 7 zapisuje 7 radku hlavicky, pak data. Radek muze mit vlozene \r,
# proto se cte po radcich pres StreamReader (ReadAllLines by mohl rozbit pocitani).
function Get-DataRowCount {
    param([string]$path)
    if (-not (Test-Path $path)) { return 0 }
    $n = 0
    try {
        $sr = [System.IO.StreamReader]::new($path, [System.Text.Encoding]::GetEncoding(1250))
        try {
            while ($null -ne $sr.ReadLine()) { $n++ }
        } finally { $sr.Dispose() }
    } catch {
        # NetLogo prave drzi soubor pro zapis - vrat posledni znamy stav
        return 0
    }
    if ($n -le 7) { return 0 }
    return $n - 7
}

# total-erosion je predposledni sloupec (za nim je highest-c-factor-representation)
function Get-NegativeCount {
    param([string]$path)
    if (-not (Test-Path $path)) { return 0 }
    $neg = 0; $i = 0
    $sr = [System.IO.StreamReader]::new($path, [System.Text.Encoding]::GetEncoding(1250))
    try {
        while ($null -ne ($line = $sr.ReadLine())) {
            $i++
            if ($i -le 7 -or -not $line.StartsWith('"')) { continue }
            $parts = $line -split '","'
            if ($parts.Count -lt 2) { continue }
            $v = 0.0
            $raw = $parts[$parts.Count - 2].Trim('"')
            if ([double]::TryParse($raw, [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and $v -lt -0.001) { $neg++ }
        }
    } finally { $sr.Dispose() }
    return $neg
}

# stav se akumuluje mezi behy (resume), aby se neprepsaly starsi vysledky
$script:status = [ordered]@{}
if (Test-Path $statusCsv) {
    foreach ($r in (Import-Csv -Path $statusCsv)) {
        if ($r.experiment) { $script:status[$r.experiment] = $r }
    }
}
function Set-Status([string]$Name, [int]$Combos, [string]$State, [int]$Rows, [double]$Seconds, [string]$Note = "") {
    $script:status[$Name] = [pscustomobject]@{
        experiment = $Name; combos = $Combos; state = $State
        rows = $Rows; seconds = [math]::Round($Seconds, 1); note = $Note
        updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $script:status.Values | Sort-Object experiment | Export-Csv -Path $statusCsv -Encoding utf8
}

function Get-SafeName([string]$n) { return ($n -replace '[\\/:*?"<>|]', "_") }

# Start-Process sklada -ArgumentList prostym spojenim mezerami, takze cesty s mezerou
# (a jmena experimentu jako "eKPntTwo (copy)") musi byt zaquotedovat rucne.
function Join-Quoted([string[]]$items) {
    $out = foreach ($a in $items) {
        if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
    }
    return ($out -join ' ')
}

# --- vyber a poradi (nejvetsi prvni = LPT scheduling) -------------------------
# -Only bere jmena primo z modelu (vcetne vygenerovanych chunk experimentu);
# bez -Only se jede pevny seznam $active.
$Only = @($Only | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$queue = @()
$candidates = if ($Only.Count -gt 0) { $Only } else { $active }
foreach ($name in $candidates) {
    $info = Get-ExperimentInfo $name
    if ($null -eq $info) { Write-Log "VAROVANI: experiment '$name' v modelu nenalezen"; continue }
    $queue += $info
}
if ($queue.Count -eq 0) { throw "Zadny experiment k behu (zkontroluj -Only)." }
$queue = @($queue | Sort-Object Combos -Descending)

$totalCombos = ($queue | Measure-Object Combos -Sum).Sum
Write-Log ("START runner: {0} experimentu, {1} kombinaci, paralelne {2}, halda {3}, strop {4} h/experiment" -f $queue.Count, $totalCombos, $Parallel, $Heap, $CapHours)
Write-Log ("java: {0}" -f $JavaExe)

$overall = [System.Diagnostics.Stopwatch]::StartNew()
$running = @()
$doneCombos = 0
$doneSeconds = 0.0
$lastReport = 0.0

function Start-Exp($exp) {
    $csv = Join-Path $outDir ("{0}.csv" -f (Get-SafeName $exp.Name))
    $lg  = Join-Path $outDir ("{0}.log" -f (Get-SafeName $exp.Name))
    $er  = Join-Path $outDir ("{0}.err" -f (Get-SafeName $exp.Name))
    Remove-Item $lg, $er -Force -ErrorAction SilentlyContinue
    Write-Log ("START {0}: {1} kombinaci" -f $exp.Name, $exp.Combos)

    $jvm = @(
        "-Xms512m", "-Xmx$Heap",
        "-Dfile.encoding=UTF-8",
        "-Dnetlogo.models.dir=$modelsDir",
        "-Dnetlogo.extensions.dir=$extDir",
        "-Djava.library.path=$nativeDir",
        "--add-exports=java.base/java.lang=ALL-UNNAMED",
        "--add-exports=java.desktop/sun.awt=ALL-UNNAMED",
        "--add-exports=java.desktop/sun.java2d=ALL-UNNAMED",
        "-classpath", $jar,
        "org.nlogo.headless.Main",
        "--model", $model,
        "--experiment", $exp.Name,
        "--table", $csv,
        "--threads", "1"
    )
    $argStr = Join-Quoted $jvm

    $p = Start-Process -FilePath $JavaExe -ArgumentList $argStr `
        -NoNewWindow -PassThru -RedirectStandardOutput $lg -RedirectStandardError $er
    [pscustomobject]@{
        Exp = $exp; Proc = $p; Csv = $csv; Log = $lg; Err = $er
        Sw = [System.Diagnostics.Stopwatch]::StartNew(); State = "RUN"; Note = ""
    }
}

function Get-ExitCodeSafe($p) {
    try { $p.Refresh(); return $p.ExitCode } catch { return $null }
}

function Finish-Exp($job) {
    try { $job.Proc.WaitForExit(30000) | Out-Null } catch {}
    $job.Sw.Stop()
    $rows = Get-DataRowCount $job.Csv
    $state = $job.State
    $note = $job.Note
    $exit = Get-ExitCodeSafe $job.Proc
    if ($state -eq "RUN") {
        $oom = $false
        foreach ($f in @($job.Log, $job.Err)) {
            if ((Test-Path $f) -and (Select-String -Path $f -Pattern "OutOfMemoryError|insufficient memory|os::commit_memory" -Quiet -ErrorAction SilentlyContinue)) { $oom = $true }
        }
        if ($oom) {
            $state = "OOM"; $note = "rows $rows / $($job.Exp.Combos), exit $exit"
        } elseif ($rows -eq $job.Exp.Combos) {
            $state = "DONE"
        } else {
            $state = "INCOMPLETE"; $note = "rows $rows / $($job.Exp.Combos), exit $exit"
        }
    }
    if ($state -eq "DONE") {
        $neg = Get-NegativeCount $job.Csv
        if ($neg -gt 0) { $state = "NEGATIVE"; $note = "$neg radku se zapornou erozi" }
    }
    $rate = if ($rows -gt 0) { [math]::Round($job.Sw.Elapsed.TotalSeconds / $rows, 1) } else { 0 }
    Write-Log ("END {0}: {1} ({2} radku, {3} min, {4} s/scenar) {5}" -f $job.Exp.Name, $state, $rows, [math]::Round($job.Sw.Elapsed.TotalMinutes, 1), $rate, $note)
    Set-Status $job.Exp.Name $job.Exp.Combos $state $rows $job.Sw.Elapsed.TotalSeconds $note
    $script:doneCombos += $rows
    $script:doneSeconds += $job.Sw.Elapsed.TotalSeconds
}

# --- hlavni smycka ------------------------------------------------------------
while (($queue.Count -gt 0) -or ($running.Count -gt 0)) {

    # nastartuj dalsi, dokud je mista
    while ($running.Count -lt $Parallel -and $queue.Count -gt 0) {
        $exp = $queue[0]
        $queue = @($queue | Select-Object -Skip 1)

        $csv = Join-Path $outDir ("{0}.csv" -f (Get-SafeName $exp.Name))
        if (-not $Force) {
            $rows = Get-DataRowCount $csv
            if ($rows -eq $exp.Combos) {
                Write-Log ("SKIP {0}: hotovo ({1} radku)" -f $exp.Name, $rows)
                Set-Status $exp.Name $exp.Combos "DONE" $rows 0 "resume"
                $script:doneCombos += $rows
                continue
            }
            if ($rows -gt 0) {
                Write-Log ("{0}: neuplny vystup ({1}/{2}), maze se" -f $exp.Name, $rows, $exp.Combos)
                Remove-Item $csv -Force
            }
        } else {
            Remove-Item $csv -Force -ErrorAction SilentlyContinue
        }
        $running += Start-Exp $exp
    }

    if ($running.Count -eq 0) { continue }

    Start-Sleep -Seconds 3

    foreach ($job in @($running)) {
        $el = $job.Sw.Elapsed.TotalSeconds

        if (-not $job.Proc.HasExited) {
            if (Test-Path $job.Log) {
                if (Select-String -Path $job.Log -Pattern "MISSING INPUT RASTER" -Quiet -ErrorAction SilentlyContinue) {
                    $job.State = "BROKEN"; $job.Note = "missing input raster"
                    & taskkill /T /F /PID $job.Proc.Id 2>$null | Out-Null
                }
            }
            if ($job.State -eq "RUN" -and $el -gt $CapHours * 3600) {
                $job.State = "TIMEOUT"; $job.Note = "cap $CapHours h"
                & taskkill /T /F /PID $job.Proc.Id 2>$null | Out-Null
            }
        }

        $exited = $job.Proc.HasExited
        if ($exited -or $job.State -ne "RUN") {
            if (-not $exited) { try { $job.Proc.WaitForExit(60000) | Out-Null } catch {} }
            Finish-Exp $job
            $running = @($running | Where-Object { $_ -ne $job })
        }
    }

    # prubezny stav (max 1x za minutu, aby log nebyl zahlcen)
    if ($overall.Elapsed.TotalSeconds - $lastReport -ge 60) {
        $lastReport = $overall.Elapsed.TotalSeconds
        $leftQueue = ($queue | Measure-Object Combos -Sum).Sum
        if ($null -eq $leftQueue) { $leftQueue = 0 }
        $leftRun = 0
        foreach ($job in $running) {
            $r = Get-DataRowCount $job.Csv
            $leftRun += [math]::Max(0, $job.Exp.Combos - $r)
        }
        $eta = ""
        if ($doneCombos -gt 0 -and $doneSeconds -gt 0) {
            $perCombo = $doneSeconds / $doneCombos
            $etaMin = [math]::Round((($leftQueue + $leftRun) * $perCombo) / $Parallel / 60, 0)
            $eta = " ETA ~$etaMin min"
        }
        Write-Log ("  stav: bezi {0}, hotovo {1}/{2} kombinaci{3}" -f $running.Count, $doneCombos, $totalCombos, $eta)
    }
}

$overall.Stop()
Write-Log ("KONEC runneru za {0} h" -f [math]::Round($overall.Elapsed.TotalHours, 2))
Write-Host ""
$script:status.Values | Sort-Object experiment |
    Select-Object experiment, combos, state, rows, seconds, note |
    Format-Table -AutoSize
