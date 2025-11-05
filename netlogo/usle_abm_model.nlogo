;extenze
extensions [gis palette]
;globalni promenne
globals [
  elevation
  dmr-res ; rozliseni dmr
  flows-prepared?; indikator pripravenych toku
  land ; vse mimo oblasti ztraty - voda, hranice polygonu
  unique-CN
  base-CN
  sink
  barrier
  dmt-file
  cf-file
  cn-file
  plodiny-parametry
  total-erosion
  round-end
  inner-land
]

;patches
patches-own [
  patch-elevation
  patch-slope-per
  patch-slope-deg
  patch-aspect
  patch-k
  patch-c
  patch-cn
  patch-r
  patch-p
  flow-acc
  cnmod
  cn-ratio-base-sum
  cn-ratio-sum
  noflow?
  flows
  drain?
  balance
  patch-g
  patch-g2
  inner-land?
  ;patch-m
]
;turtles
turtles-own [
  frac
  cn-modifier
  cn-modifier-base

]


;Nacteni bloku
to setup
  clear-all
  reset-ticks
  set round-end false
  setup-interface

  ifelse not(test?) [
    ;morphology flow_direction
    ifelse substring morphology 0 2 = "ka" or substring morphology 0 2 = "ce" [
      set dmt-file (word morphology "f.asc")
      set soil ifelse-value substring morphology 0 2 = "ka" ["kambizem"]["černozem"]
    ]
    [
      set dmt-file (word morphology "_" flow_direction ".asc")
    ]

  ]
  [
    set dmt-file ("test.asc")
  ]


  print (word "DMT file:" dmt-file)

  ;let blok-file user-file
  ifelse file-exists? dmt-file [
    file-open dmt-file
    set elevation gis:load-dataset dmt-file

    let ncols 0
    let nrows 0
    let xllcorner 0
    let yllcorner 0
    let cellsize 0

    let line file-read-line
    print line
    set ncols read-from-string remove "NCOLS " line


    set line file-read-line

    set nrows read-from-string remove "NROWS " line
    set line file-read-line
    set xllcorner read-from-string remove "XLLCORNER " line
    set line file-read-line
    set yllcorner read-from-string remove "YLLCORNER " line
    set line file-read-line

    set cellsize read-from-string remove "CELLSIZE " line
    file-close
    print "Soubor nacten"
    print "Resizing world"
    set-patch-size 900 * 1 / (ncols * nrows) ^ 0.5
    resize-world 0 ncols - 1 0 nrows - 1
    set elevation gis:load-dataset dmt-file;
    gis:set-world-envelope gis:envelope-of elevation
    set dmr-res cellsize
    print "Surface ready!"

    setup-land
    set flows-prepared? false
  ]
  [
    print (word "Soubor " dmt-file "neexistuje!")
  ]

end


to load-CFCN
  ifelse debug? [
    set cf-file "C_debug.asc"
    let cf-file-r gis:load-dataset cf-file
    set cn-file "CN_debug.asc"
    let cn-file-r gis:load-dataset cn-file
    ask patches [
      set patch-c (gis:raster-sample cf-file-r self)
      set patch-cn (gis:raster-sample cn-file-r self)
    ]
  ]

  [
  ifelse (division = "single") [
    set cf-file "C_factor_uniform.asc"
  ]
  [ ifelse (division = "two") [
      set cf-file (word "C_two_" division_angle ".asc")
    ]
    [ ifelse (division = "stripes") [
        set cf-file (word "C_striped_" division_angle "_" stripe-length "m.asc")
      ][
        ifelse (division = "one110") [
          set cf-file (word "C_two_parts_" division_angle "_deg_110m_top.asc")
        ]
        [
        set cf-file (word "single_stripe_" division_angle "_" stripe-length "m.asc")
        ]
        ]
    ]
  ]

  let cf-file-r gis:load-dataset cf-file
  ask patches [
    set patch-c (gis:raster-sample cf-file-r self)
    ifelse (patch-c = 1) [
      set patch-c get-c-factor crop1
      set patch-cn get-cn-factor crop1

    ]
    [ if (patch-c = 2) [
        set patch-c get-c-factor crop2
        set patch-cn get-cn-factor crop2
      ]
    ]
  ]
  ]
  print word "CF and CN ready:" cf-file
end


to get-flow-accumulation
  load-CFCN
  repairCKCN
  if debug? [
    file-open "log5.txt"  ; Otevře soubor pro zápis
  ]
  ask patches [
      set flow-acc 1
      set cn-ratio-base-sum 0
      set cn-ratio-sum 0
  ]
  ;tri varianty algoritmu odtoku
  if not flows-prepared?[ prepare-flows ]
  ifelse WF? [
    ask patches [
      set cnmod []
    ]
    set unique-CN remove-duplicates [patch-cn] of patches
    print unique-CN
    foreach unique-CN [
      cnv ->
        set base-cn cnv
      if debug? [file-print (word "CN:" base-cn)]
;    set base-cn 81
        ask patches [
          set flow-acc 1
          set cn-ratio-base-sum 1  ;nastavime vsechny bunky referencniho odtoku na pomer 1, vsude je jedna plodina odpovidajici cf
          set cn-ratio-sum get-CN-modifier 1 ; pro vsechny bunky take nastavime skutecny pomer
          if debug? [
            if cn-ratio-sum > 1 [
            set cn-ratio-sum 2 ]
            if cn-ratio-sum < 1 [
            set cn-ratio-sum 0.5 ]
          ]
        ]
        ask land [
         ; vytvorime vektory
         prepare-turtles-Dall 1 cn-ratio-base-sum cn-ratio-sum
        ]
        turtles-move-forward
        print word "CN " base-cn
        ask patches [
            let uncn ifelse-value (cn-ratio-base-sum = 0) [1] [cn-ratio-sum / cn-ratio-base-sum]
            set cnmod lput uncn cnmod
        ]
      ]
    ]


  [
    ask land [
        set flow-acc 1
        prepare-turtles-Dall-base 1
    ]
    turtles-move-forward
  ]
  print "Flow accumulation surface ready!"
  color-patches-based-on-flow-acc

end

to repairCKCN
  ask patches with [not(patch-c > 0) and not(patch-c <= 0)][
    set patch-c 0
  ]
  ask patches with [not(patch-k > 0) and not(patch-k <= 0)][
    set patch-k 0
  ]
  ask patches with [not(patch-cn > 0) and not(patch-cn <= 0)][
    set patch-cn 1
  ]
  ask patches [
    set patch-cn round(patch-cn)
  ]
end

to prepare-flows
  print "Starting to prepare flows"
  ask land [
    let ee patch-elevation
    let neighbors-offsets [[-1 1] [0 1] [1 1] [-1 0] [1 0] [-1 -1] [0 -1] [1 -1]]
    let weights [0.354 0.5 0.354 0.5 0.5 0.354 0.5 0.354]

    let elevation-diffs []
    let slope-angles []

    foreach neighbors-offsets [ offset ->
      let neighbor patch-at (item 0 offset) (item 1 offset)

        let ele ee - [patch-elevation] of neighbor
        set elevation-diffs lput ele elevation-diffs
        ifelse not (member? neighbor sink)[
          set slope-angles lput [patch-slope-per] of neighbor slope-angles
        ]
        [
          set slope-angles lput ele slope-angles       ;pridavam svazitost z okolni bunky, jinak to neni mozne
        ]
    ]

    let slopes (map [ [diff weight] -> ifelse-value (diff > 0) [diff * weight * dmr-res] [0] ] elevation-diffs weights)
    let total-sum reduce + slopes

    let percent-distribution map [val -> ifelse-value (total-sum > 0) [val / total-sum] [0]] slopes

    let turning-point ifelse-value (patch-slope-per > 0.05)
      [0.3 * patch-slope-per]
      [0.5 * patch-slope-per]

    set flows (map [[angle per] ->
      ifelse-value (angle < turning-point and angle > 0)
        [-1 * per]
        [per]
    ] slope-angles percent-distribution)
  ]

  print "Flows prepared."
  set flows-prepared? true
end

;existuje nebezpeci, ze kdyz bunka nema kam smerovat, pak se zelva ani nevytvori a nic neodtece
to prepare-turtles-Dall [sum-flow cnm-base cnm]
  if (debug?) [ file-print (word "Pripravuju vektory" sum-flow "-" cnm-base "-" cnm)]
  ;pro vsechny vypoctene smery vetsi nez nula zjisti od
  (foreach flows [-1 0 1 -1 1 -1 0 1] [1 1 1 0 0 -1 -1 -1] [
    [flow row col] -> if flow > par-minfrac [
      let target-patch patch-at row col
      if not (target-patch = nobody) and [patch-elevation] of target-patch < patch-elevation [
        sprout 1 [
          set heading towards target-patch
          set color blue
          set frac sum-flow * flow
          set cn-modifier-base cnm-base * flow
          set cn-modifier cnm * flow
          if frac < par-minfrac[
              die
          ]
          if debug? [
            file-print (word "B:" cn-modifier-base "A:" cn-modifier)
          ]


       ]
      ]
      ]
  ])
end

to prepare-turtles-Dall-base [sum-flow]
  if debug? [ file-print (word "Pripravuju vektory klasicky" sum-flow)]
  ;pro vsechny vypoctene smery vetsi nez nula zjisti od
  (foreach flows [-1 0 1 -1 1 -1 0 1] [1 1 1 0 0 -1 -1 -1] [
    [flow row col] -> if flow > par-minfrac [
      let target-patch patch-at row col
      if not (target-patch = nobody) and [patch-elevation] of target-patch < patch-elevation [
        sprout 1 [
          set heading towards target-patch
          set color blue
          set frac sum-flow * flow
          if frac < par-minfrac[
              die
          ]
          if debug? [
            file-print (word "T:" frac)
          ]
       ]
      ]
      ]
  ])
end


to turtles-move-forward
  if debug? [ file-print "Posun vektorů"]
  ;posunu zelvy
  let tur turtle-set turtles
  ask tur [
    forward 1
  ]
  ;pokud je na kraji nebo v pasti, konci
  ask patches with [noflow? or drain?][
    ask turtles-here [die]
  ]

  ;aktualizuju flow acc
  let turtles-land land with [any? turtles-here]
  ask turtles-land [
    if debug? [ file-print (word "Ploska:" pxcor "," pycor)]
    let sum-flow sum [frac] of turtles-here
    if debug? [ file-print (word "Suma zelv:" sum-flow)]
    set flow-acc flow-acc + sum-flow
    if debug? [ file-print (word "Ploska FACC po aktualizaci:" flow-acc)]
    ifelse WF? [
      let sum-cn-modifier sum [cn-modifier] of turtles-here
      let sum-cn-modifier-base sum [cn-modifier-base] of turtles-here

      if debug? [
              file-print (word "cn-modifier pritok:" sum-cn-modifier)
                file-print (word "cn-modifier-base pritok:" sum-cn-modifier-base)
              ]

      set cn-ratio-sum cn-ratio-sum + sum-cn-modifier
      set cn-ratio-base-sum cn-ratio-base-sum + sum-cn-modifier-base

      ask turtles-here [
        die
      ]
      if debug? [
              file-print (word "cn-ratio-sum pritok:" cn-ratio-sum)
                file-print (word "cn-ratio-base-sum pritok:" cn-ratio-base-sum)
      ]


      prepare-turtles-Dall sum-flow sum-cn-modifier-base sum-cn-modifier
    ]
    [
      ask turtles-here [
        die
      ]
      prepare-turtles-Dall-base sum-flow
    ]

  ]
  ;koncim kdyz uz zelvy nejsou
  if any? turtles [
    turtles-move-forward
  ]
end






to color-patches-based-on-flow-acc
  let min-g min [flow-acc] of land
  let max-g max [flow-acc] of land

  ask patches [
    set pcolor scale-color red flow-acc max-g min-g
;    let rounded-value precision patch-g 1 ; Round patch-g to one decimal place
;    set plabel precision patch-g 1
  ]
end

;p2 is base
to-report get-CN-modifier [f-p]
  ifelse WF? [
    let s-p  CN-S patch-cn
    let r-p CN-R s-p

    let s-b CN-S base-CN
    let r-b CN-R s-b
    set r-b round(r-b * 10) / 10
    set r-p round(r-p * 10) / 10

    if r-p = 0 [report 0]; k zadne erozi nedojde, nebot tam nic nepritece!!
    if r-b = 0 [report 0]  ; Změna podmínky na r_b
    let rate (r-p / r-b)     ; Obrácený poměr
    report rate
  ]
  [
    report 1
  ]
end

to-report CN-S [cnp]
  report (25400 - 254 * cnp) / cnp
end

to-report CN-R [sp]
  if (0.2 * sp) > srazky-mm [report 0] ;pocatecni ztraty nemuzou byt vetsi nez srazka
  if (srazky-mm + 0.85 * sp) = 0 [type srazky-mm print word "ouha:" sp]
  report (srazky-mm - 0.2 * sp) ^ 2 / (srazky-mm + 0.85 * sp)
end

to setup-land
  ask patches [
    set patch-elevation (gis:raster-sample elevation self)
  ]
  ask patches [
    set drain? false
    set noflow? false
    set flow-acc 1
    set patch-c -1
    set patch-r 40
    set patch-k ifelse-value soil = "černozem" [0.41][0.33] ; černozem a kambizem
    set patch-p 1
    set balance 0
    set inner-land? false
  ]

  ask patches with-max [pxcor]  [
    set drain? true
  ]
  ask patches with-max [pycor]  [
    set drain? true
  ]
  ask patches with-min [pxcor]  [
    set drain? true
  ]
  ask patches with-min [pycor]  [
    set drain? true
  ]

  ask patches with [not (patch-elevation > 0 or patch-elevation <= 0)] [
    set drain? true
  ]

  set land patches with [not drain?]
  set sink patches with [drain?]

  ask patches [
    if (pxcor >= (min-pxcor + 5)  and pxcor <= (max-pxcor - 5) and pycor >= (min-pycor + 5) and pycor <= (max-pycor - 5)) [
      set inner-land? true  ; inner_land bude žluté barvy pro vizuální odlišení
    ]
  ]


  ask patches [
    if not any? neighbors with [patch-elevation < [patch-elevation] of myself] [
      set noflow? true
    ]
  ]


    set sink patches with [drain?]
    set land patches with [not drain?]
    set inner-land patches with [inner-land?]

    print "aktualizuji svazitost a aspekt"
    update-slope-and-aspect




    let min-ele min [patch-elevation] of land
    let max-ele max [patch-elevation] of land

    ask land [
      set pcolor scale-color brown patch-elevation max-ele min-ele
      set balance 0
  ]

  ask patches with [noflow? or drain?][
    set pcolor 9
  ]
   repairCKCN

end

;;;;;;;;;;;;;;;;;;;  ELEVATION ;;;;;;;;;;;;;;;

to update-slope-and-aspect
  ;[dz/dx] = ((c + 2f + i) - (a + 2d + g) / (8 * x_cellsize)
  ;[dz/dy] = ((g + 2h + i) - (a + 2b + c)) / (8 * y_cellsize)
  ask land [
    let a [patch-elevation] of patch-at -1 1
    let b [patch-elevation] of patch-at 0 1
    let c [patch-elevation] of patch-at 1 1
    let d [patch-elevation] of patch-at -1 0
    let ee patch-elevation
    let f [patch-elevation] of patch-at 1 0
    let g [patch-elevation] of patch-at -1 -1
    let h [patch-elevation] of patch-at 0 -1
    let i [patch-elevation] of patch-at 1 -1

    let dz-dy ((g + 2 * h + i) - (a + 2 * b + c)) / (8 * dmr-res); [dz/dy] y cellsize
    let dz-dx ((c + 2 * f + i) - (a + 2 * d + g)) / (8 * dmr-res); [dz/dx] x cellsize
    let dzxy (dz-dy ^ 2 + dz-dx ^ 2) ^ 0.5 ; prevyseni na metr
    set patch-slope-deg atan dzxy 1
    set patch-slope-per dzxy
    set patch-aspect atan (- dz-dx) dz-dy
    ;set patch-m calculate-m (patch-slope-per * 100)
  ]
end

to calculate-erosion
  repairCKCN
  set total-erosion 0
  ifelse WF? [
    ask land with [not noflow?][
      set patch-g2 usle-base-g2 self

    ]
    color-patches-based-on-g2
    set total-erosion mean [patch-g2] of land with [not noflow?]
  ]
  [
    ask land with [not noflow?][
      set patch-g usle-base-g self
    ]
    color-g
    set total-erosion mean [patch-g] of land with [not noflow?]
  ]

  type "Celkova eroze:" print total-erosion
  set round-end true
  if debug? [file-close]

end

;turtle context
to-report usle-base-g [p]
  let p-slope-deg [patch-slope-deg] of p
  let p-asp [patch-aspect] of p
  let beta sin p-slope-deg / (0.0896 * (3 * sin(p-slope-deg) ^ 0.8 + 0.56))
  let fa [flow-acc] of p
  let lf (fa / (22.13 * dmr-res * (abs (sin(p-asp)) + abs(cos(p-asp)))) ^ (beta / (beta + 1)))
  let sf -1.5 + 17 / (1 + exp(2.3 - 6.1 * sin(p-slope-deg)))
  report [patch-c] of p * [patch-r] of p * [patch-p] of p * [patch-k] of p * lf * sf
end

to color-g
  let min-g min [patch-g] of land
  let max-g max [patch-g] of land
  let s1 land with [patch-g <= 1]
  let s2 land with [patch-g <= 4 and patch-g > 1]
  let s3 land with [patch-g <= 9 and patch-g > 4]
  let s4 land with [patch-g <= 25 and patch-g > 9]
  let s5 land with [patch-g > 25]

  ask s1 [
    set pcolor 62
  ]
  ask s2 [
    set pcolor 57
  ]
    ask s3 [
    set pcolor 26
  ]
  ask s4 [
    set pcolor 15
  ]
  ask s5 [
    set pcolor 11
  ]
end

;patch context
to-report usle-base-g2 [p]
  let p-slope-deg [patch-slope-deg] of p
  let p-asp [patch-aspect] of p
  let beta sin p-slope-deg / (0.0896 * (3 * sin(p-slope-deg) ^ 0.8 + 0.56))
  let pos position [patch-cn] of p unique-CN
  let modi item pos [cnmod] of p

;  if pxcor = 89 and pycor = 90 [ print word "<<<" fa ]
;  let fa get-watershed p

  let lf (flow-acc * modi / (22.13 * dmr-res * (abs (sin(p-asp)) + abs(cos(p-asp)))) ^ (beta / (beta + 1)))
  let sf -1.5 + 17 / (1 + exp(2.3 - 6.1 * sin(p-slope-deg)))
  report [patch-c] of p * [patch-r] of p * [patch-p] of p * [patch-k] of p * lf * sf
end

to color-patches-based-on-g2
  let s1 land with [patch-g2 <= 1]
  let s2 land with [patch-g2 <= 4 and patch-g2 > 1]
  let s3 land with [patch-g2 <= 9 and patch-g2 > 4]
  let s4 land with [patch-g2 <= 25 and patch-g2 > 9]
  let s5 land with [patch-g2 > 25]

  ask s1 [
    set pcolor 62
  ]
  ask s2 [
    set pcolor 57
  ]
    ask s3 [
    set pcolor 26
  ]
  ask s4 [
    set pcolor 15
  ]
  ask s5 [
    set pcolor 11
  ]

end

to color-patches-based-on-c
  let min-g min [patch-c] of land
  let max-g max [patch-c] of land
  ask land [
    set pcolor scale-color red patch-c max-g min-g
  ]
end


to color-row [row prah]
  ask patches with [pycor = row]
  [
  let value [flow-acc] of self  ; Předpokládejme, že máte proměnnou s hodnotou

  ifelse value > prah
  [ set pcolor black ]
  [ set pcolor blue ]
  ; NEBO použití škály barev
  ;set pcolor scale-color red value 0 2
]

end

to setup-interface
  set plodiny-parametry [
    ["pšenice ozimá" 0.12 60.5 71.75]
    ["žito ozimé" 0.17 60.5 71.75]
    ["ječmen jarní" 0.15 60.5 71.75]
    ["ječmen ozimý" 0.17 60.5 71.75]
    ["oves" 0.1 60.5 71.75]
    ["kukuřice na zrno" 0.61 66.33 75.67]
    ["luštěniny" 0.05 59.5 72.17]
    ["brambory rané" 0.6 66.33 75.67]
    ["brambory pozdní" 0.44 66.33 75.67]
    ["louky" 0.005 30 58]
    ["chmelnice" 0.8 44 65.33]
    ["řepka ozimá" 0.22 66.33 75.67]
    ["slunečnice" 0.6 66.33 75.67]
    ["mák" 0.5 66.33 75.67]
    ["ostatní olejniny" 0.22 66.33 75.67]
    ["kukuřice na siláž" 0.72 66.33 75.67]
    ["ostatní pícniny jednoleté" 0.02 59.5 72.17]
    ["ostatní pícniny víceleté" 0.01 59.5 72.17]
    ["zelenina" 0.45 66.33 75.67]
    ["sady" 0.45 44 65.33]
  ]
end

to swap-crop
  let crop crop1
  set crop1 crop2
  set crop2 crop
end

to-report get-c-factor [nazev-plodiny]
  let vysledek filter [p -> first p = nazev-plodiny] plodiny-parametry
  ifelse not empty? vysledek
    [ report item 1 first vysledek ]
    [ report false ]
end

to-report get-cn-factor [nazev-plodiny]
  let vysledek filter [p -> first p = nazev-plodiny] plodiny-parametry
  ifelse not empty? vysledek
    [
      ifelse soil = "černozem"
        [ report item 2 first vysledek ]
        [
          ifelse soil = "kambizem"
            [ report item 3 first vysledek ]
            [ report false ]
        ]
    ]
    [ report false ]
end


to test-crop [cn?]
  setup-interface
  let parametr false
  ifelse cn? [
      set parametr get-cn-factor crop1
  ][
    set parametr get-c-factor crop1
  ]
  if parametr != false [
    print (word "Parametr pro " crop1 " je " parametr)
  ]
end

to export-to-asc
  let file-name "facc_concav_con.asc"
  let x-min 1506552
  let y-min 5533496
  let cell-size 5
  let no-data-value -9999

  file-open file-name

  ; Write header
  file-print (word "ncols " world-width)
  file-print (word "nrows " world-height)
  file-print (word "xllcorner " x-min)
  file-print (word "yllcorner " y-min)
  file-print (word "cellsize " cell-size)
  file-print (word "NODATA_value " no-data-value)

  ; Write data
  let y world-height - 1
  while [y >= 0] [
    let x 0
    while [x < world-width] [
      ask patch x y [
        ifelse drain?
        [ file-type no-data-value ]
        [ file-type flow-acc ]
      ]
      if x < (world-width - 1) [ file-type " " ]
      set x x + 1
    ]
    file-print ""
    set y y - 1
  ]

  file-close
  print "ASC file exported successfully!"
end


to-report calculate-m [slope-percent]
  ;let max-slope 30  ; maximální uvažovaný sklon v procentech
  if slope-percent <= 5 [
      report 0.1 + (slope-percent / 5) * 0.1  ; lineární interpolace mezi 0.1 a 0.2
  ]
  if (slope-percent > 5) and (slope-percent <= 15) [
      report 0.3 + ((slope-percent - 5) / 10) * 0.2  ; lineární interpolace mezi 0.3 a 0.5
  ]
  if (slope-percent > 15) and (slope-percent <= 30) [
      report 0.6 + ((slope-percent - 15) / 15) * 0.2  ; lineární interpolace mezi 0.6 a 0.8
  ]
  report 0.8 ; pro svahy vetsi nez 30%
end

to-report highest-c-factor-representation
  let low-threshold min [patch-elevation] of land + stripe-length / 10 ; nastav hranici pro "nízkou část svahu"
  let low-patches land with [patch-elevation <= low-threshold]

  let unique-c-factors remove-duplicates [patch-c] of low-patches ; zjištění unikátních hodnot C faktorů

  let highest-c-factor max unique-c-factors ; najdi nejvyšší C faktor

  let total-low-patches count low-patches ; celkový počet plošek v nízké části svahu

  let count-highest-c-factor count low-patches with [patch-c = highest-c-factor] ; počet plošek s nejvyšším C faktorem

  let ratio-highest-c-factor count-highest-c-factor / total-low-patches ; relativní podíl nejvyššího C faktoru

  report ratio-highest-c-factor ; vrátí seznam: nejvyšší C faktor a jeho relativní podíl
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
1118
919
-1
-1
7.5
1
10
1
1
1
0
0
0
1
0
119
0
119
0
0
1
ticks
30.0

BUTTON
35
128
166
161
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
36
169
167
202
NIL
load-CFCN
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
19
308
189
341
WF?
WF?
1
1
-1000

BUTTON
37
214
168
247
flow accumulation
get-flow-accumulation 
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
38
256
168
289
NIL
calculate-erosion
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
18
515
192
560
morphology
morphology
"plane" "convex" "concave" "ce1" "ce2" "ce3" "ce4" "ce5" "ka1" "ka2" "ka3" "ka4" "ka5"
0

CHOOSER
18
580
194
625
flow_direction
flow_direction
"parallel" "divergent" "convergent"
1

SLIDER
19
464
191
497
division_angle
division_angle
0
90
90.0
10
1
NIL
HORIZONTAL

MONITOR
16
10
191
55
DMT
dmt-file
17
1
11

CHOOSER
19
352
191
397
division
division
"single" "two" "stripes" "stripe-inside" "one110"
4

MONITOR
16
58
190
103
CF
cf-file
17
1
11

INPUTBOX
18
651
191
711
par-minfrac
0.0
1
0
Number

CHOOSER
1141
56
1315
101
crop1
crop1
"pšenice ozimá" "žito ozimé" "ječmen jarní" "ječmen ozimý" "oves" "kukuřice na zrno" "luštěniny" "brambory rané" "brambory pozdní" "louky" "chmelnice" "řepka ozimá" "slunečnice" "mák" "ostatní olejniny" "kukuřice na siláž" "ostatní pícniny jednoleté" "ostatní pícniny víceleté" "zelenina" "sady"
5

CHOOSER
1141
114
1319
159
crop2
crop2
"pšenice ozimá" "žito ozimé" "ječmen jarní" "ječmen ozimý" "oves" "kukuřice na zrno" "luštěniny" "brambory rané" "brambory pozdní" "louky" "chmelnice" "řepka ozimá" "slunečnice" "mák" "ostatní olejniny" "kukuřice na siláž" "ostatní pícniny jednoleté" "ostatní pícniny víceleté" "zelenina" "sady"
0

BUTTON
1171
173
1273
206
<>
swap-crop
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
1183
390
1306
423
NIL
test-crop false
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
1170
10
1320
35
Plodiny
20
0.0
1

TEXTBOX
1176
246
1326
271
Půda
20
0.0
1

CHOOSER
1143
292
1317
337
soil
soil
"černozem" "kambizem"
1

BUTTON
1172
624
1276
657
Export Facc
export-to-asc
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SWITCH
1175
501
1278
534
test?
test?
1
1
-1000

CHOOSER
19
407
190
452
stripe-length
stripe-length
10 20 25 30 36 40 50 72 75 80 100 108 125 144 150 175 180 200 216 250
1

SWITCH
1171
575
1274
608
debug?
debug?
1
1
-1000

INPUTBOX
17
723
193
783
srazky-mm
40.0
1
0
Number

MONITOR
18
820
191
865
pd
highest-c-factor-representation
17
1
11

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="false">
    <go>setup
get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;convergent&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;single&quot;"/>
      <value value="&quot;two&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp_two_angles_standard" repetitions="1" runMetricsEveryStep="false">
    <go>setup
get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;two&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="10"/>
      <value value="20"/>
      <value value="30"/>
      <value value="40"/>
      <value value="50"/>
      <value value="60"/>
      <value value="70"/>
      <value value="80"/>
      <value value="90"/>
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="exp_two_angles_all" repetitions="1" runMetricsEveryStep="false">
    <go>setup
get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;two&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="10"/>
      <value value="20"/>
      <value value="30"/>
      <value value="40"/>
      <value value="50"/>
      <value value="60"/>
      <value value="70"/>
      <value value="80"/>
      <value value="90"/>
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment2" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="par-minfrac">
      <value value="0.05"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;two&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;convex&quot;"/>
      <value value="&quot;plane&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="division_angle" first="0" step="10" last="90"/>
  </experiment>
  <experiment name="experiment2 (copy)" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;two&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;convex&quot;"/>
      <value value="&quot;plane&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="division_angle" first="0" step="10" last="90"/>
  </experiment>
  <experiment name="ex_pasy" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;convergent&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;convex&quot;"/>
      <value value="&quot;plane&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="division_angle" first="0" step="10" last="90"/>
  </experiment>
  <experiment name="pasy_srazky" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;convergent&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;convex&quot;"/>
      <value value="&quot;plane&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="division_angle" first="0" step="10" last="90"/>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
      <value value="36"/>
      <value value="50"/>
      <value value="72"/>
      <value value="100"/>
      <value value="108"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="10"/>
      <value value="20"/>
      <value value="30"/>
      <value value="40"/>
      <value value="50"/>
    </enumeratedValueSet>
    <subExperiment>
      <enumeratedValueSet variable="crop1">
        <value value="&quot;pšenice ozimá&quot;"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="crop2">
        <value value="&quot;kukuřice na siláž&quot;"/>
      </enumeratedValueSet>
    </subExperiment>
    <subExperiment>
      <enumeratedValueSet variable="crop2">
        <value value="&quot;pšenice ozimá&quot;"/>
      </enumeratedValueSet>
      <enumeratedValueSet variable="crop1">
        <value value="&quot;kukuřice na siláž&quot;"/>
      </enumeratedValueSet>
    </subExperiment>
  </experiment>
  <experiment name="ex_pasy_po_10" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;convergent&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;convex&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="division_angle" first="0" step="10" last="90"/>
    <enumeratedValueSet variable="stripe-length">
      <value value="30"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="ex_pasy_obracene" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;convergent&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;convex&quot;"/>
      <value value="&quot;plane&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="division_angle" first="0" step="10" last="90"/>
    <enumeratedValueSet variable="stripe-length">
      <value value="36"/>
      <value value="50"/>
      <value value="72"/>
      <value value="100"/>
      <value value="108"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="ex_pasy_obracene_25" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;parallel&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;convergent&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;convex&quot;"/>
      <value value="&quot;plane&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="division_angle" first="0" step="10" last="90"/>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="pasy_srazky_test" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="eKP2" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="36"/>
      <value value="72"/>
      <value value="108"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;ka1&quot;"/>
      <value value="&quot;ka2&quot;"/>
      <value value="&quot;ka3&quot;"/>
      <value value="&quot;ka4&quot;"/>
      <value value="&quot;ka5&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="10"/>
      <value value="30"/>
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="cernozemePK" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
      <value value="50"/>
      <value value="125"/>
      <value value="250"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;ce1&quot;"/>
      <value value="&quot;ce2&quot;"/>
      <value value="&quot;ce3&quot;"/>
      <value value="&quot;ce4&quot;"/>
      <value value="&quot;ce5&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="ePKnt" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="36"/>
      <value value="72"/>
      <value value="108"/>
      <value value="144"/>
      <value value="180"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="10"/>
      <value value="30"/>
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="eKPnt" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="36"/>
      <value value="72"/>
      <value value="108"/>
      <value value="144"/>
      <value value="180"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="10"/>
      <value value="30"/>
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="eKPntTwo" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;two&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="10"/>
      <value value="30"/>
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="eKPntTwo (copy)" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;two&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="10"/>
      <value value="30"/>
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="ePKnt288" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="36"/>
      <value value="72"/>
      <value value="144"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="10"/>
      <value value="30"/>
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="eKPnt288_2" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="36"/>
      <value value="72"/>
      <value value="144"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="10"/>
      <value value="30"/>
      <value value="50"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="p400s1p" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
      <value value="50"/>
      <value value="100"/>
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="p400s1k" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
      <value value="50"/>
      <value value="100"/>
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="cernozemeKP" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
      <value value="50"/>
      <value value="125"/>
      <value value="250"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;ce1&quot;"/>
      <value value="&quot;ce2&quot;"/>
      <value value="&quot;ce3&quot;"/>
      <value value="&quot;ce4&quot;"/>
      <value value="&quot;ce5&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="cernozemeKP250" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="250"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;ce1&quot;"/>
      <value value="&quot;ce2&quot;"/>
      <value value="&quot;ce3&quot;"/>
      <value value="&quot;ce4&quot;"/>
      <value value="&quot;ce5&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="cernozemePK250" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="250"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;ce1&quot;"/>
      <value value="&quot;ce2&quot;"/>
      <value value="&quot;ce3&quot;"/>
      <value value="&quot;ce4&quot;"/>
      <value value="&quot;ce5&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="kambizemeKP" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
      <value value="50"/>
      <value value="125"/>
      <value value="250"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;ka1&quot;"/>
      <value value="&quot;ka2&quot;"/>
      <value value="&quot;ka3&quot;"/>
      <value value="&quot;ka4&quot;"/>
      <value value="&quot;ka5&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="15"/>
      <value value="30"/>
      <value value="45"/>
      <value value="60"/>
      <value value="75"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="kambizemePK" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
      <value value="50"/>
      <value value="125"/>
      <value value="250"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;ka1&quot;"/>
      <value value="&quot;ka2&quot;"/>
      <value value="&quot;ka3&quot;"/>
      <value value="&quot;ka4&quot;"/>
      <value value="&quot;ka5&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="p288p" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="36"/>
      <value value="72"/>
      <value value="144"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="p288k" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="36"/>
      <value value="72"/>
      <value value="144"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="p500p" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
      <value value="50"/>
      <value value="125"/>
      <value value="250"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="p500k" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="25"/>
      <value value="50"/>
      <value value="125"/>
      <value value="250"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripes&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="20"/>
      <value value="50"/>
      <value value="70"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="p400PU" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;ostatní pícniny jednoleté&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stripe-length">
      <value value="10"/>
      <value value="20"/>
      <value value="40"/>
      <value value="80"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;stripe-inside&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="15"/>
      <value value="30"/>
      <value value="45"/>
      <value value="60"/>
      <value value="75"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="blok600d" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>get-flow-accumulation
calculate-erosion</go>
    <exitCondition>round-end = true</exitCondition>
    <metric>total-erosion</metric>
    <metric>highest-c-factor-representation</metric>
    <enumeratedValueSet variable="crop1">
      <value value="&quot;kukuřice na zrno&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="crop2">
      <value value="&quot;pšenice ozimá&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division">
      <value value="&quot;one110&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="WF?">
      <value value="false"/>
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="morphology">
      <value value="&quot;plane&quot;"/>
      <value value="&quot;convex&quot;"/>
      <value value="&quot;concave&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="flow_direction">
      <value value="&quot;convergent&quot;"/>
      <value value="&quot;divergent&quot;"/>
      <value value="&quot;parallel&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="soil">
      <value value="&quot;černozem&quot;"/>
      <value value="&quot;kambizem&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="division_angle">
      <value value="0"/>
      <value value="15"/>
      <value value="30"/>
      <value value="45"/>
      <value value="60"/>
      <value value="75"/>
      <value value="90"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="srazky-mm">
      <value value="30"/>
      <value value="60"/>
      <value value="120"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
