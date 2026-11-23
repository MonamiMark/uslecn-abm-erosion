#requires -Version 7
<#
  make_chunks.ps1 - generuje odvozené BehaviorSpace experimenty z existujicich.

  Podporuje vsechny tri zpusoby zadani hodnot v NetLogo 7:
    <enumeratedValueSet>   seznam hodnot
    <steppedValueSet>      first/step/last
    <subExperiment>        dalsi (krizene) sada promennych - napr. prohozeni plodin

  Rezimy:
    -Chunk   : rozdeli experiment po hladinach jedne (vnejsi) promenne, aby jeden
               proces nebezela 15 h. Kazdy chunk ma jen jednu hodnotu.
    -Freeze  : vsechny ostatni promenne na prvni hodnotu + jen prvni subExperiment
               (pro benchmark ceny scénare).

  Priklady:
    pwsh -File make_chunks.ps1 -List
    pwsh -File make_chunks.ps1 -Base p500p -Var stripe-length -Prefix "p500p_sl_" -Chunk
    pwsh -File make_chunks.ps1 -Base p500p -Var stripe-length -Prefix "bm_p500p_" -Freeze
    pwsh -File make_chunks.ps1 -Prefix "bm_" -Remove
#>
param(
    [string]$Base,
    [string]$Var,
    [string]$Prefix,
    [switch]$Chunk,
    [switch]$Freeze,
    [string[]]$Keep = @(),
    [switch]$List,
    [switch]$Remove,
    [string]$Model = ""
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Model) { $Model = Join-Path $here "usle_abm_model_LE_LFIX_RUN.nlogo" }

$enc = [System.Text.Encoding]::GetEncoding(1250)
$txt = [System.IO.File]::ReadAllText($Model, $enc)

$rxSet  = '(?s)<enumeratedValueSet variable="([^"]+)">(.*?)</enumeratedValueSet>'
$rxStep = '<steppedValueSet variable="([^"]+)" first="([^"]+)" step="([^"]+)" last="([^"]+)"\s*/>'
$rxSub  = '(?s)<subExperiment>(.*?)</subExperiment>'

function Get-Block([string]$name) {
    $rx = [regex]("(?s)<experiment name=`"$([regex]::Escape($name))`"([^>]*)>(.*?)</experiment>")
    $m = $rx.Match($txt)
    if (-not $m.Success) { throw "experiment '$name' nenalezen" }
    $m
}

function Expand-Step([string]$first, [string]$step, [string]$last) {
    $f = [double]$first; $s = [double]$step; $l = [double]$last
    $out = @()
    for ($v = $f; $v -le $l + 1e-9; $v += $s) { $out += [string]([math]::Round($v, 6)) }
    $out
}

# vrati hashtable promenna -> pole hodnot pro dany kus XML (jen primé sady, bez subExperimentu)
function Get-Sets([string]$xml) {
    $h = [ordered]@{}
    foreach ($mm in [regex]::Matches($xml, $rxSet)) {
        $vals = @([regex]::Matches($mm.Groups[2].Value, '<value value="([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
        $h[$mm.Groups[1].Value] = $vals
    }
    foreach ($mm in [regex]::Matches($xml, $rxStep)) {
        $h[$mm.Groups[1].Value] = Expand-Step $mm.Groups[2].Value $mm.Groups[3].Value $mm.Groups[4].Value
    }
    $h
}

function Get-Product($h) {
    $n = 1
    foreach ($k in $h.Keys) { $n *= [math]::Max(1, $h[$k].Count) }
    $n
}

# pocet kombinaci: top-level sady x soucin pres subExperimenty
function Get-Combos([string]$body) {
    $top = [regex]::Replace($body, $rxSub, "")
    $n = Get-Product (Get-Sets $top)
    foreach ($sm in [regex]::Matches($body, $rxSub)) {
        $n *= Get-Product (Get-Sets $sm.Groups[1].Value)
    }
    $n
}

function Get-SafeTag([string]$v) {
    $t = ($v -replace '"', '') -replace '[^A-Za-z0-9]+', '_'
    return $t.Trim('_')
}

function Set-SingleValue([string]$xml, [string]$var, [string]$val) {
    $rx = [regex]("(?s)<enumeratedValueSet variable=`"$([regex]::Escape($var))`">.*?</enumeratedValueSet>")
    $rep = "<enumeratedValueSet variable=`"$var`">`n      <value value=`"$val`"/>`n    </enumeratedValueSet>"
    $xml = $rx.Replace($xml, $rep, 1)
    $rxs = [regex]("(?s)<steppedValueSet variable=`"$([regex]::Escape($var))`"[^>]*/>")
    return $rxs.Replace($xml, $rep, 1)
}

if ($List) {
    foreach ($m in [regex]::Matches($txt, '<experiment name="([^"]+)"')) {
        $n = $m.Groups[1].Value
        $body = (Get-Block $n).Groups[2].Value
        Write-Host ("{0,-26} {1,6} kombinaci" -f $n, (Get-Combos $body))
    }
    return
}

if ($Remove) {
    if (-not $Prefix) { throw "pro -Remove je potreba -Prefix" }
    $rx = [regex]("(?s)\s*<experiment name=`"$([regex]::Escape($Prefix))[^`"]*`"[^>]*>.*?</experiment>")
    $before = ([regex]::Matches($txt, $rx)).Count
    [System.IO.File]::WriteAllText($Model, $rx.Replace($txt, ""), $enc)
    Write-Host "odstraneno $before experimentu s prefixem '$Prefix'"
    return
}

if (-not $Base -or -not $Var -or -not $Prefix) { throw "chybi -Base, -Var nebo -Prefix" }
if (-not ($Chunk -or $Freeze)) { throw "zadej -Chunk nebo -Freeze" }

$blk    = Get-Block $Base
$attrs  = $blk.Groups[1].Value
$body   = $blk.Groups[2].Value
$topXml = [regex]::Replace($body, $rxSub, "")
$topVars = Get-Sets $topXml

if (-not $topVars.Contains($Var)) { throw "promenna '$Var' neni na top-level v '$Base' (je uvnitr subExperiment?)" }

$blocks = @()
$report = @()
foreach ($val in $topVars[$Var]) {
    $newBody = $body
    if ($Freeze) {
        foreach ($k in $topVars.Keys) {
            if ($k -eq $Var) { continue }
            if ($Keep -contains $k) { continue }
            $newBody = Set-SingleValue $newBody $k $topVars[$k][0]
        }
        # jen prvni subExperiment
        $subs = [regex]::Matches($newBody, $rxSub)
        if ($subs.Count -gt 1) {
            for ($i = $subs.Count - 1; $i -ge 1; $i--) {
                $newBody = $newBody.Remove($subs[$i].Index, $subs[$i].Length)
            }
        }
    }
    $newBody = Set-SingleValue $newBody $Var $val

    $newName = "$Prefix$(Get-SafeTag $val)"
    $rxOld = [regex]("(?s)\s*<experiment name=`"$([regex]::Escape($newName))`"[^>]*>.*?</experiment>")
    $txt = $rxOld.Replace($txt, "", 1)
    $blocks += "  <experiment name=`"$newName`"$attrs>`n    $($newBody.Trim())`n  </experiment>"
    $report += [pscustomobject]@{ Name = $newName; Combo = (Get-Combos $newBody) }
}

$idx = $txt.LastIndexOf("</experiments>")
if ($idx -lt 0) { throw "</experiments> nenalezen" }
$txt = $txt.Substring(0, $idx) + ($blocks -join "`n") + "`n" + $txt.Substring($idx)
[System.IO.File]::WriteAllText($Model, $txt, $enc)

Write-Host ("zapsano {0} experimentu do {1}" -f $blocks.Count, (Split-Path -Leaf $Model))
$report | ForEach-Object { Write-Host ("   {0,-32} {1,5} kombinaci" -f $_.Name, $_.Combo) }
