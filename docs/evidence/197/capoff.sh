#!/bin/zsh
# capoff.sh <app> <outdir>: per tab and theme, held HID drags that scroll about 4, 20, 40 and 60pt.
S=${0:a:h}; U=$(cat $S/udid); OUT=$2; mkdir -p $OUT; B=app.settlo
typeset -A R; R=(home /home spaces /spaces loans /loans activity /activity)
xcrun simctl terminate $U $B 2>/dev/null; xcrun simctl uninstall $U $B 2>/dev/null; xcrun simctl install $U $1
conf() { local D=$(xcrun simctl get_app_container $U $B data)/Documents; mkdir -p $D; printf "$1" > $D/capture.txt; }
# Flutter starts scrolling after an 18pt slop on the 874pt screen.
moves() { local f=$(( ($1+18)/874.0 )); local a=(down 0.5 0.75); local y; for i in {1..25}; do y=$((0.75 - f*i/25.0)); a+=(move 0.5 $y); done; for i in {1..12}; do a+=(move 0.5 $y); done; $S/simtouch $U ${a[@]}; Y=$y; }
for t in dark light; do for s in home spaces loans activity; do
  xcrun simctl terminate $U $B 2>/dev/null
  conf "THEME=$t\nROUTE=${R[$s]}\nUNREAD=3\n"
  xcrun simctl launch $U $B >/dev/null; sleep 6
  xcrun simctl io $U screenshot $OUT/$s-$t-0.png >/dev/null 2>&1
  for d in 4 20 40 60; do
    moves $d; sleep 0.6; xcrun simctl io $U screenshot $OUT/$s-$t-$d.png >/dev/null 2>&1
    $S/simtouch $U up 0.5 $Y; sleep 1.2
  done
done; done
