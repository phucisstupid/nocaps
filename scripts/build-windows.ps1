$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    cmake -S Windows -B .build/windows -A x64
    if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }
    cmake --build .build/windows --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    ctest --test-dir .build/windows -C Release --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw 'Windows self-checks failed.' }

    New-Item -ItemType Directory -Force build | Out-Null
    $archive = 'build/NoCaps-Windows-x64.zip'
    Compress-Archive -Path .build/windows/Release/NoCaps.exe -DestinationPath $archive -Force
    $checksum = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
    "$checksum  NoCaps-Windows-x64.zip" | Set-Content "$archive.sha256" -Encoding ascii
    Write-Output "Built $((Get-Location).Path)/$archive"
} finally {
    Pop-Location
}
