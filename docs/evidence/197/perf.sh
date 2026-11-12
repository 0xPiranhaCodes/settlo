#!/bin/zsh
# perf.sh <app> <outdir> <theme> <route>: scroll recording plus frame timings over a scripted HID scroll.
S=${0:a:h}; U=$(cat $S/udid); OUT=$2; T=$3; B=app.settlo; mkdir -p $OUT; N=${4:t}; N=${N:-home}
xcrun simctl terminate $U $B 2>/dev/null; xcrun simctl uninstall $U $B 2>/dev/null; xcrun simctl install $U $1
D=$(xcrun simctl get_app_container $U $B data)/Documents; mkdir -p $D; printf "THEME=$T\nROUTE=$4\nUNREAD=3\nFRAMES=14\n" > $D/capture.txt
xcrun simctl launch $U $B >/dev/null; sleep 3.5
xcrun simctl io $U recordVideo --codec h264 -f $OUT/$N-$T.mp4 >/dev/null 2>&1 & R=$!
sleep 1
drag() { local a=(down 0.5 $1); local y; for i in {1..30}; do y=$(($1 + ($2-$1)*i/30.0)); a+=(move 0.5 $y); done; a+=(up 0.5 $y); $S/simtouch $U ${a[@]}; }
for k in 1 2 3; do drag 0.80 0.30; sleep 0.9; done
for k in 1 2 3; do drag 0.30 0.80; sleep 0.9; done
sleep 4; kill -INT $R; wait $R
for i in {1..20}; do [ -f $D/frames.txt ] && break; sleep 1; done; cp $D/frames.txt $OUT/frames-$N-$T.txt
