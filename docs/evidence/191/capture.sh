#!/bin/zsh
# capture.sh <before|after>: rest and scrolled shots of each header screen, dark and light.
S=${0:a:h}; U=$UDID; L=$1; OUT=$S/raw/$L; mkdir -p $OUT; B=app.settlo
typeset -A R; R=(home /home space /spaces/s1 balances /spaces/s1/balances profile /home/profile spaces /spaces loans /loans activity /activity loan /loans/l1)
screens=(${=SCREENS:-home space balances profile spaces loans activity loan})
xcrun simctl terminate $U $B 2>/dev/null; xcrun simctl uninstall $U $B 2>/dev/null; xcrun simctl install $U $S/$L.app
conf() { local D=$(xcrun simctl get_app_container $U $B data)/Documents; mkdir -p $D; printf "$1" > $D/capture.txt; }
drag() { local a=(down 0.5 0.75); local y; for i in {1..25}; do y=$((0.75 - $1*i/25.0)); a+=(move 0.5 $y); done; for i in {1..12}; do a+=(move 0.5 $y); done; a+=(up 0.5 $y); $S/simtouch $U ${a[@]}; }
# Claim the one-off reminder prompt on Profile.
conf "THEME=dark\nROUTE=/home/profile\n"; xcrun simctl launch $U $B >/dev/null; sleep 7; $S/simtouch $U down 0.49 0.626; sleep 0.08; $S/simtouch $U up 0.49 0.626; sleep 1
for t in dark light; do for s in $screens; do
  xcrun simctl terminate $U $B 2>/dev/null
  conf "THEME=$t\nROUTE=${R[$s]}\nUNREAD=3\n"
  xcrun simctl launch $U $B >/dev/null
  sleep 6; xcrun simctl io $U screenshot $OUT/$s-$t-rest.png >/dev/null 2>&1
  drag 0.3; sleep 1.5; xcrun simctl io $U screenshot $OUT/$s-$t-scrolled.png >/dev/null 2>&1
done; done
