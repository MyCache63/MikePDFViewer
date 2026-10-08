#!/bin/zsh
V=$1; S=${0:a:h}; APP=$S/dd_$V/Build/Products/Release/MikePDFPrintTest$V.app; P=MikePDFPrintTest$V
open -n "$APP"; sleep 4
for n in Alpha Bravo Charlie Delta Echo Foxtrot Golf Hotel; do open -a "$APP" $S/pdfs/Test_$n.pdf; sleep 2; done
osascript -e "tell application \"System Events\" to tell process \"$P\" to click menu item \"Put Background Windows to Sleep\" of menu \"Window\" of menu bar 1"
sleep 2
for n in Charlie Foxtrot Alpha Hotel Delta Charlie Golf; do
osascript <<OSA
tell application "System Events" to tell process "$P"
  set frontmost to true
  set w to (first window whose name contains "$n")
  perform action "AXRaise" of w
  delay 2
  keystroke "p" using command down
  delay 3
  set out to ""
  repeat with x in windows
    if (count of sheets of x) > 0 then set out to out & (name of x) & " | "
  end repeat
  set fw to name of window 1
  log "pressed in $n (front: " & fw & ") -> sheets on: " & out & " windows=" & (count of windows)
  repeat with x in windows
    repeat while (count of sheets of x) > 0
      try
        click button "Cancel" of sheet 1 of x
      on error
        key code 53
      end try
      delay 0.8
    end repeat
  end repeat
end tell
OSA
done
osascript -e "tell application \"$P\" to quit"
