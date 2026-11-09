$ErrorActionPreference = "Stop"

# Stop running SpanShot instance if open so the binary can be overwritten cleanly
Get-Process -Name "SpanShot" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 150

$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) {
    throw "csc.exe not found at $csc"
}

$outExe = Join-Path $PSScriptRoot "SpanShot.exe"
$sources = Get-ChildItem -Path (Join-Path $PSScriptRoot "src\*.cs") | ForEach-Object { $_.FullName }

Write-Host "Compiling SpanShot.exe ..." -ForegroundColor Cyan
& $csc /nologo /target:winexe /optimize+ /unsafe+ /out:$outExe $sources

if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE"
}

$fileInfo = Get-Item $outExe
Write-Host ("Successfully built: {0} ({1:N1} KB)" -f $fileInfo.FullName, ($fileInfo.Length / 1KB)) -ForegroundColor Green
