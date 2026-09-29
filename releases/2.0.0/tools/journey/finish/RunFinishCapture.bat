@echo off
rem Renders the Journey finish animations with the real Goober rig.
rem Output: this folder\finish-captures\*.png
"E:\SteamLibrary\steamapps\common\Goober Dash\upguys.exe" -s "user://mod/tools/journey/finish/FinishCapture.gd"
explorer "%APPDATA%\Godot\app_userdata\Goober Dash\mod\finish-captures"
