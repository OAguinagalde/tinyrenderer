param (
    [Switch]$Run,
    [Switch]$Release,
    [Switch]$DebuggerOpen,
    [Switch]$HotReloaded,
    [Switch]$Reload
)
if (!(Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw [Exception]::new("cl.exe is not in path!")
}

if ($DebuggerOpen) {
    
    if (!(Test-Path ".\bin\main.exe")) {
        throw [Exception]::new("Build the project first!")
    }

    # Check if debugger running already
    $exists = $false;
    Get-Process "*devenv*" | ForEach-Object {
        $exists = $exists -or $_.mainWindowTitle.contains("tinyrenderer")
    }

    if ($exists) {
        throw [Exception]::new("Debugger already open!")
    }

    devenv /NoSplash /DebugExe .\bin\main.exe
    return
}

if (!(Test-Path "bin")) { $null = New-Item "bin" -Type Directory }
if (!(Test-Path "obj")) { $null = New-Item "obj" -Type Directory }


if ($HotReloaded) {
    if ($Release) {

    }
    else {

        if (!$Reload) {
            # make win32.dll
            cl /D_USRDLL /D_WINDLL /DWIN32_COMPILEDLL src\win32.cpp /Zi /Fo".\obj\" /Fd".\obj\" /nologo /Od /EHsc /link /DLL /OUT:.\bin\win32.dll
            if (!$?) {throw [Exception]::new("cl.exe failed!")}

            # make the host application that manages the hot reloading
            cl src\hr_host.cpp src\util.cpp /Zi /Fe".\bin\main.exe" /Fo".\obj\" /Fd".\obj\" /nologo /Od /EHsc /link /LIBPATH:.\bin
            if (!$?) {throw [Exception]::new("cl.exe failed!")}
        }

        # make hot reloaded application dll, whenever this gets compiled it will be hot reloaded if the host app is running
        # /link /LIBPATH:.\bin is because im building win32.dll and win32.lib and putting it in bin, and this app needs that .lib file and expects it to exist
        cl /D_USRDLL /D_WINDLL `
        src\hr_app.cpp `
        src\util.cpp `
        src\model.cpp `
        src\tgaimage.cpp `
        /Fo".\obj\" /Fd".\obj\" /nologo /Od /EHsc /link /DLL /OUT:.\bin\hr_app.dll /LIBPATH:.\bin
        if (!$?) {throw [Exception]::new("cl.exe failed!")}
        if ($Reload) { return; }
    }
}
else {
    # Zi for debug information
    # Fe for executable output path
    # Fo for intermediate objects path
    # Fd for debugging files path
    # nologo for no logo, duh
    # 0d for disabling optimizations
    # 02 for fastest optimizations
    # /WX /W4 Warnings as error
    # /EHsc for exceptions
    if ($Release) {
        cl `
        src\main.cpp `
        src\util.cpp `
        src\model.cpp `
        src\win32.cpp `
        src\tgaimage.cpp `
        src\my_gl.cpp `
        /Zi /Fe".\bin\main.exe" /Fo".\obj\" /Fd".\obj\" /nologo /O2 /EHsc
        if (!$?) {throw [Exception]::new("cl.exe failed!")}
    }
    else {
        cl `
        src\main.cpp `
        src\util.cpp `
        src\model.cpp `
        src\win32.cpp `
        src\tgaimage.cpp `
        src\my_gl.cpp `
        /Zi /Fe".\bin\main.exe" /Fo".\obj\" /Fd".\obj\" /nologo /Od /EHsc
        if (!$?) {throw [Exception]::new("cl.exe failed!")}
    }
}

# setup the resources that the binary requires.
# its required that .\bin and .\res exist
if ((test-path ".\bin") -and ( Test-Path ".\res")) {
    
    # Create a symbolic link to the res folder in the binary output folder
    if (!(Test-Path ".\bin\res")) {
        $null = New-Item -Path ".\bin\res" -ItemType Junction -Value ".\res"
        # delete safely Remove-Item .\bin\res -Recurse -Force
    }
}
else {
    throw [Exception]::new("Couldn't find the .\bin or .\res folder!")
}

Write-Host "OK" -ForeGroundColor Green

if ($Run) {
    .\bin\main.exe
}