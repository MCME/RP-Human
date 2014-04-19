SET oldDir=%CD%
cd %appdata%\.minecraft\resourcepacks
SET newDir=%CD%
cd %oldDir%
if not exist %newDir%\MCME-Gondor-DEBUG mkdir %newDir%\MCME-Gondor-DEBUG
del %newdir%\MCME-Gondor-DEBUG\*.* /s /q
xcopy /y/s %oldDir%\src\main\meta\* %newDir%\MCME-Gondor-DEBUG
xcopy /y/s %oldDir%\src\main\pack\* %newDir%\MCME-Gondor-DEBUG\assets\minecraft
xcopy /y/s %oldDir%\MCME-UI\src\main\pack\*.* %newDir%\MCME-Gondor-DEBUG\assets\minecraft
xcopy /y/s %oldDir%\MCME-Aural-Experience\src\main\pack\*.* %newDir%\MCME-Gondor-DEBUG\assets\minecraft
