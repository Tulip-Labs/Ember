EMBER 3.1 - see CHANGES.txt for what is new.
Build: ./build.sh   (needs mingw-w64: x86_64-w64-mingw32-gcc + windres)

EMBER 3.0 — the shell in the new house style
=============================================
Same trusted mechanics as 2.1, new skin: a merged pastel gradient,
frosted-glass cards, Nunito type, navy ink text — the Lite 1.x look.

!!!!!!!!!!!!!!!!!!!!!!!!!!!!  SECURITY WARNING  !!!!!!!!!!!!!!!!!!!!!!!!!!!!
Windows Defender and SmartScreen will very likely flag this unsigned Ember as
suspicious, because replacing your shell is exactly what some malware does.
That is a false positive — Ember is your own program, written and built for
you. Click "More info" -> "Run anyway", and if Defender quarantines it,
restore/allow it from Protection history. Unsigned + shell replacement is
inherently flag-shaped; the code does nothing else.
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

WHAT YOU SEE
- A calm pastel backdrop: five soft color fields melted into each other
  (the gradient is rendered once and cached — painting stays cheap)
- A dashboard row up top: a wide date + clock card, then CPU, MEMORY,
  NETWORK, DISK and BATTERY (when present) as frosted cards, each with a
  hand-drawn style icon on a pastel chip
- A frosted strip under it: APPS count, quick chips for Explorer and the
  Desktop folder, and five theme dots at the right end
- Your apps below as frosted tiles with navy names (Start Menu scan)
- Bottom-left "Ember" wordmark + hints; bottom-right a round power button

THEMES (new in 3.0)
- Five light colorways, same as Lite: Spring Mix (default), Sky, Mint,
  Honey, Blossom. Click a dot in the strip to switch instantly.
- Your choice is remembered (registry HKCU\Software\Ember, value "Theme").

NEW SAFETY NET (3.0)
- Single instance: a named mutex means a second launch of Ember exits
  immediately and silently — Ember can never stack copies of itself.

BEHAVIOR (unchanged from 2.1)
- Windows key shows/hides the screen (clicking an app launches it and hides)
- Click a name to open it. Start typing to filter. Esc clears. Wheel /
  Page Up / Page Down scroll.
- Right-click a name to hide it. Type "hidden" to see hidden apps;
  right-click a hidden name to bring it back.
- Power button (bottom right): Restart / Shut down / Sleep / Sign out /
  Restore Windows Explorer / Exit Ember.

SAFETY NETS (unchanged)
1. Failsafe: if Ember crashes at startup 3 times running, it restores
   Windows Explorer as your shell by itself and tells you. Recovery: Ctrl+Shift+Esc -> Run new task -> explorer.exe. Restore Windows Explorer in the power menu does the same any time.

INSTALL (per-user, no admin): run INSTALAR.bat — it copies Ember.exe to
%LOCALAPPDATA%\Ember, points your shell at it and signs you out once.
DEINSTALAR.bat fully undoes it. (Note: installing resets Ember's saved
settings, including hidden apps and theme.)
