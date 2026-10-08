#!/bin/zsh
# usage: run.sh <Old|New>  -> opens 4 PDFs in the test copy, presses Cmd+P in each window in turn, counts print sheets
V=$1; S=${0:a:h}; APP=$S/dd_$V/Build/Products/Release/MikePDFPrintTest$V.app; P=MikePDFPrintTest$V
open -n "$APP"; sleep 4
for n in Alpha Bravo Charlie Delta; do open -a "$APP" $S/pdfs/Test_$n.pdf; sleep 2.5; done
for round in 1 2; do
for n in Bravo Delta Alpha Charlie; do
osascript <<OSA
tell application "System Events" to tell process "$P"
  set frontmost to true
  set w to (first window whose name contains "$n")
  perform action "AXRaise" of w
  delay 1.2
  keystroke "p" using command down
  delay 2.5
  set out to ""
  repeat with x in windows
    if (count of sheets of x) > 0 then set out to out & (name of x) & " | "
  end repeat
  log "round $round pressed in $n -> sheets on: " & out
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
done; done
osascript -e "tell application \"$P\" to quit"
