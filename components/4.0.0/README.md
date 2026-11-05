# Goobplayability 4.0 Windows components

1. Install the 4.0 client update from Settings. Close Goober Dash.
2. Download the [Windows components ZIP](./Goobplayability-4.0-Windows-components.zip) and extract it into `%APPDATA%\Godot\app_userdata\Goober Dash\mod`. The ZIP starts with the `tools` directory.
3. For MP4 recording and the local MP3 decoder, place a Windows FFmpeg build with libx264 support at `mod\tools\clips\bin\ffmpeg.exe`. Use the [FFmpeg download page](https://ffmpeg.org/download.html) to find a Windows build.
4. Start Goober Dash. Clip Studio can now start the instant replay buffer. Overlay Studio uses the bridge for Windows media sessions.

ZIP SHA-256 `21e6930508b5f04b337539bebaff12dfac2532d43135a846908fb740224ebd46`

The ZIP includes the GoobCapture and GoobOverlayBridge binaries and their build source and notices. FFmpeg is obtained separately.
