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

    Single-element arrays are normalized to scalars so that output is
    identical under Windows PowerShell 5.1 and PowerShell 7+, except for
    nested arrays such as bin/shortcuts ([[target, alias]]), whose
    structure is preserved verbatim. On PS 5.1, ConvertFrom-Json unwraps
    the outer single-element array, so top-level bin/shortcuts are
    repaired from the raw text before reordering.

    Architecture-level bin/shortcuts must use the flat (one-dimensional)
    form; the nested [[...]] form is only supported at the top level.
    Other manifest values are never modified.

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
$ArchitectureOrder = @('url', 'hash', 'extract_dir', 'extract_to', 'pre_install', 'installer', 'post_install', 'bin', 'shortcuts', 'uninstaller', 'checkver')
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
        # Detect nested arrays, e.g. bin/shortcuts' [["exe","alias"]] form.
        # Nested arrays are preserved verbatim; only flat single-element
        # arrays are unwrapped to scalars.
        $isNested = $false
        foreach ($item in $Value) {
            if ($item -is [System.Collections.IEnumerable] -and
                $item -isnot [string] -and
                $item -isnot [System.Management.Automation.PSCustomObject]) {
                $isNested = $true
                break
            }
        }

        $items = @()
        foreach ($item in $Value) {
            $items += , (Invoke-ManifestReorder -Value $item)
        }
        if (-not $isNested -and $items.Count -eq 1) { return $items[0] }
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

function Repair-NestedField {
    <#
    .SYNOPSIS
        Re-wrap the outer single-element array of a nested field that
        Windows PowerShell 5.1's ConvertFrom-Json unwrapped during parsing.

    .DESCRIPTION
        Only applies when the raw text declares the field as '[[...]]' and
        the parsed value's first element is a scalar, which indicates the
        outer array was unwrapped. Multi-element arrays and non-nested
        fields are left untouched.
    #>
    param($Manifest, [string] $Original, [string] $Field)

    if ($Original -notmatch "`"$Field`"\s*:\s*\[\s*\[") { return }
    $val = $Manifest.$Field
    if ($null -eq $val) { return }

    $arr = @($val)
    if ($arr.Count -eq 0) { return }

    $first = $arr[0]
    if ($null -eq $first -or $first -is [string] -or $first -is [ValueType]) {
        $Manifest.$Field = , $arr
    }
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

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

    $original = Get-Content -Path $FilePath -Raw -Encoding UTF8
    try {
        $parsed = $original | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "Invalid JSON in $FilePath : $($_.Exception.Message)"
        return $null
    }

    # PS 5.1 unwraps the outer single-element array of nested fields during
    # parsing; repair the top-level bin/shortcuts before reordering.
    # Architecture-level bin/shortcuts must use the flat form because the
    # raw-text heuristic cannot reliably distinguish top level from arch.
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        Repair-NestedField -Manifest $parsed -Original $original -Field 'bin'
        Repair-NestedField -Manifest $parsed -Original $original -Field 'shortcuts'
    }

    $reordered = Invoke-ManifestReorder -Value $parsed -KeyOrder $TopLevelOrder
    # Pass by parameter (not pipeline) to avoid PS 5.1 unwrapping a
    # top-level single-element array during serialization.
    $text = (ConvertToPrettyJson -data $reordered) + "`r`n"

    if (-not $hasBom -and $original -ceq $text) { return $null }
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

# Every path must reach an exit so that Manifest-Style.Tests.ps1 can rely
# on $LASTEXITCODE to detect -Check failures.
exit 0
