@echo off
REM Defiller - optional launcher.
REM Only needed if you did NOT enable always-on in vlcrc.
REM Double-click to open VLC with auto-skip, or drag a video file onto this .bat.
start "" "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe" --extraintf=luaintf --lua-intf=defiller-intf %*
