SET oldDir=%CD%
cd %appdata%\.minecraft\resourcepacks
SET newDir=%CD%
cd %oldDir%
if not exist %newDir%\Gondor-DEBUG mkdir %newDir%\Gondor-DEBUG
del %newdir%\Gondor-DEBUG\*.* /s /q
xcopy /y/s %oldDir%\src\main\meta\* %newDir%\Gondor-DEBUG
xcopy /y/s %oldDir%\src\main\pack\* %newDir%\Gondor-DEBUG\assets\minecraft
xcopy /y/s %oldDir%\MCME-UI\src\main\pack\*.* %newDir%\Gondor-DEBUG\assets\minecraft
xcopy /y/s %oldDir%\MCME-Aural-Experience\src\main\pack\*.* %newDir%\Gondor-DEBUG\assets\minecraft
pause
