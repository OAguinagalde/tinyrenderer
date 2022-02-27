param (
    [Switch]$Release
)
if (!(Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    throw [Exception]::new("cl.exe is not in path!")
}
if (!(Test-Path "bin")) { $null = New-Item "bin" -Type Directory }
if (!(Test-Path "obj")) { $null = New-Item "obj" -Type Directory }
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
    cl main.cpp tgaimage.cpp model.cpp /Zi /Fe".\bin\main.exe" /Fo".\obj\" /Fd".\obj\" /nologo /O2 /EHsc
}
else {
    cl main.cpp tgaimage.cpp model.cpp /Zi /Fe".\bin\main.exe" /Fo".\obj\" /Fd".\obj\" /nologo /Od /EHsc
}

if ($?) {
    Write-Host "OK" -ForeGroundColor Green
}