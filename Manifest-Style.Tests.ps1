#Requires -Version 5.1

BeforeDiscovery {
    $manifestPaths = @(
        Get-ChildItem "$PSScriptRoot\bucket", "$PSScriptRoot\deprecated" -Filter '*.json' -File -Recurse |
            ForEach-Object { $_.FullName }
    )

    # Files that contain Chinese must be readable by Windows PowerShell 5.1, which
    # requires an UTF-16 LE BOM for scripts and registry files (see README).
    $nonAsciiScriptPaths = @(
        Get-ChildItem $PSScriptRoot -Include '*.ps1', '*.psm1', '*.reg' -File -Recurse |
            Where-Object { $_.FullName -notmatch '\\\.git\\' } |
            Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match '[\u4e00-\u9fff]' } |
            ForEach-Object { $_.FullName }
    )
}

Describe 'Manifest style' {
    BeforeAll {
        $repoRoot = $PSScriptRoot
        if (-not $repoRoot) { $repoRoot = Split-Path -Parent $PSCommandPath }

        # Collect every line of embedded script from a manifest.
        function Get-EmbeddedScriptLine {
            param([Parameter(Mandatory = $true)] $Manifest)

            $lines = @()
            foreach ($key in 'pre_install', 'post_install', 'pre_uninstall', 'post_uninstall') {
                $value = $Manifest.$key
                if ($value -is [string]) {
                    $lines += $value
                } elseif ($value) {
                    $lines += @($value | Where-Object { $_ -is [string] })
                }
            }
            foreach ($key in 'installer', 'uninstaller') {
                $value = $Manifest.$key
                if ($value -and $value.script) {
                    if ($value.script -is [string]) {
                        $lines += $value.script
                    } else {
                        $lines += @($value.script | Where-Object { $_ -is [string] })
                    }
                }
            }
            foreach ($arch in '64bit', '32bit', 'arm64') {
                $value = $Manifest.architecture.$arch
                if ($value) {
                    foreach ($key in 'pre_install', 'post_install') {
                        if ($value.$key) {
                            $lines += @($value.$key | Where-Object { $_ -is [string] })
                        }
                    }
                }
            }
            return $lines
        }
    }

    It 'manifest files are normalized' {
        $output = & "$repoRoot\bin\format-manifests.ps1" -Check
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
    }

    It '<_> follows the embedded script conventions' -TestCases $manifestPaths {
        $manifest = Get-Content -Path $_ -Raw -Encoding UTF8 | ConvertFrom-Json
        $script = @(Get-EmbeddedScriptLine -Manifest $manifest)

        @($script | Where-Object { $_ -match '-Recurse -Force' }) | Should -BeNullOrEmpty
        @($script | Where-Object { $_ -match 'Remove-Item -R ' }) | Should -BeNullOrEmpty
        @($script | Where-Object { $_ -match 'Remove-Item (?!-Path)(?=''|"|\$|\\)' }) | Should -BeNullOrEmpty
        @($script | Where-Object { $_ -match 'Remove-Item -(Force|Recurse)[^"$|]*["$]' }) | Should -BeNullOrEmpty
        @($script | Where-Object { $_ -match '"## ' }) | Should -BeNullOrEmpty
        @($script | Where-Object { $_ -match '\$runtimeCache' }) | Should -BeNullOrEmpty
        @($script | Where-Object { $_ -match '\$source\s*=' }) | Should -BeNullOrEmpty
        @($script | Where-Object { $_ -match 'Start-Process|System\.Diagnostics\.Process' }) | Should -BeNullOrEmpty
        @($script | Where-Object { $_ -match 'Invoke-ExternalCommand (?!-FilePath)' }) | Should -BeNullOrEmpty
    }
}

Describe 'Script encoding' {
    It '<_> uses UTF-16 LE with BOM' -TestCases $nonAsciiScriptPaths {
        $bytes = [System.IO.File]::ReadAllBytes($_)
        $bytes[0] | Should -Be 0xFF
        $bytes[1] | Should -Be 0xFE
    }
}
