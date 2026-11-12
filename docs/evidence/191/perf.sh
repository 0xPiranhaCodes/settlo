#!/bin/zsh
# perf.sh <before|after> <theme>: Home scroll recording plus frame timings over the same scripted HID scroll.
S=${0:a:h}; U=$UDID; L=$1; T=$2; B=app.settlo; mkdir -p $S/video $S/frames
xcrun simctl terminate $U $B 2>/dev/null; xcrun simctl uninstall $U $B 2>/dev/null; xcrun simctl install $U $S/$L.app
D=$(xcrun simctl get_app_container $U $B data)/Documents; mkdir -p $D; printf "THEME=$T\nROUTE=/home\nUNREAD=3\nFRAMES=14\n" > $D/capture.txt
xcrun simctl launch $U $B >/dev/null; sleep 3.5
xcrun simctl io $U recordVideo --codec h264 -f $S/video/$L-$T.mp4 >/dev/null 2>&1 & R=$!
sleep 1
drag() { local a=(down 0.5 $2); local y; for i in {1..30}; do y=$(($2 + ($3-$2)*i/30.0)); a+=(move 0.5 $y); done; a+=(up 0.5 $y); $S/simtouch $U ${a[@]}; }
for k in 1 2 3; do drag x 0.80 0.30; sleep 0.9; done
for k in 1 2 3; do drag x 0.30 0.80; sleep 0.9; done
sleep 4; kill -INT $R; wait $R
sleep 2; cp $D/frames.txt $S/frames/$L-$T.txt
