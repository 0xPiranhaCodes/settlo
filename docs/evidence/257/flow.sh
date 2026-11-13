#!/bin/zsh
# flow.sh <out-prefix>: relaunch, record New loan with name "Ravi" through real HID taps, back to Loans.
S=${0:h}; U=$(cat $S/udid); OUT=$1
t() { while (( $# >= 2 )); do $S/simtouch $U down $1 $2; sleep 0.08; $S/simtouch $U up $1 $2; sleep 0.5; shift 2; done; }
shot() { sleep 1.2; xcrun simctl io $U screenshot $OUT-$1.png >/dev/null 2>&1; }
xcrun simctl terminate $U app.settlo 2>/dev/null; xcrun simctl launch $U app.settlo >/dev/null; sleep 6
xcrun simctl io $U recordVideo --codec=h264 --force $OUT.mp4 2>/dev/null & rec=$!
sleep 1.5
t .604 .939; sleep 1; t .626 .092; sleep 1.2
t .54 .37 .495 .75 .495 .878 .495 .878 .495 .878
t .5 .541 .816 .814 .495 .814 .174 .814 .816 .75 .495 .75 .495 .878 .495 .878 .495 .878 .174 .686 .174 .686
t .896 .603; sleep 0.6; t .5 .62; sleep 0.8; t .347 .6875 .11 .755 .493 .816 .759 .6875
t .896 .571; sleep 0.6; t .5 .582; shot typed
t .5 .898; sleep 3; t .08 .042; sleep 1.5; shot detail
t .12 .082; sleep 1.2; shot list
sleep 1.5; kill -INT $rec; wait $rec
