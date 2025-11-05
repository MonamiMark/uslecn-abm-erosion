<?xml version="1.0" encoding="utf-8"?>
<model version="NetLogo 7.0.2" snapToGrid="false">
  <code><![CDATA[; extensions
extensions [gis palette]

; globals
globals [
  elevation
  dmr-res                ; DEM resolution
  flows-prepared?        ; indicator that flow directions/weights are prepared
  land                   ; all non-sink area (excludes water and polygon boundaries)
  unique-CN
  base-CN
  sink
  barrier
  dmt-file
  cf-file
  cn-file
  plodiny-parametry      ; crop parameters table
  total-erosion
  round-end
  inner-land
]

; patches
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
  ; patch-m
]

; turtles
turtles-own [
  frac
  cn-modifier
  cn-modifier-base
]

; Load block / setup
to setup
  clear-all
  reset-ticks
  set round-end false
  setup-interface

  ifelse not(test?) [
    ; morphology + flow_direction
    ifelse substring morphology 0 2 = "ka" or substring morphology 0 2 = "ce" [
      set dmt-file (word morphology "f.asc")
      set soil ifelse-value substring morphology 0 2 = "ka" ["cambisol"]["chernozem"]
    ]
    [
      set dmt-file (word morphology "_" flow_direction ".asc")
    ]
  ]
  [
    set dmt-file ("test.asc")
  ]

  print (word "DEM file: " dmt-file)

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

    print "File loaded."
    print "Resizing world"
    set-patch-size 900 * 1 / (ncols * nrows) ^ 0.5
    resize-world 0 ncols - 1 0 nrows - 1
    set elevation gis:load-dataset dmt-file
    gis:set-world-envelope gis:envelope-of elevation
    set dmr-res cellsize
    print "Surface ready!"

    setup-land
    set flows-prepared? false
  ]
  [
    print (word "File " dmt-file " does not exist!")
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
  print word "C and CN ready: " cf-file
end

to get-flow-accumulation
  load-CFCN
  repairCKCN
  if debug? [
    file-open "log5.txt"
  ]
  ask patches [
    set flow-acc 1
    set cn-ratio-base-sum 0
    set cn-ratio-sum 0
  ]
  ; three variants of the outflow algorithm
  if not flows-prepared? [ prepare-flows ]
  ifelse WF? [
    ask patches [ set cnmod [] ]
    set unique-CN remove-duplicates [patch-cn] of patches
    print unique-CN
    foreach unique-CN [
      cnv ->
      set base-cn cnv
      if debug? [file-print (word "CN: " base-cn)]

      ask patches [
        set flow-acc 1
        set cn-ratio-base-sum 1                  ; reference ratio set to 1 where a single crop matches cf
        set cn-ratio-sum get-CN-modifier 1       ; actual ratio for all patches
        if debug? [
          if cn-ratio-sum > 1 [ set cn-ratio-sum 2 ]
          if cn-ratio-sum < 1 [ set cn-ratio-sum 0.5 ]
        ]
      ]
      ask land [
        ; create flow vectors
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
  ask patches with [not(patch-c > 0) and not(patch-c <= 0)][ set patch-c 0 ]
  ask patches with [not(patch-k > 0) and not(patch-k <= 0)][ set patch-k 0 ]
  ask patches with [not(patch-cn > 0) and not(patch-cn <= 0)][ set patch-cn 1 ]
  ask patches [ set patch-cn round(patch-cn) ]
end

to prepare-flows
  print "Preparing flow directions/weights..."
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
      ifelse not (member? neighbor sink) [
        set slope-angles lput [patch-slope-per] of neighbor slope-angles
      ]
      [
        set slope-angles lput ele slope-angles    ; inject neighbor slope; otherwise not possible
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

; If a patch has nowhere to flow, no turtle is created and nothing flows out
to prepare-turtles-Dall [sum-flow cnm-base cnm]
  if (debug?) [ file-print (word "Preparing vectors " sum-flow "-" cnm-base "-" cnm)]
  ; for all positive outgoing directions
  (foreach flows [-1 0 1 -1 1 -1 0 1] [1 1 1 0 0 -1 -1 -1] [
    [flow row col] ->
    if flow > par-minfrac [
      let target-patch patch-at row col
      if not (target-patch = nobody) and [patch-elevation] of target-patch < patch-elevation [
        sprout 1 [
          set heading towards target-patch
          set color blue
          set frac sum-flow * flow
          set cn-modifier-base cnm-base * flow
          set cn-modifier cnm * flow
          if frac < par-minfrac [ die ]
          if debug? [ file-print (word "B: " cn-modifier-base " A: " cn-modifier) ]
        ]
      ]
    ]
  ])
end

to prepare-turtles-Dall-base [sum-flow]
  if debug? [ file-print (word "Preparing vectors (baseline) " sum-flow)]
  (foreach flows [-1 0 1 -1 1 -1 0 1] [1 1 1 0 0 -1 -1 -1] [
    [flow row col] ->
    if flow > par-minfrac [
      let target-patch patch-at row col
      if not (target-patch = nobody) and [patch-elevation] of target-patch < patch-elevation [
        sprout 1 [
          set heading towards target-patch
          set color blue
          set frac sum-flow * flow
          if frac < par-minfrac [ die ]
          if debug? [ file-print (word "T: " frac) ]
        ]
      ]
    ]
  ])
end

to turtles-move-forward
  if debug? [ file-print "Moving vectors (turtles)" ]
  ask turtle-set turtles [ forward 1 ]

  ; kill turtles at sinks or where no outflow exists
  ask patches with [noflow? or drain?] [
    ask turtles-here [die]
  ]

  ; update flow accumulation
  let turtles-land land with [any? turtles-here]
  ask turtles-land [
    if debug? [ file-print (word "Patch: " pxcor "," pycor)]
    let sum-flow sum [frac] of turtles-here
    if debug? [ file-print (word "Flow sum (turtles): " sum-flow)]
    set flow-acc flow-acc + sum-flow
    if debug? [ file-print (word "Flow-acc after update: " flow-acc)]

    ifelse WF? [
      let sum-cn-modifier sum [cn-modifier] of turtles-here
      let sum-cn-modifier-base sum [cn-modifier-base] of turtles-here

      if debug? [
        file-print (word "cn-modifier inflow: " sum-cn-modifier)
        file-print (word "cn-modifier-base inflow: " sum-cn-modifier-base)
      ]

      set cn-ratio-sum cn-ratio-sum + sum-cn-modifier
      set cn-ratio-base-sum cn-ratio-base-sum + sum-cn-modifier-base

      ask turtles-here [ die ]

      if debug? [
        file-print (word "cn-ratio-sum inflow: " cn-ratio-sum)
        file-print (word "cn-ratio-base-sum inflow: " cn-ratio-base-sum)
      ]

      prepare-turtles-Dall sum-flow sum-cn-modifier-base sum-cn-modifier
    ]
    [
      ask turtles-here [ die ]
      prepare-turtles-Dall-base sum-flow
    ]
  ]

  ; recurse until no turtles remain
  if any? turtles [
    turtles-move-forward
  ]
end

to color-patches-based-on-flow-acc
  let min-g min [flow-acc] of land
  let max-g max [flow-acc] of land
  ask patches [
    set pcolor scale-color red flow-acc max-g min-g
  ]
end

; p2 is base
to-report get-CN-modifier [f-p]
  ifelse WF? [
    let s-p  CN-S patch-cn
    let r-p CN-R s-p

    let s-b CN-S base-CN
    let r-b CN-R s-b
    set r-b round(r-b * 10) / 10
    set r-p round(r-p * 10) / 10

    if r-p = 0 [report 0]   ; no erosion because no runoff reaches the patch
    if r-b = 0 [report 0]
    let rate (r-p / r-b)
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
  if (0.2 * sp) > srazky-mm [report 0]         ; initial abstraction cannot exceed rainfall
  if (srazky-mm + 0.85 * sp) = 0 [type srazky-mm print word "warning: " sp]
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
    set patch-k ifelse-value soil = "chernozem" [0.41][0.33] ; chernozem vs cambisol
    set patch-p 1
    set balance 0
    set inner-land? false
  ]

  ask patches with-max [pxcor]  [ set drain? true ]
  ask patches with-max [pycor]  [ set drain? true ]
  ask patches with-min [pxcor]  [ set drain? true ]
  ask patches with-min [pycor]  [ set drain? true ]

  ask patches with [not (patch-elevation > 0 or patch-elevation <= 0)] [
    set drain? true
  ]

  set land patches with [not drain?]
  set sink patches with [drain?]

  ask patches [
    if (pxcor >= (min-pxcor + 5) and pxcor <= (max-pxcor - 5) and pycor >= (min-pycor + 5) and pycor <= (max-pycor - 5)) [
      set inner-land? true
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

  print "Updating slope and aspect..."
  update-slope-and-aspect

  let min-ele min [patch-elevation] of land
  let max-ele max [patch-elevation] of land

  ask land [
    set pcolor scale-color brown patch-elevation max-ele min-ele
    set balance 0
  ]

  ask patches with [noflow? or drain?] [
    set pcolor 9
  ]
  repairCKCN
end

;;;;  ELEVATION ;;;;

to update-slope-and-aspect
  ; [dz/dx] = ((c + 2f + i) - (a + 2d + g)) / (8 * x_cellsize)
  ; [dz/dy] = ((g + 2h + i) - (a + 2b + c)) / (8 * y_cellsize)
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

    let dz-dy ((g + 2 * h + i) - (a + 2 * b + c)) / (8 * dmr-res)
    let dz-dx ((c + 2 * f + i) - (a + 2 * d + g)) / (8 * dmr-res)
    let dzxy (dz-dy ^ 2 + dz-dx ^ 2) ^ 0.5
    set patch-slope-deg atan dzxy 1
    set patch-slope-per dzxy
    set patch-aspect atan (- dz-dx) dz-dy
    ; set patch-m calculate-m (patch-slope-per * 100)
  ]
end

to calculate-erosion
  repairCKCN
  set total-erosion 0
  ifelse WF? [
    ask land with [not noflow?] [
      set patch-g2 usle-base-g2 self
    ]
    color-patches-based-on-g2
    set total-erosion mean [patch-g2] of land with [not noflow?]
  ]
  [
    ask land with [not noflow?] [
      set patch-g usle-base-g self
    ]
    color-g
    set total-erosion mean [patch-g] of land with [not noflow?]
  ]

  type "Total erosion: " print total-erosion
  set round-end true
  if debug? [file-close]
end

; turtle context
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

  ask s1 [ set pcolor 62 ]
  ask s2 [ set pcolor 57 ]
  ask s3 [ set pcolor 26 ]
  ask s4 [ set pcolor 15 ]
  ask s5 [ set pcolor 11 ]
end

; patch context
to-report usle-base-g2 [p]
  let p-slope-deg [patch-slope-deg] of p
  let p-asp [patch-aspect] of p
  let beta sin p-slope-deg / (0.0896 * (3 * sin(p-slope-deg) ^ 0.8 + 0.56))
  let pos position [patch-cn] of p unique-CN
  let modi item pos [cnmod] of p

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

  ask s1 [ set pcolor 62 ]
  ask s2 [ set pcolor 57 ]
  ask s3 [ set pcolor 26 ]
  ask s4 [ set pcolor 15 ]
  ask s5 [ set pcolor 11 ]
end

to color-patches-based-on-c
  let min-g min [patch-c] of land
  let max-g max [patch-c] of land
  ask land [
    set pcolor scale-color red patch-c max-g min-g
  ]
end

to color-row [row threshold]
  ask patches with [pycor = row] [
    let value [flow-acc] of self
    ifelse value > threshold
    [ set pcolor black ]
    [ set pcolor blue ]
  ]
end

to setup-interface
  set plodiny-parametry [
    ["winter wheat" 0.12 60.5 71.75]
    ["winter rye" 0.17 60.5 71.75]
    ["spring barley" 0.15 60.5 71.75]
    ["winter barley" 0.17 60.5 71.75]
    ["oats" 0.1 60.5 71.75]
    ["grain maize" 0.61 66.33 75.67]
    ["legumes" 0.05 59.5 72.17]
    ["early potatoes" 0.6 66.33 75.67]
    ["late potatoes" 0.44 66.33 75.67]
    ["grassland" 0.005 30 58]
    ["hop gardens" 0.8 44 65.33]
    ["winter rapeseed" 0.22 66.33 75.67]
    ["sunflower" 0.6 66.33 75.67]
    ["poppy" 0.5 66.33 75.67]
    ["other oilseeds" 0.22 66.33 75.67]
    ["silage maize" 0.72 66.33 75.67]
    ["other annual forages" 0.02 59.5 72.17]
    ["other perennial forages" 0.01 59.5 72.17]
    ["vegetables" 0.45 66.33 75.67]
    ["orchards" 0.45 44 65.33]
  ]
end

to swap-crop
  let crop crop1
  set crop1 crop2
  set crop2 crop
end

to-report get-c-factor [crop-name]
  let res filter [p -> first p = crop-name] plodiny-parametry
  ifelse not empty? res
    [ report item 1 first res ]
    [ report false ]
end

to-report get-cn-factor [crop-name]
  let res filter [p -> first p = crop-name] plodiny-parametry
  ifelse not empty? res
    [
      ifelse soil = "chernozem"
      [ report item 2 first res ]
      [
        ifelse soil = "cambisol"
        [ report item 3 first res ]
        [ report false ]
      ]
    ]
    [ report false ]
end

to test-crop [cn?]
  setup-interface
  let param false
  ifelse cn? [
    set param get-cn-factor crop1
  ][
    set param get-c-factor crop1
  ]
  if param != false [
    print (word "Parameter for " crop1 " is " param)
  ]
end

to export-to-asc
  let file-name "facc_concav_con.asc"
  let x-min 1506552
  let y-min 5533496
  let cell-size 5
  let no-data-value -9999

  file-open file-name

  ; header
  file-print (word "ncols " world-width)
  file-print (word "nrows " world-height)
  file-print (word "xllcorner " x-min)
  file-print (word "yllcorner " y-min)
  file-print (word "cellsize " cell-size)
  file-print (word "NODATA_value " no-data-value)

  ; data (written from top row to bottom)
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
  if slope-percent <= 5 [
    report 0.1 + (slope-percent / 5) * 0.1
  ]
  if (slope-percent > 5) and (slope-percent <= 15) [
    report 0.3 + ((slope-percent - 5) / 10) * 0.2
  ]
  if (slope-percent > 15) and (slope-percent <= 30) [
    report 0.6 + ((slope-percent - 15) / 15) * 0.2
  ]
  report 0.8 ; for slopes > 30%
end

to-report highest-c-factor-representation
  ; ratio of highest C-factor representation in the lower part of the slope
  let low-threshold min [patch-elevation] of land + stripe-length / 10
  let low-patches land with [patch-elevation <= low-threshold]

  let unique-c-factors remove-duplicates [patch-c] of low-patches
  let highest-c-factor max unique-c-factors

  let total-low-patches count low-patches
  let count-highest-c-factor count low-patches with [patch-c = highest-c-factor]
  let ratio-highest-c-factor count-highest-c-factor / total-low-patches

  report ratio-highest-c-factor
end]]></code>
  <widgets>
    <view x="210" wrappingAllowedX="false" y="10" frameRate="30.0" minPycor="0" height="904" showTickCounter="true" patchSize="7.5" fontSize="10" wrappingAllowedY="false" width="904" tickCounterLabel="ticks" maxPycor="119" updateMode="0" maxPxcor="119" minPxcor="0"></view>
    <button x="35" y="160" height="40" disableUntilTicks="false" forever="false" kind="Observer" width="131">setup</button>
    <button x="36" y="208" height="40" disableUntilTicks="false" forever="false" kind="Observer" width="131">load-CFCN</button>
    <switch x="19" y="368" height="40" on="false" variable="WF?" width="170" display="WF?"></switch>
    <button x="37" y="260" height="40" disableUntilTicks="false" forever="false" kind="Observer" width="131" display="flow accumulation">get-flow-accumulation </button>
    <button x="38" y="309" height="40" disableUntilTicks="false" forever="false" kind="Observer" width="130">calculate-erosion</button>
    <chooser x="18" y="629" height="60" variable="morphology" current="0" width="174" display="morphology">
      <choice type="string" value="plane"></choice>
      <choice type="string" value="convex"></choice>
      <choice type="string" value="concave"></choice>
      <choice type="string" value="ce1"></choice>
      <choice type="string" value="ce2"></choice>
      <choice type="string" value="ce3"></choice>
      <choice type="string" value="ce4"></choice>
      <choice type="string" value="ce5"></choice>
      <choice type="string" value="ka1"></choice>
      <choice type="string" value="ka2"></choice>
      <choice type="string" value="ka3"></choice>
      <choice type="string" value="ka4"></choice>
      <choice type="string" value="ka5"></choice>
    </chooser>
    <chooser x="18" y="709" height="60" variable="flow_direction" current="1" width="176" display="flow_direction">
      <choice type="string" value="parallel"></choice>
      <choice type="string" value="divergent"></choice>
      <choice type="string" value="convergent"></choice>
    </chooser>
    <slider x="19" step="10" y="561" max="90" width="172" display="division_angle" height="50" min="0" direction="Horizontal" default="90.0" variable="division_angle"></slider>
    <monitor x="16" precision="17" y="10" height="60" fontSize="11" width="175" display="DMT">dmt-file</monitor>
    <chooser x="19" y="419" height="60" variable="division" current="4" width="172" display="division">
      <choice type="string" value="single"></choice>
      <choice type="string" value="two"></choice>
      <choice type="string" value="stripes"></choice>
      <choice type="string" value="stripe-inside"></choice>
      <choice type="string" value="one110"></choice>
    </chooser>
    <monitor x="16" precision="17" y="75" height="60" fontSize="11" width="174" display="CF">cf-file</monitor>
    <input x="18" multiline="false" y="795" height="60" variable="par-minfrac" type="number" width="173">0.0</input>
    <chooser x="1141" y="56" height="60" variable="crop1" current="5" width="174" display="crop1">
      <choice type="string" value="pšenice ozimá"></choice>
      <choice type="string" value="žito ozimé"></choice>
      <choice type="string" value="ječmen jarní"></choice>
      <choice type="string" value="ječmen ozimý"></choice>
      <choice type="string" value="oves"></choice>
      <choice type="string" value="kukuřice na zrno"></choice>
      <choice type="string" value="luštěniny"></choice>
      <choice type="string" value="brambory rané"></choice>
      <choice type="string" value="brambory pozdní"></choice>
      <choice type="string" value="louky"></choice>
      <choice type="string" value="chmelnice"></choice>
      <choice type="string" value="řepka ozimá"></choice>
      <choice type="string" value="slunečnice"></choice>
      <choice type="string" value="mák"></choice>
      <choice type="string" value="ostatní olejniny"></choice>
      <choice type="string" value="kukuřice na siláž"></choice>
      <choice type="string" value="ostatní pícniny jednoleté"></choice>
      <choice type="string" value="ostatní pícniny víceleté"></choice>
      <choice type="string" value="zelenina"></choice>
      <choice type="string" value="sady"></choice>
    </chooser>
    <chooser x="1141" y="129" height="60" variable="crop2" current="0" width="178" display="crop2">
      <choice type="string" value="pšenice ozimá"></choice>
      <choice type="string" value="žito ozimé"></choice>
      <choice type="string" value="ječmen jarní"></choice>
      <choice type="string" value="ječmen ozimý"></choice>
      <choice type="string" value="oves"></choice>
      <choice type="string" value="kukuřice na zrno"></choice>
      <choice type="string" value="luštěniny"></choice>
      <choice type="string" value="brambory rané"></choice>
      <choice type="string" value="brambory pozdní"></choice>
      <choice type="string" value="louky"></choice>
      <choice type="string" value="chmelnice"></choice>
      <choice type="string" value="řepka ozimá"></choice>
      <choice type="string" value="slunečnice"></choice>
      <choice type="string" value="mák"></choice>
      <choice type="string" value="ostatní olejniny"></choice>
      <choice type="string" value="kukuřice na siláž"></choice>
      <choice type="string" value="ostatní pícniny jednoleté"></choice>
      <choice type="string" value="ostatní pícniny víceleté"></choice>
      <choice type="string" value="zelenina"></choice>
      <choice type="string" value="sady"></choice>
    </chooser>
    <button x="1171" y="203" height="40" disableUntilTicks="false" forever="false" kind="Observer" width="102" display="&lt;&gt;">swap-crop</button>
    <button x="1183" y="442" height="40" disableUntilTicks="false" forever="false" kind="Observer" width="123">test-crop false</button>
    <note x="1170" y="10" backgroundDark="0" fontSize="20" width="150" markdown="false" height="25" textColorDark="-1" textColorLight="-16777216" backgroundLight="0">Plodiny</note>
    <note x="1176" y="283" backgroundDark="0" fontSize="20" width="150" markdown="false" height="25" textColorDark="-1" textColorLight="-16777216" backgroundLight="0">Půda</note>
    <chooser x="1143" y="329" height="60" variable="soil" current="1" width="174" display="soil">
      <choice type="string" value="černozem"></choice>
      <choice type="string" value="kambizem"></choice>
    </chooser>
    <button x="1172" y="697" height="40" disableUntilTicks="false" forever="false" kind="Observer" width="104" display="Export Facc">export-to-asc</button>
    <switch x="1175" y="560" height="40" on="false" variable="test?" width="103" display="test?"></switch>
    <chooser x="19" y="489" height="60" variable="stripe-length" current="1" width="171" display="stripe-length">
      <choice type="double" value="10.0"></choice>
      <choice type="double" value="20.0"></choice>
      <choice type="double" value="25.0"></choice>
      <choice type="double" value="30.0"></choice>
      <choice type="double" value="36.0"></choice>
      <choice type="double" value="40.0"></choice>
      <choice type="double" value="50.0"></choice>
      <choice type="double" value="72.0"></choice>
      <choice type="double" value="75.0"></choice>
      <choice type="double" value="80.0"></choice>
      <choice type="double" value="100.0"></choice>
      <choice type="double" value="108.0"></choice>
      <choice type="double" value="125.0"></choice>
      <choice type="double" value="144.0"></choice>
      <choice type="double" value="150.0"></choice>
      <choice type="double" value="175.0"></choice>
      <choice type="double" value="180.0"></choice>
      <choice type="double" value="200.0"></choice>
      <choice type="double" value="216.0"></choice>
      <choice type="double" value="250.0"></choice>
    </chooser>
    <switch x="1171" y="641" height="40" on="false" variable="debug?" width="103" display="debug?"></switch>
    <input x="17" multiline="false" y="867" height="60" variable="srazky-mm" type="number" width="176">40.0</input>
    <monitor x="18" precision="17" y="964" height="60" fontSize="11" width="173" display="pd">highest-c-factor-representation</monitor>
  </widgets>
  <info>## WHAT IS IT?

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

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)</info>
  <turtleShapes>
    <shape name="default" rotatable="true" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="5"></point>
        <point x="40" y="250"></point>
        <point x="150" y="205"></point>
        <point x="260" y="250"></point>
      </polygon>
    </shape>
    <shape name="airplane" rotatable="true" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="0"></point>
        <point x="135" y="15"></point>
        <point x="120" y="60"></point>
        <point x="120" y="105"></point>
        <point x="15" y="165"></point>
        <point x="15" y="195"></point>
        <point x="120" y="180"></point>
        <point x="135" y="240"></point>
        <point x="105" y="270"></point>
        <point x="120" y="285"></point>
        <point x="150" y="270"></point>
        <point x="180" y="285"></point>
        <point x="210" y="270"></point>
        <point x="165" y="240"></point>
        <point x="180" y="180"></point>
        <point x="285" y="195"></point>
        <point x="285" y="165"></point>
        <point x="180" y="105"></point>
        <point x="180" y="60"></point>
        <point x="165" y="15"></point>
      </polygon>
    </shape>
    <shape name="arrow" rotatable="true" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="0"></point>
        <point x="0" y="150"></point>
        <point x="105" y="150"></point>
        <point x="105" y="293"></point>
        <point x="195" y="293"></point>
        <point x="195" y="150"></point>
        <point x="300" y="150"></point>
      </polygon>
    </shape>
    <shape name="box" rotatable="false" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="285"></point>
        <point x="285" y="225"></point>
        <point x="285" y="75"></point>
        <point x="150" y="135"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="135"></point>
        <point x="15" y="75"></point>
        <point x="150" y="15"></point>
        <point x="285" y="75"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="15" y="75"></point>
        <point x="15" y="225"></point>
        <point x="150" y="285"></point>
        <point x="150" y="135"></point>
      </polygon>
      <line endX="150" startY="285" marked="false" color="255" endY="135" startX="150"></line>
      <line endX="15" startY="135" marked="false" color="255" endY="75" startX="150"></line>
      <line endX="285" startY="135" marked="false" color="255" endY="75" startX="150"></line>
    </shape>
    <shape name="bug" rotatable="true" editableColorIndex="0">
      <circle x="96" y="182" marked="true" color="-1920102913" diameter="108" filled="true"></circle>
      <circle x="110" y="127" marked="true" color="-1920102913" diameter="80" filled="true"></circle>
      <circle x="110" y="75" marked="true" color="-1920102913" diameter="80" filled="true"></circle>
      <line endX="80" startY="100" marked="true" color="-1920102913" endY="30" startX="150"></line>
      <line endX="220" startY="100" marked="true" color="-1920102913" endY="30" startX="150"></line>
    </shape>
    <shape name="butterfly" rotatable="true" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="165"></point>
        <point x="209" y="199"></point>
        <point x="225" y="225"></point>
        <point x="225" y="255"></point>
        <point x="195" y="270"></point>
        <point x="165" y="255"></point>
        <point x="150" y="240"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="165"></point>
        <point x="89" y="198"></point>
        <point x="75" y="225"></point>
        <point x="75" y="255"></point>
        <point x="105" y="270"></point>
        <point x="135" y="255"></point>
        <point x="150" y="240"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="139" y="148"></point>
        <point x="100" y="105"></point>
        <point x="55" y="90"></point>
        <point x="25" y="90"></point>
        <point x="10" y="105"></point>
        <point x="10" y="135"></point>
        <point x="25" y="180"></point>
        <point x="40" y="195"></point>
        <point x="85" y="194"></point>
        <point x="139" y="163"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="162" y="150"></point>
        <point x="200" y="105"></point>
        <point x="245" y="90"></point>
        <point x="275" y="90"></point>
        <point x="290" y="105"></point>
        <point x="290" y="135"></point>
        <point x="275" y="180"></point>
        <point x="260" y="195"></point>
        <point x="215" y="195"></point>
        <point x="162" y="165"></point>
      </polygon>
      <polygon color="255" filled="true" marked="false">
        <point x="150" y="255"></point>
        <point x="135" y="225"></point>
        <point x="120" y="150"></point>
        <point x="135" y="120"></point>
        <point x="150" y="105"></point>
        <point x="165" y="120"></point>
        <point x="180" y="150"></point>
        <point x="165" y="225"></point>
      </polygon>
      <circle x="135" y="90" marked="false" color="255" diameter="30" filled="true"></circle>
      <line endX="195" startY="105" marked="false" color="255" endY="60" startX="150"></line>
      <line endX="105" startY="105" marked="false" color="255" endY="60" startX="150"></line>
    </shape>
    <shape name="car" rotatable="false" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="300" y="180"></point>
        <point x="279" y="164"></point>
        <point x="261" y="144"></point>
        <point x="240" y="135"></point>
        <point x="226" y="132"></point>
        <point x="213" y="106"></point>
        <point x="203" y="84"></point>
        <point x="185" y="63"></point>
        <point x="159" y="50"></point>
        <point x="135" y="50"></point>
        <point x="75" y="60"></point>
        <point x="0" y="150"></point>
        <point x="0" y="165"></point>
        <point x="0" y="225"></point>
        <point x="300" y="225"></point>
        <point x="300" y="180"></point>
      </polygon>
      <circle x="180" y="180" marked="false" color="255" diameter="90" filled="true"></circle>
      <circle x="30" y="180" marked="false" color="255" diameter="90" filled="true"></circle>
      <polygon color="255" filled="true" marked="false">
        <point x="162" y="80"></point>
        <point x="132" y="78"></point>
        <point x="134" y="135"></point>
        <point x="209" y="135"></point>
        <point x="194" y="105"></point>
        <point x="189" y="96"></point>
        <point x="180" y="89"></point>
      </polygon>
      <circle x="47" y="195" marked="true" color="-1920102913" diameter="58" filled="true"></circle>
      <circle x="195" y="195" marked="true" color="-1920102913" diameter="58" filled="true"></circle>
    </shape>
    <shape name="circle" rotatable="false" editableColorIndex="0">
      <circle x="0" y="0" marked="true" color="-1920102913" diameter="300" filled="true"></circle>
    </shape>
    <shape name="circle 2" rotatable="false" editableColorIndex="0">
      <circle x="0" y="0" marked="true" color="-1920102913" diameter="300" filled="true"></circle>
      <circle x="30" y="30" marked="false" color="255" diameter="240" filled="true"></circle>
    </shape>
    <shape name="cow" rotatable="false" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="200" y="193"></point>
        <point x="197" y="249"></point>
        <point x="179" y="249"></point>
        <point x="177" y="196"></point>
        <point x="166" y="187"></point>
        <point x="140" y="189"></point>
        <point x="93" y="191"></point>
        <point x="78" y="179"></point>
        <point x="72" y="211"></point>
        <point x="49" y="209"></point>
        <point x="48" y="181"></point>
        <point x="37" y="149"></point>
        <point x="25" y="120"></point>
        <point x="25" y="89"></point>
        <point x="45" y="72"></point>
        <point x="103" y="84"></point>
        <point x="179" y="75"></point>
        <point x="198" y="76"></point>
        <point x="252" y="64"></point>
        <point x="272" y="81"></point>
        <point x="293" y="103"></point>
        <point x="285" y="121"></point>
        <point x="255" y="121"></point>
        <point x="242" y="118"></point>
        <point x="224" y="167"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="73" y="210"></point>
        <point x="86" y="251"></point>
        <point x="62" y="249"></point>
        <point x="48" y="208"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="25" y="114"></point>
        <point x="16" y="195"></point>
        <point x="9" y="204"></point>
        <point x="23" y="213"></point>
        <point x="25" y="200"></point>
        <point x="39" y="123"></point>
      </polygon>
    </shape>
    <shape name="cylinder" rotatable="false" editableColorIndex="0">
      <circle x="0" y="0" marked="true" color="-1920102913" diameter="300" filled="true"></circle>
    </shape>
    <shape name="dot" rotatable="false" editableColorIndex="0">
      <circle x="90" y="90" marked="true" color="-1920102913" diameter="120" filled="true"></circle>
    </shape>
    <shape name="face happy" rotatable="false" editableColorIndex="0">
      <circle x="8" y="8" marked="true" color="-1920102913" diameter="285" filled="true"></circle>
      <circle x="60" y="75" marked="false" color="255" diameter="60" filled="true"></circle>
      <circle x="180" y="75" marked="false" color="255" diameter="60" filled="true"></circle>
      <polygon color="255" filled="true" marked="false">
        <point x="150" y="255"></point>
        <point x="90" y="239"></point>
        <point x="62" y="213"></point>
        <point x="47" y="191"></point>
        <point x="67" y="179"></point>
        <point x="90" y="203"></point>
        <point x="109" y="218"></point>
        <point x="150" y="225"></point>
        <point x="192" y="218"></point>
        <point x="210" y="203"></point>
        <point x="227" y="181"></point>
        <point x="251" y="194"></point>
        <point x="236" y="217"></point>
        <point x="212" y="240"></point>
      </polygon>
    </shape>
    <shape name="face neutral" rotatable="false" editableColorIndex="0">
      <circle x="8" y="7" marked="true" color="-1920102913" diameter="285" filled="true"></circle>
      <circle x="60" y="75" marked="false" color="255" diameter="60" filled="true"></circle>
      <circle x="180" y="75" marked="false" color="255" diameter="60" filled="true"></circle>
      <rectangle endX="240" startY="195" marked="false" color="255" endY="225" startX="60" filled="true"></rectangle>
    </shape>
    <shape name="face sad" rotatable="false" editableColorIndex="0">
      <circle x="8" y="8" marked="true" color="-1920102913" diameter="285" filled="true"></circle>
      <circle x="60" y="75" marked="false" color="255" diameter="60" filled="true"></circle>
      <circle x="180" y="75" marked="false" color="255" diameter="60" filled="true"></circle>
      <polygon color="255" filled="true" marked="false">
        <point x="150" y="168"></point>
        <point x="90" y="184"></point>
        <point x="62" y="210"></point>
        <point x="47" y="232"></point>
        <point x="67" y="244"></point>
        <point x="90" y="220"></point>
        <point x="109" y="205"></point>
        <point x="150" y="198"></point>
        <point x="192" y="205"></point>
        <point x="210" y="220"></point>
        <point x="227" y="242"></point>
        <point x="251" y="229"></point>
        <point x="236" y="206"></point>
        <point x="212" y="183"></point>
      </polygon>
    </shape>
    <shape name="fish" rotatable="false" editableColorIndex="0">
      <polygon color="-1" filled="true" marked="false">
        <point x="44" y="131"></point>
        <point x="21" y="87"></point>
        <point x="15" y="86"></point>
        <point x="0" y="120"></point>
        <point x="15" y="150"></point>
        <point x="0" y="180"></point>
        <point x="13" y="214"></point>
        <point x="20" y="212"></point>
        <point x="45" y="166"></point>
      </polygon>
      <polygon color="-1" filled="true" marked="false">
        <point x="135" y="195"></point>
        <point x="119" y="235"></point>
        <point x="95" y="218"></point>
        <point x="76" y="210"></point>
        <point x="46" y="204"></point>
        <point x="60" y="165"></point>
      </polygon>
      <polygon color="-1" filled="true" marked="false">
        <point x="75" y="45"></point>
        <point x="83" y="77"></point>
        <point x="71" y="103"></point>
        <point x="86" y="114"></point>
        <point x="166" y="78"></point>
        <point x="135" y="60"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="30" y="136"></point>
        <point x="151" y="77"></point>
        <point x="226" y="81"></point>
        <point x="280" y="119"></point>
        <point x="292" y="146"></point>
        <point x="292" y="160"></point>
        <point x="287" y="170"></point>
        <point x="270" y="195"></point>
        <point x="195" y="210"></point>
        <point x="151" y="212"></point>
        <point x="30" y="166"></point>
      </polygon>
      <circle x="215" y="106" marked="false" color="255" diameter="30" filled="true"></circle>
    </shape>
    <shape name="flag" rotatable="false" editableColorIndex="0">
      <rectangle endX="75" startY="15" marked="true" color="-1920102913" endY="300" startX="60" filled="true"></rectangle>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="90" y="150"></point>
        <point x="270" y="90"></point>
        <point x="90" y="30"></point>
      </polygon>
      <line endX="90" startY="135" marked="true" color="-1920102913" endY="135" startX="75"></line>
      <line endX="90" startY="45" marked="true" color="-1920102913" endY="45" startX="75"></line>
    </shape>
    <shape name="flower" rotatable="false" editableColorIndex="0">
      <polygon color="1504722175" filled="true" marked="false">
        <point x="135" y="120"></point>
        <point x="165" y="165"></point>
        <point x="180" y="210"></point>
        <point x="180" y="240"></point>
        <point x="150" y="300"></point>
        <point x="165" y="300"></point>
        <point x="195" y="240"></point>
        <point x="195" y="195"></point>
        <point x="165" y="135"></point>
      </polygon>
      <circle x="85" y="132" marked="true" color="-1920102913" diameter="38" filled="true"></circle>
      <circle x="130" y="147" marked="true" color="-1920102913" diameter="38" filled="true"></circle>
      <circle x="192" y="85" marked="true" color="-1920102913" diameter="38" filled="true"></circle>
      <circle x="85" y="40" marked="true" color="-1920102913" diameter="38" filled="true"></circle>
      <circle x="177" y="40" marked="true" color="-1920102913" diameter="38" filled="true"></circle>
      <circle x="177" y="132" marked="true" color="-1920102913" diameter="38" filled="true"></circle>
      <circle x="70" y="85" marked="true" color="-1920102913" diameter="38" filled="true"></circle>
      <circle x="130" y="25" marked="true" color="-1920102913" diameter="38" filled="true"></circle>
      <circle x="96" y="51" marked="true" color="-1920102913" diameter="108" filled="true"></circle>
      <circle x="113" y="68" marked="false" color="255" diameter="74" filled="true"></circle>
      <polygon color="1504722175" filled="true" marked="false">
        <point x="189" y="233"></point>
        <point x="219" y="188"></point>
        <point x="249" y="173"></point>
        <point x="279" y="188"></point>
        <point x="234" y="218"></point>
      </polygon>
      <polygon color="1504722175" filled="true" marked="false">
        <point x="180" y="255"></point>
        <point x="150" y="210"></point>
        <point x="105" y="210"></point>
        <point x="75" y="240"></point>
        <point x="135" y="240"></point>
      </polygon>
    </shape>
    <shape name="house" rotatable="false" editableColorIndex="0">
      <rectangle endX="255" startY="120" marked="true" color="-1920102913" endY="285" startX="45" filled="true"></rectangle>
      <rectangle endX="180" startY="210" marked="false" color="255" endY="285" startX="120" filled="true"></rectangle>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="15" y="120"></point>
        <point x="150" y="15"></point>
        <point x="285" y="120"></point>
      </polygon>
      <line endX="270" startY="120" marked="false" color="255" endY="120" startX="30"></line>
    </shape>
    <shape name="leaf" rotatable="false" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="210"></point>
        <point x="135" y="195"></point>
        <point x="120" y="210"></point>
        <point x="60" y="210"></point>
        <point x="30" y="195"></point>
        <point x="60" y="180"></point>
        <point x="60" y="165"></point>
        <point x="15" y="135"></point>
        <point x="30" y="120"></point>
        <point x="15" y="105"></point>
        <point x="40" y="104"></point>
        <point x="45" y="90"></point>
        <point x="60" y="90"></point>
        <point x="90" y="105"></point>
        <point x="105" y="120"></point>
        <point x="120" y="120"></point>
        <point x="105" y="60"></point>
        <point x="120" y="60"></point>
        <point x="135" y="30"></point>
        <point x="150" y="15"></point>
        <point x="165" y="30"></point>
        <point x="180" y="60"></point>
        <point x="195" y="60"></point>
        <point x="180" y="120"></point>
        <point x="195" y="120"></point>
        <point x="210" y="105"></point>
        <point x="240" y="90"></point>
        <point x="255" y="90"></point>
        <point x="263" y="104"></point>
        <point x="285" y="105"></point>
        <point x="270" y="120"></point>
        <point x="285" y="135"></point>
        <point x="240" y="165"></point>
        <point x="240" y="180"></point>
        <point x="270" y="195"></point>
        <point x="240" y="210"></point>
        <point x="180" y="210"></point>
        <point x="165" y="195"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="135" y="195"></point>
        <point x="135" y="240"></point>
        <point x="120" y="255"></point>
        <point x="105" y="255"></point>
        <point x="105" y="285"></point>
        <point x="135" y="285"></point>
        <point x="165" y="240"></point>
        <point x="165" y="195"></point>
      </polygon>
    </shape>
    <shape name="line" rotatable="true" editableColorIndex="0">
      <line endX="150" startY="0" marked="true" color="-1920102913" endY="300" startX="150"></line>
    </shape>
    <shape name="line half" rotatable="true" editableColorIndex="0">
      <line endX="150" startY="0" marked="true" color="-1920102913" endY="150" startX="150"></line>
    </shape>
    <shape name="pentagon" rotatable="false" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="15"></point>
        <point x="15" y="120"></point>
        <point x="60" y="285"></point>
        <point x="240" y="285"></point>
        <point x="285" y="120"></point>
      </polygon>
    </shape>
    <shape name="person" rotatable="false" editableColorIndex="0">
      <circle x="110" y="5" marked="true" color="-1920102913" diameter="80" filled="true"></circle>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="105" y="90"></point>
        <point x="120" y="195"></point>
        <point x="90" y="285"></point>
        <point x="105" y="300"></point>
        <point x="135" y="300"></point>
        <point x="150" y="225"></point>
        <point x="165" y="300"></point>
        <point x="195" y="300"></point>
        <point x="210" y="285"></point>
        <point x="180" y="195"></point>
        <point x="195" y="90"></point>
      </polygon>
      <rectangle endX="172" startY="79" marked="true" color="-1920102913" endY="94" startX="127" filled="true"></rectangle>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="195" y="90"></point>
        <point x="240" y="150"></point>
        <point x="225" y="180"></point>
        <point x="165" y="105"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="105" y="90"></point>
        <point x="60" y="150"></point>
        <point x="75" y="180"></point>
        <point x="135" y="105"></point>
      </polygon>
    </shape>
    <shape name="plant" rotatable="false" editableColorIndex="0">
      <rectangle endX="165" startY="90" marked="true" color="-1920102913" endY="300" startX="135" filled="true"></rectangle>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="135" y="255"></point>
        <point x="90" y="210"></point>
        <point x="45" y="195"></point>
        <point x="75" y="255"></point>
        <point x="135" y="285"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="165" y="255"></point>
        <point x="210" y="210"></point>
        <point x="255" y="195"></point>
        <point x="225" y="255"></point>
        <point x="165" y="285"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="135" y="180"></point>
        <point x="90" y="135"></point>
        <point x="45" y="120"></point>
        <point x="75" y="180"></point>
        <point x="135" y="210"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="165" y="180"></point>
        <point x="165" y="210"></point>
        <point x="225" y="180"></point>
        <point x="255" y="120"></point>
        <point x="210" y="135"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="135" y="105"></point>
        <point x="90" y="60"></point>
        <point x="45" y="45"></point>
        <point x="75" y="105"></point>
        <point x="135" y="135"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="165" y="105"></point>
        <point x="165" y="135"></point>
        <point x="225" y="105"></point>
        <point x="255" y="45"></point>
        <point x="210" y="60"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="135" y="90"></point>
        <point x="120" y="45"></point>
        <point x="150" y="15"></point>
        <point x="180" y="45"></point>
        <point x="165" y="90"></point>
      </polygon>
    </shape>
    <shape name="sheep" rotatable="false" editableColorIndex="15">
      <circle x="203" y="65" marked="true" color="-1" diameter="88" filled="true"></circle>
      <circle x="70" y="65" marked="true" color="-1" diameter="162" filled="true"></circle>
      <circle x="150" y="105" marked="true" color="-1" diameter="120" filled="true"></circle>
      <polygon color="-1920102913" filled="true" marked="false">
        <point x="218" y="120"></point>
        <point x="240" y="165"></point>
        <point x="255" y="165"></point>
        <point x="278" y="120"></point>
      </polygon>
      <circle x="214" y="72" marked="false" color="-1920102913" diameter="67" filled="true"></circle>
      <rectangle endX="179" startY="223" marked="true" color="-1" endY="298" startX="164" filled="true"></rectangle>
      <polygon color="-1" filled="true" marked="true">
        <point x="45" y="285"></point>
        <point x="30" y="285"></point>
        <point x="30" y="240"></point>
        <point x="15" y="195"></point>
        <point x="45" y="210"></point>
      </polygon>
      <circle x="3" y="83" marked="true" color="-1" diameter="150" filled="true"></circle>
      <rectangle endX="80" startY="221" marked="true" color="-1" endY="296" startX="65" filled="true"></rectangle>
      <polygon color="-1" filled="true" marked="true">
        <point x="195" y="285"></point>
        <point x="210" y="285"></point>
        <point x="210" y="240"></point>
        <point x="240" y="210"></point>
        <point x="195" y="210"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="false">
        <point x="276" y="85"></point>
        <point x="285" y="105"></point>
        <point x="302" y="99"></point>
        <point x="294" y="83"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="false">
        <point x="219" y="85"></point>
        <point x="210" y="105"></point>
        <point x="193" y="99"></point>
        <point x="201" y="83"></point>
      </polygon>
    </shape>
    <shape name="square" rotatable="false" editableColorIndex="0">
      <rectangle endX="270" startY="30" marked="true" color="-1920102913" endY="270" startX="30" filled="true"></rectangle>
    </shape>
    <shape name="square 2" rotatable="false" editableColorIndex="0">
      <rectangle endX="270" startY="30" marked="true" color="-1920102913" endY="270" startX="30" filled="true"></rectangle>
      <rectangle endX="240" startY="60" marked="false" color="255" endY="240" startX="60" filled="true"></rectangle>
    </shape>
    <shape name="star" rotatable="false" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="151" y="1"></point>
        <point x="185" y="108"></point>
        <point x="298" y="108"></point>
        <point x="207" y="175"></point>
        <point x="242" y="282"></point>
        <point x="151" y="216"></point>
        <point x="59" y="282"></point>
        <point x="94" y="175"></point>
        <point x="3" y="108"></point>
        <point x="116" y="108"></point>
      </polygon>
    </shape>
    <shape name="target" rotatable="false" editableColorIndex="0">
      <circle x="0" y="0" marked="true" color="-1920102913" diameter="300" filled="true"></circle>
      <circle x="30" y="30" marked="false" color="255" diameter="240" filled="true"></circle>
      <circle x="60" y="60" marked="true" color="-1920102913" diameter="180" filled="true"></circle>
      <circle x="90" y="90" marked="false" color="255" diameter="120" filled="true"></circle>
      <circle x="120" y="120" marked="true" color="-1920102913" diameter="60" filled="true"></circle>
    </shape>
    <shape name="tree" rotatable="false" editableColorIndex="0">
      <circle x="118" y="3" marked="true" color="-1920102913" diameter="94" filled="true"></circle>
      <rectangle endX="180" startY="195" marked="false" color="-1653716737" endY="300" startX="120" filled="true"></rectangle>
      <circle x="65" y="21" marked="true" color="-1920102913" diameter="108" filled="true"></circle>
      <circle x="116" y="41" marked="true" color="-1920102913" diameter="127" filled="true"></circle>
      <circle x="45" y="90" marked="true" color="-1920102913" diameter="120" filled="true"></circle>
      <circle x="104" y="74" marked="true" color="-1920102913" diameter="152" filled="true"></circle>
    </shape>
    <shape name="triangle" rotatable="false" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="30"></point>
        <point x="15" y="255"></point>
        <point x="285" y="255"></point>
      </polygon>
    </shape>
    <shape name="triangle 2" rotatable="false" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="150" y="30"></point>
        <point x="15" y="255"></point>
        <point x="285" y="255"></point>
      </polygon>
      <polygon color="255" filled="true" marked="false">
        <point x="151" y="99"></point>
        <point x="225" y="223"></point>
        <point x="75" y="224"></point>
      </polygon>
    </shape>
    <shape name="truck" rotatable="false" editableColorIndex="0">
      <rectangle endX="195" startY="45" marked="true" color="-1920102913" endY="187" startX="4" filled="true"></rectangle>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="296" y="193"></point>
        <point x="296" y="150"></point>
        <point x="259" y="134"></point>
        <point x="244" y="104"></point>
        <point x="208" y="104"></point>
        <point x="207" y="194"></point>
      </polygon>
      <rectangle endX="195" startY="60" marked="false" color="-1" endY="105" startX="195" filled="true"></rectangle>
      <polygon color="255" filled="true" marked="false">
        <point x="238" y="112"></point>
        <point x="252" y="141"></point>
        <point x="219" y="141"></point>
        <point x="218" y="112"></point>
      </polygon>
      <circle x="234" y="174" marked="false" color="255" diameter="42" filled="true"></circle>
      <rectangle endX="214" startY="185" marked="true" color="-1920102913" endY="194" startX="181" filled="true"></rectangle>
      <circle x="144" y="174" marked="false" color="255" diameter="42" filled="true"></circle>
      <circle x="24" y="174" marked="false" color="255" diameter="42" filled="true"></circle>
      <circle x="24" y="174" marked="true" color="-1920102913" diameter="42" filled="false"></circle>
      <circle x="144" y="174" marked="true" color="-1920102913" diameter="42" filled="false"></circle>
      <circle x="234" y="174" marked="true" color="-1920102913" diameter="42" filled="false"></circle>
    </shape>
    <shape name="turtle" rotatable="true" editableColorIndex="0">
      <polygon color="1504722175" filled="true" marked="false">
        <point x="215" y="204"></point>
        <point x="240" y="233"></point>
        <point x="246" y="254"></point>
        <point x="228" y="266"></point>
        <point x="215" y="252"></point>
        <point x="193" y="210"></point>
      </polygon>
      <polygon color="1504722175" filled="true" marked="false">
        <point x="195" y="90"></point>
        <point x="225" y="75"></point>
        <point x="245" y="75"></point>
        <point x="260" y="89"></point>
        <point x="269" y="108"></point>
        <point x="261" y="124"></point>
        <point x="240" y="105"></point>
        <point x="225" y="105"></point>
        <point x="210" y="105"></point>
      </polygon>
      <polygon color="1504722175" filled="true" marked="false">
        <point x="105" y="90"></point>
        <point x="75" y="75"></point>
        <point x="55" y="75"></point>
        <point x="40" y="89"></point>
        <point x="31" y="108"></point>
        <point x="39" y="124"></point>
        <point x="60" y="105"></point>
        <point x="75" y="105"></point>
        <point x="90" y="105"></point>
      </polygon>
      <polygon color="1504722175" filled="true" marked="false">
        <point x="132" y="85"></point>
        <point x="134" y="64"></point>
        <point x="107" y="51"></point>
        <point x="108" y="17"></point>
        <point x="150" y="2"></point>
        <point x="192" y="18"></point>
        <point x="192" y="52"></point>
        <point x="169" y="65"></point>
        <point x="172" y="87"></point>
      </polygon>
      <polygon color="1504722175" filled="true" marked="false">
        <point x="85" y="204"></point>
        <point x="60" y="233"></point>
        <point x="54" y="254"></point>
        <point x="72" y="266"></point>
        <point x="85" y="252"></point>
        <point x="107" y="210"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="119" y="75"></point>
        <point x="179" y="75"></point>
        <point x="209" y="101"></point>
        <point x="224" y="135"></point>
        <point x="220" y="225"></point>
        <point x="175" y="261"></point>
        <point x="128" y="261"></point>
        <point x="81" y="224"></point>
        <point x="74" y="135"></point>
        <point x="88" y="99"></point>
      </polygon>
    </shape>
    <shape name="wheel" rotatable="false" editableColorIndex="0">
      <circle x="3" y="3" marked="true" color="-1920102913" diameter="294" filled="true"></circle>
      <circle x="30" y="30" marked="false" color="255" diameter="240" filled="true"></circle>
      <line endX="150" startY="285" marked="true" color="-1920102913" endY="15" startX="150"></line>
      <line endX="285" startY="150" marked="true" color="-1920102913" endY="150" startX="15"></line>
      <circle x="120" y="120" marked="true" color="-1920102913" diameter="60" filled="true"></circle>
      <line endX="79" startY="40" marked="true" color="-1920102913" endY="269" startX="216"></line>
      <line endX="269" startY="84" marked="true" color="-1920102913" endY="221" startX="40"></line>
      <line endX="269" startY="216" marked="true" color="-1920102913" endY="79" startX="40"></line>
      <line endX="221" startY="40" marked="true" color="-1920102913" endY="269" startX="84"></line>
    </shape>
    <shape name="wolf" rotatable="false" editableColorIndex="0">
      <polygon color="255" filled="true" marked="false">
        <point x="253" y="133"></point>
        <point x="245" y="131"></point>
        <point x="245" y="133"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="2" y="194"></point>
        <point x="13" y="197"></point>
        <point x="30" y="191"></point>
        <point x="38" y="193"></point>
        <point x="38" y="205"></point>
        <point x="20" y="226"></point>
        <point x="20" y="257"></point>
        <point x="27" y="265"></point>
        <point x="38" y="266"></point>
        <point x="40" y="260"></point>
        <point x="31" y="253"></point>
        <point x="31" y="230"></point>
        <point x="60" y="206"></point>
        <point x="68" y="198"></point>
        <point x="75" y="209"></point>
        <point x="66" y="228"></point>
        <point x="65" y="243"></point>
        <point x="82" y="261"></point>
        <point x="84" y="268"></point>
        <point x="100" y="267"></point>
        <point x="103" y="261"></point>
        <point x="77" y="239"></point>
        <point x="79" y="231"></point>
        <point x="100" y="207"></point>
        <point x="98" y="196"></point>
        <point x="119" y="201"></point>
        <point x="143" y="202"></point>
        <point x="160" y="195"></point>
        <point x="166" y="210"></point>
        <point x="172" y="213"></point>
        <point x="173" y="238"></point>
        <point x="167" y="251"></point>
        <point x="160" y="248"></point>
        <point x="154" y="265"></point>
        <point x="169" y="264"></point>
        <point x="178" y="247"></point>
        <point x="186" y="240"></point>
        <point x="198" y="260"></point>
        <point x="200" y="271"></point>
        <point x="217" y="271"></point>
        <point x="219" y="262"></point>
        <point x="207" y="258"></point>
        <point x="195" y="230"></point>
        <point x="192" y="198"></point>
        <point x="210" y="184"></point>
        <point x="227" y="164"></point>
        <point x="242" y="144"></point>
        <point x="259" y="145"></point>
        <point x="284" y="151"></point>
        <point x="277" y="141"></point>
        <point x="293" y="140"></point>
        <point x="299" y="134"></point>
        <point x="297" y="127"></point>
        <point x="273" y="119"></point>
        <point x="270" y="105"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="-1" y="195"></point>
        <point x="14" y="180"></point>
        <point x="36" y="166"></point>
        <point x="40" y="153"></point>
        <point x="53" y="140"></point>
        <point x="82" y="131"></point>
        <point x="134" y="133"></point>
        <point x="159" y="126"></point>
        <point x="188" y="115"></point>
        <point x="227" y="108"></point>
        <point x="236" y="102"></point>
        <point x="238" y="98"></point>
        <point x="268" y="86"></point>
        <point x="269" y="92"></point>
        <point x="281" y="87"></point>
        <point x="269" y="103"></point>
        <point x="269" y="113"></point>
      </polygon>
    </shape>
    <shape name="x" rotatable="false" editableColorIndex="0">
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="270" y="75"></point>
        <point x="225" y="30"></point>
        <point x="30" y="225"></point>
        <point x="75" y="270"></point>
      </polygon>
      <polygon color="-1920102913" filled="true" marked="true">
        <point x="30" y="75"></point>
        <point x="75" y="30"></point>
        <point x="270" y="225"></point>
        <point x="225" y="270"></point>
      </polygon>
    </shape>
  </turtleShapes>
  <linkShapes>
    <shape name="default" curviness="0.0">
      <lines>
        <line x="-0.2" visible="false">
          <dash value="0.0"></dash>
          <dash value="1.0"></dash>
        </line>
        <line x="0.0" visible="true">
          <dash value="1.0"></dash>
          <dash value="0.0"></dash>
        </line>
        <line x="0.2" visible="false">
          <dash value="0.0"></dash>
          <dash value="1.0"></dash>
        </line>
      </lines>
      <indicator>
        <shape name="link direction" rotatable="true" editableColorIndex="0">
          <line endX="90" startY="150" marked="true" color="-1920102913" endY="180" startX="150"></line>
          <line endX="210" startY="150" marked="true" color="-1920102913" endY="180" startX="150"></line>
        </shape>
      </indicator>
    </shape>
  </linkShapes>
  <previewCommands>setup repeat 75 [ go ]</previewCommands>
  <experiments>
    <experiment name="experiment" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <go>setup
get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;convergent&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;single&quot;"></value>
          <value value="&quot;two&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="exp_two_angles_standard" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <go>setup
get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;two&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="10"></value>
          <value value="20"></value>
          <value value="30"></value>
          <value value="40"></value>
          <value value="50"></value>
          <value value="60"></value>
          <value value="70"></value>
          <value value="80"></value>
          <value value="90"></value>
          <value value="0"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="exp_two_angles_all" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <go>setup
get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;two&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="10"></value>
          <value value="20"></value>
          <value value="30"></value>
          <value value="40"></value>
          <value value="50"></value>
          <value value="60"></value>
          <value value="70"></value>
          <value value="80"></value>
          <value value="90"></value>
          <value value="0"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="experiment2" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="par-minfrac">
          <value value="0.05"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;two&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <steppedValueSet variable="division_angle" first="0" step="10" last="90"></steppedValueSet>
      </constants>
    </experiment>
    <experiment name="experiment2 (copy)" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;two&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <steppedValueSet variable="division_angle" first="0" step="10" last="90"></steppedValueSet>
      </constants>
    </experiment>
    <experiment name="ex_pasy" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;convergent&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <steppedValueSet variable="division_angle" first="0" step="10" last="90"></steppedValueSet>
      </constants>
    </experiment>
    <experiment name="pasy_srazky" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;convergent&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <steppedValueSet variable="division_angle" first="0" step="10" last="90"></steppedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
          <value value="36"></value>
          <value value="50"></value>
          <value value="72"></value>
          <value value="100"></value>
          <value value="108"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="10"></value>
          <value value="20"></value>
          <value value="30"></value>
          <value value="40"></value>
          <value value="50"></value>
        </enumeratedValueSet>
      </constants>
      <subExperiments>
        <subExperiment>
          <enumeratedValueSet variable="crop1">
            <value value="&quot;pšenice ozimá&quot;"></value>
          </enumeratedValueSet>
          <enumeratedValueSet variable="crop2">
            <value value="&quot;kukuřice na siláž&quot;"></value>
          </enumeratedValueSet>
        </subExperiment>
        <subExperiment>
          <enumeratedValueSet variable="crop2">
            <value value="&quot;pšenice ozimá&quot;"></value>
          </enumeratedValueSet>
          <enumeratedValueSet variable="crop1">
            <value value="&quot;kukuřice na siláž&quot;"></value>
          </enumeratedValueSet>
        </subExperiment>
      </subExperiments>
    </experiment>
    <experiment name="ex_pasy_po_10" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;convergent&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;convex&quot;"></value>
        </enumeratedValueSet>
        <steppedValueSet variable="division_angle" first="0" step="10" last="90"></steppedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="30"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="ex_pasy_obracene" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;convergent&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <steppedValueSet variable="division_angle" first="0" step="10" last="90"></steppedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="36"></value>
          <value value="50"></value>
          <value value="72"></value>
          <value value="100"></value>
          <value value="108"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="ex_pasy_obracene_25" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;parallel&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;convergent&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <steppedValueSet variable="division_angle" first="0" step="10" last="90"></steppedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="pasy_srazky_test" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="eKP2" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="36"></value>
          <value value="72"></value>
          <value value="108"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;ka1&quot;"></value>
          <value value="&quot;ka2&quot;"></value>
          <value value="&quot;ka3&quot;"></value>
          <value value="&quot;ka4&quot;"></value>
          <value value="&quot;ka5&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="10"></value>
          <value value="30"></value>
          <value value="50"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="cernozemePK" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
          <value value="50"></value>
          <value value="125"></value>
          <value value="250"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;ce1&quot;"></value>
          <value value="&quot;ce2&quot;"></value>
          <value value="&quot;ce3&quot;"></value>
          <value value="&quot;ce4&quot;"></value>
          <value value="&quot;ce5&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="ePKnt" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="36"></value>
          <value value="72"></value>
          <value value="108"></value>
          <value value="144"></value>
          <value value="180"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="10"></value>
          <value value="30"></value>
          <value value="50"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="eKPnt" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="36"></value>
          <value value="72"></value>
          <value value="108"></value>
          <value value="144"></value>
          <value value="180"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="10"></value>
          <value value="30"></value>
          <value value="50"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="eKPntTwo" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;two&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="10"></value>
          <value value="30"></value>
          <value value="50"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="eKPntTwo (copy)" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;two&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="10"></value>
          <value value="30"></value>
          <value value="50"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="ePKnt288" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="36"></value>
          <value value="72"></value>
          <value value="144"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="10"></value>
          <value value="30"></value>
          <value value="50"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="eKPnt288_2" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="36"></value>
          <value value="72"></value>
          <value value="144"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="10"></value>
          <value value="30"></value>
          <value value="50"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="p400s1p" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
          <value value="50"></value>
          <value value="100"></value>
          <value value="200"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="p400s1k" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
          <value value="50"></value>
          <value value="100"></value>
          <value value="200"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="cernozemeKP" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
          <value value="50"></value>
          <value value="125"></value>
          <value value="250"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;ce1&quot;"></value>
          <value value="&quot;ce2&quot;"></value>
          <value value="&quot;ce3&quot;"></value>
          <value value="&quot;ce4&quot;"></value>
          <value value="&quot;ce5&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="cernozemeKP250" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="250"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;ce1&quot;"></value>
          <value value="&quot;ce2&quot;"></value>
          <value value="&quot;ce3&quot;"></value>
          <value value="&quot;ce4&quot;"></value>
          <value value="&quot;ce5&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="cernozemePK250" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="250"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;ce1&quot;"></value>
          <value value="&quot;ce2&quot;"></value>
          <value value="&quot;ce3&quot;"></value>
          <value value="&quot;ce4&quot;"></value>
          <value value="&quot;ce5&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="kambizemeKP" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
          <value value="50"></value>
          <value value="125"></value>
          <value value="250"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;ka1&quot;"></value>
          <value value="&quot;ka2&quot;"></value>
          <value value="&quot;ka3&quot;"></value>
          <value value="&quot;ka4&quot;"></value>
          <value value="&quot;ka5&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="15"></value>
          <value value="30"></value>
          <value value="45"></value>
          <value value="60"></value>
          <value value="75"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="kambizemePK" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
          <value value="50"></value>
          <value value="125"></value>
          <value value="250"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;ka1&quot;"></value>
          <value value="&quot;ka2&quot;"></value>
          <value value="&quot;ka3&quot;"></value>
          <value value="&quot;ka4&quot;"></value>
          <value value="&quot;ka5&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="p288p" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="36"></value>
          <value value="72"></value>
          <value value="144"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="p288k" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="36"></value>
          <value value="72"></value>
          <value value="144"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="p500p" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
          <value value="50"></value>
          <value value="125"></value>
          <value value="250"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="p500k" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="25"></value>
          <value value="50"></value>
          <value value="125"></value>
          <value value="250"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripes&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="20"></value>
          <value value="50"></value>
          <value value="70"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="p400PU" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;ostatní pícniny jednoleté&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="stripe-length">
          <value value="10"></value>
          <value value="20"></value>
          <value value="40"></value>
          <value value="80"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;stripe-inside&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="15"></value>
          <value value="30"></value>
          <value value="45"></value>
          <value value="60"></value>
          <value value="75"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
    <experiment name="blok600d" repetitions="1" sequentialRunOrder="true" runMetricsEveryStep="false">
      <setup>setup</setup>
      <go>get-flow-accumulation
calculate-erosion</go>
      <exitCondition>round-end = true</exitCondition>
      <metrics>
        <metric>total-erosion</metric>
        <metric>highest-c-factor-representation</metric>
      </metrics>
      <constants>
        <enumeratedValueSet variable="crop1">
          <value value="&quot;kukuřice na zrno&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="crop2">
          <value value="&quot;pšenice ozimá&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division">
          <value value="&quot;one110&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="WF?">
          <value value="false"></value>
          <value value="true"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="morphology">
          <value value="&quot;plane&quot;"></value>
          <value value="&quot;convex&quot;"></value>
          <value value="&quot;concave&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="flow_direction">
          <value value="&quot;convergent&quot;"></value>
          <value value="&quot;divergent&quot;"></value>
          <value value="&quot;parallel&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="soil">
          <value value="&quot;černozem&quot;"></value>
          <value value="&quot;kambizem&quot;"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="division_angle">
          <value value="0"></value>
          <value value="15"></value>
          <value value="30"></value>
          <value value="45"></value>
          <value value="60"></value>
          <value value="75"></value>
          <value value="90"></value>
        </enumeratedValueSet>
        <enumeratedValueSet variable="srazky-mm">
          <value value="30"></value>
          <value value="60"></value>
          <value value="120"></value>
        </enumeratedValueSet>
      </constants>
    </experiment>
  </experiments>
</model>
