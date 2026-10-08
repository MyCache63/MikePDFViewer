#!/bin/zsh
# Reopen-an-open-file path: Finder-style "open" of a file already showing in a window, then Cmd+P.
V=$1; S=${0:a:h}; APP=$S/dd_$V/Build/Products/Release/MikePDFPrintTest$V.app; P=MikePDFPrintTest$V
open -n "$APP"; sleep 4
for n in Alpha Bravo Charlie Delta Echo; do open -a "$APP" $S/pdfs/Test_$n.pdf; sleep 2; done
for n in Bravo Delta Alpha Echo Charlie Bravo; do
  open -a "$APP" $S/pdfs/Test_$n.pdf; sleep 2.5
osascript <<OSA
tell application "System Events" to tell process "$P"
  set frontmost to true
  delay 0.5
  keystroke "p" using command down
  delay 0.4
  keystroke "p" using command down
  delay 3
  set out to ""
  repeat with x in windows
    if (count of sheets of x) > 0 then set out to out & (name of x) & " | "
    if (value of attribute "AXMain" of x) then set fw to name of x
  end repeat
  log "reopened $n (main: " & fw & ") -> sheets on: " & out
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
