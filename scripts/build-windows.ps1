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
    $executable = 'build/NoCaps.exe'
    Copy-Item .build/windows/Release/NoCaps.exe -Destination $executable -Force
    $archive = 'build/NoCaps-Windows-x64.zip'
    Compress-Archive -Path $executable -DestinationPath $archive -Force
    foreach ($file in @($archive, $executable)) {
        $checksum = (Get-FileHash -Algorithm SHA256 $file).Hash.ToLowerInvariant()
        "$checksum  $(Split-Path $file -Leaf)" | Set-Content "$file.sha256" -Encoding ascii
    }
    Write-Output "Built $((Get-Location).Path)/$archive"
} finally {
    Pop-Location
}
