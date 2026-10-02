#Requires -Version 5.1
<#
.SYNOPSIS
    Normalize the writing style of the bucket manifests.

.DESCRIPTION
    Applies the repository manifest style rules to every manifest under
    'bucket' and 'deprecated':

      * canonical key order (top level and the common nested objects)
      * '"##"' comment as the first key
      * UTF-8 without BOM, CRLF line endings, four-space indent, final newline

    Manifest values are never modified.

.PARAMETER App
    Manifest name pattern. Wildcards are supported. Defaults to '*' (all).

.PARAMETER Path
    Repository root. Defaults to the parent directory of this script.

.PARAMETER Check
    Do not write anything. Report the manifests that are not normalized and
    exit with a non-zero code when at least one is found.

.EXAMPLE
    PS> .\bin\format-manifests.ps1
    Normalize every manifest in the repository.

.EXAMPLE
    PS> .\bin\format-manifests.ps1 -Check
    Verify that every manifest is normalized.
#>
[CmdletBinding()]
param(
    [String] $App = '*',
    [String] $Path = (Convert-Path (Join-Path $PSScriptRoot '..')),
    [Switch] $Check
)

$ErrorActionPreference = 'Stop'

if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Convert-Path (scoop prefix scoop) }
. "$env:SCOOP_HOME\lib\json.ps1"

# --- style rules -------------------------------------------------------------

# Canonical order of the top level keys.
$TopLevelOrder = @(
    '##', 'version', 'description', 'homepage', 'license', 'notes', 'suggest', 'depends',
    'architecture', 'url', 'hash', 'extract_dir', 'extract_to', 'innosetup',
    'pre_install', 'installer', 'post_install',
    'bin', 'shortcuts', 'env_add_path', 'env_set', 'persist',
    'uninstaller', 'pre_uninstall', 'post_uninstall',
    'checkver', 'autoupdate'
)

# Canonical order of the known nested objects. Objects that are not listed
# (env_set, env_add_path, ...) are data maps and keep their original order.
$NestedOrder = @{
    'license'     = @('identifier', 'url')
    'checkver'    = @('github', 'url', 'script', 'jsonpath', 'regex', 'replace', 'reverse', 'mode')
    'hash'        = @('url', 'regex', 'jsonpath', 'mode', 'type')
    'installer'   = @('file', 'script', 'args')
    'uninstaller' = @('file', 'script', 'args')
    'autoupdate'  = @('architecture', 'url', 'extract_dir', 'hash')
}

# Objects whose own keys are architecture names; every value uses this order.
$ArchitectureOrder = @('url', 'hash', 'extract_dir', 'extract_to', 'pre_install', 'post_install', 'bin', 'shortcuts')
$ArchitectureMaps = @('architecture')

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Invoke-ManifestReorder {
    <#
    .SYNOPSIS
        Rebuild a manifest object in the canonical key order.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $Value,
        [AllowNull()] [String[]] $KeyOrder
    )

    if ($null -eq $Value -or $Value -is [String] -or $Value -is [ValueType]) {
        return $Value
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Management.Automation.PSCustomObject]) {
        $items = @()
        foreach ($item in $Value) {
            $items += , (Invoke-ManifestReorder -Value $item)
        }
        return , $items
    }

    $names = @($Value.PSObject.Properties.Name)
    if ($KeyOrder) {
        $ordered = @($KeyOrder | Where-Object { $names -contains $_ }) + @($names | Where-Object { $KeyOrder -notcontains $_ })
    } else {
        $ordered = $names
    }

    $result = [ordered]@{}
    foreach ($name in $ordered) {
        $child = $Value.$name

        if ($ArchitectureMaps -contains $name -and $child -is [System.Management.Automation.PSCustomObject]) {
            $map = [ordered]@{}
            foreach ($arch in @($child.PSObject.Properties.Name)) {
                $map[$arch] = Invoke-ManifestReorder -Value $child.$arch -KeyOrder $ArchitectureOrder
            }
            $result[$name] = [pscustomobject]$map
            continue
        }

        $childOrder = if ($NestedOrder.ContainsKey($name)) { $NestedOrder[$name] } else { $null }
        $result[$name] = Invoke-ManifestReorder -Value $child -KeyOrder $childOrder
    }

    return [pscustomobject]$result
}

function Get-NormalizedManifest {
    <#
    .SYNOPSIS
        Return the normalized text of a manifest, or $null when it is already normalized.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][String] $FilePath
    )

    $original = Get-Content -Path $FilePath -Raw -Encoding UTF8
    $parsed = $original | ConvertFrom-Json -ErrorAction Stop
    $text = (Invoke-ManifestReorder -Value $parsed -KeyOrder $TopLevelOrder | ConvertToPrettyJson) + "`r`n"

    if ($original -ceq $text) { return $null }
    return $text
}

# --- main --------------------------------------------------------------------

$dirs = @('bucket', 'deprecated') | ForEach-Object { Join-Path $Path $_ } | Where-Object { Test-Path $_ }
$manifests = @($dirs | ForEach-Object { Get-ChildItem -Path $_ -Filter "$App.json" -File -Recurse })

if ($manifests.Count -eq 0) {
    Write-Host 'No manifest found.' -ForegroundColor Yellow
    exit 0
}

$changed = 0
foreach ($manifest in $manifests) {
    $file = $manifest.FullName
    $relative = $file.Substring($Path.Length).TrimStart('\', '/')

    $normalized = Get-NormalizedManifest -FilePath $file
    if ($null -eq $normalized) { continue }

    $changed++
    if ($Check) {
        Write-Host "[!] $relative" -ForegroundColor Yellow
    } else {
        [System.IO.File]::WriteAllText($file, $normalized, $Utf8NoBom)
        Write-Host "[+] $relative" -ForegroundColor Green
    }
}

if ($Check -and $changed -gt 0) {
    Write-Host "`n$changed manifest(s) are not formatted. Run 'bin/format-manifests.ps1' to fix them." -ForegroundColor Red
    exit 1
}

if ($Check) {
    Write-Host "`nAll $($manifests.Count) manifest(s) are formatted." -ForegroundColor Green
} else {
    Write-Host "`n$changed manifest(s) formatted." -ForegroundColor Green
}
exit 0
