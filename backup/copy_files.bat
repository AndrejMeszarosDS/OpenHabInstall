set "targetDir=C:\Users\Andi\OneDrive\MyImportantTextFiles\OpenHabInstall\backup\data"

xcopy X:\items\*.items "%targetDir%" /Y /I
xcopy X:\rules\*.rules "%targetDir%" /Y /I
xcopy X:\things\*.things "%targetDir%" /Y /I
xcopy Y:\jsondb\ui*.json "%targetDir%" /Y /I


