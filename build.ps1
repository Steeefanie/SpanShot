$ErrorActionPreference = "Stop"

# Stop running SpanShot instance if open so the binary can be overwritten cleanly
Get-Process -Name "SpanShot" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 150

$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    throw "csc.exe not found at $csc"
}

$outExe = Join-Path $PSScriptRoot "SpanShot.exe"
$icoPath = Join-Path $PSScriptRoot "assets\SpanShot.ico"
$sources = Get-ChildItem -Path (Join-Path $PSScriptRoot "src\*.cs") | ForEach-Object { $_.FullName }

# If assets\SpanShot.ico is missing, bootstrap-compile once to generate the multi-DPI icon
if (-not (Test-Path $icoPath)) {
    Write-Host "Generating assets\SpanShot.ico ..." -ForegroundColor Cyan
    & $csc /nologo /target:winexe /optimize+ /unsafe+ /out:$outExe $sources
    if ($LASTEXITCODE -ne 0) { throw "Bootstrap compilation failed with exit code $LASTEXITCODE" }
    & $outExe --gen-icon $icoPath
}

Write-Host "Compiling SpanShot.exe with embedded icon ..." -ForegroundColor Cyan
& $csc /nologo /target:winexe /optimize+ /unsafe+ "/win32icon:$icoPath" "/out:$outExe" $sources

if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE"
}

$fileInfo = Get-Item $outExe
Write-Host ("Successfully built: {0} ({1:N1} KB)" -f $fileInfo.FullName, ($fileInfo.Length / 1KB)) -ForegroundColor Green
