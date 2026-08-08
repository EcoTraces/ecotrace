@echo off
cd /d "c:\Users\Fatmata Z. Kamara\wastemanagementsystem"
echo Building APK... >> build_log.txt
flutter build apk --release >> build_log.txt 2>&1
echo Build completed with exit code: %ERRORLEVEL% >> build_log.txt
pause
