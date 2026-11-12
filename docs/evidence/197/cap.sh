#!/bin/zsh
# cap.sh <app> <outdir>: rest, mid (held drag) and scrolled shots of the 4 tab roots, dark and light.
S=${0:a:h}; U=$(cat $S/udid); OUT=$2; mkdir -p $OUT; B=app.settlo
typeset -A R; R=(home /home spaces /spaces loans /loans activity /activity)
xcrun simctl terminate $U $B 2>/dev/null; xcrun simctl uninstall $U $B 2>/dev/null; xcrun simctl install $U $1
conf() { local D=$(xcrun simctl get_app_container $U $B data)/Documents; mkdir -p $D; printf "$1" > $D/capture.txt; }
# moves <dy>: a slow drag up by dy (screen fraction) from 0.75, left held.
moves() { local a=(down 0.5 0.75); local y; for i in {1..25}; do y=$((0.75 - $1*i/25.0)); a+=(move 0.5 $y); done; for i in {1..12}; do a+=(move 0.5 $y); done; $S/simtouch $U ${a[@]}; Y=$y; }
conf "THEME=dark\nROUTE=/home/profile\n"; xcrun simctl launch $U $B >/dev/null; sleep 7; $S/simtouch $U down 0.49 0.626; sleep 0.08; $S/simtouch $U up 0.49 0.626; sleep 1
for t in ${=THEMES:-dark light}; do for s in ${=SCREENS:-home spaces loans activity}; do
  xcrun simctl terminate $U $B 2>/dev/null
  conf "THEME=$t\nROUTE=${R[$s]}\nUNREAD=3\n"
  xcrun simctl launch $U $B >/dev/null
  sleep 6; xcrun simctl io $U screenshot $OUT/$s-$t-rest.png >/dev/null 2>&1
  # Mid: held, so a short tab's bounce can't settle back.
  moves ${MID:-0.05}; sleep 0.6; xcrun simctl io $U screenshot $OUT/$s-$t-mid.png >/dev/null 2>&1
  $S/simtouch $U up 0.5 $Y; sleep 1
  moves 0.25; sleep 0.6; xcrun simctl io $U screenshot $OUT/$s-$t-scrolled.png >/dev/null 2>&1
  $S/simtouch $U up 0.5 $Y; sleep 1
done; done
