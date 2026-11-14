#!/bin/zsh
# t.sh <shot-name|-> x y [x y ...]: HID taps, then a screenshot named <shot-name>.
D=${0:h}; U=$(cat $D/udid); N=$1; shift
while (( $# >= 2 )); do $D/simtouch $U down $1 $2; sleep 0.08; $D/simtouch $U up $1 $2; sleep 1.2; shift 2; done
[[ $N != - ]] && { sleep 0.8; xcrun simctl io $U screenshot $D/$N.png >/dev/null 2>&1; magick $D/$N.png -resize 390x $D/$N.s.png; }
