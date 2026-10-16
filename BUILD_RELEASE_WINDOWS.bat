@echo off
setlocal
where flutter >nul 2>nul || (echo ERROR: Flutter SDK tidak ditemukan di PATH.& exit /b 1)
where python >nul 2>nul || (echo ERROR: Python 3 diperlukan untuk preflight.& exit /b 1)
if "%YOUTUBE_API_KEY%"=="" (echo ERROR: Set environment variable YOUTUBE_API_KEY sebelum build.& exit /b 1)
if not exist "android\local.properties" (echo ERROR: android\local.properties belum ada.& exit /b 1)
if not exist "android\key.properties" (echo ERROR: android\key.properties belum ada.& exit /b 1)

python tool\release_preflight.py
if errorlevel 1 exit /b %errorlevel%

call flutter pub get
if errorlevel 1 exit /b %errorlevel%
call flutter test
if errorlevel 1 exit /b %errorlevel%
call flutter analyze
if errorlevel 1 exit /b %errorlevel%
call flutter build apk --release --dart-define=YOUTUBE_API_KEY=%YOUTUBE_API_KEY%
if errorlevel 1 exit /b %errorlevel%

echo Build release selesai. Lanjutkan checklist RELEASE_QA_CHECKLIST.md sebelum distribusi.
endlocal
