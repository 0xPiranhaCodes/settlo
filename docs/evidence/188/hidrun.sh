#!/bin/zsh
# hidrun.sh <udid> <out-prefix>: taps, home-indicator band taps and a drag-off through Simulator's HID path; crops the bar after each step.
U=$1; OUT=$2; T=$(dirname $0)/simtouch
step=0
shot() { sleep 1.5; xcrun simctl io $U screenshot $OUT-$step.png >/dev/null 2>&1; magick $OUT-$step.png -gravity south -crop 1206x300+0+0 +repage -resize 600x -fill white -undercolor black -gravity northwest -font Helvetica -pointsize 22 -annotate +4+2 "$step $1" $OUT-$step.png; step=$((step+1)); }
tap() { $T $U down $1 $2; sleep 0.08; $T $U up $1 $2; shot "$3"; }
tap 0.396 0.939 "tap Spaces"
tap 0.604 0.939 "tap Loans"
tap 0.816 0.939 "tap Activity"
tap 0.184 0.939 "tap Home"
tap 0.396 0.975 "band Spaces"
tap 0.604 0.975 "band Loans"
tap 0.816 0.975 "band Activity"
tap 0.184 0.975 "band Home"
$T $U down 0.396 0.939; sleep 0.4; for i in 1 2 3 4 5 6 7 8 9 10; do $T $U move $((0.396+0.01*i)) $((0.939-0.03*i)); done; $T $U up 0.5 0.64; shot "drag-off from Spaces"
magick $OUT-{0..8}.png -append $OUT-sheet.png
