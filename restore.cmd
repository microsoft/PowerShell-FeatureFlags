@ECHO OFF
pushd "%~dp0"

@nuget install packages.config -ExcludeVersion -NonInteractive -PackageSaveMode nuspec -OutputDirectory External || (
    echo Couldn't install packages
    exit /b 1
)

del /s /q External\*.nupkg


popd