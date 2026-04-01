@echo off
echo Syncing web source files to Tauri repository...
xcopy "d:\Software\Nuztrack\Nuztrack-win32-x64\resources\app\index.html" "d:\Software\Nuztrack\_remote_repo\src\" /Y
xcopy "d:\Software\Nuztrack\Nuztrack-win32-x64\resources\app\renderer.js" "d:\Software\Nuztrack\_remote_repo\src\" /Y
xcopy "d:\Software\Nuztrack\Nuztrack-win32-x64\resources\app\style.css" "d:\Software\Nuztrack\_remote_repo\src\" /Y

cd /d "d:\Software\Nuztrack\_remote_repo"

echo Building Windows Desktop executable...
call npx tauri build

echo Ready for Android! (Just launch Android Studio and press 'Run' or 'Build' so Gradle grabs the new frontend code)

echo Publishing to GitHub...
git add .
git commit -m "Update via script"
git push

echo Publish complete!
pause
