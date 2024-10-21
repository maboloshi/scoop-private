$regRoot = "HKLM:\SOFTWARE"

# 移除注册表项
function Remove-RegistryKey {
    param (
        [string]$Path,
        [string]$Name = ""
    )
    try {
        if ($Name) {
            Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue
        } else {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # 捕获任何错误，继续执行
        Write-Host "Failed to remove registry key or value: $Path\$Name" -ForegroundColor Yellow
    }
}

# 执行注册表项删除操作
Remove-RegistryKey -Path "$regRoot\Classes\.bcss"
Remove-RegistryKey -Path "$regRoot\Classes\.bcpkg"
Remove-RegistryKey -Path "$regRoot\Classes\BeyondCompare.Snapshot"
Remove-RegistryKey -Path "$regRoot\Classes\BeyondCompare.SettingsPackage"
Remove-RegistryKey -Path "$regRoot\Scooter Software\Beyond Compare 5"
Remove-RegistryKey -Path "$regRoot\WOW6432Node\Scooter Software\Beyond Compare 5"
Remove-RegistryKey -Path "$regRoot\Microsoft\Windows\CurrentVersion\App Paths\BCompare.exe"
Remove-RegistryKey -Path "$regRoot\Classes\CLSID\{812BC6B5-83CF-4AD9-97C1-6C60C8D025C5}"
Remove-RegistryKey -Path "$regRoot\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved" -Name "{812BC6B5-83CF-4AD9-97C1-6C60C8D025C5}"
Remove-RegistryKey -Path "$regRoot\Classes\*\shellex\ContextMenuHandlers\CirrusShellEx"
Remove-RegistryKey -Path "$regRoot\Classes\Folder\shellex\ContextMenuHandlers\CirrusShellEx"
Remove-RegistryKey -Path "$regRoot\Classes\lnkfile\shellex\ContextMenuHandlers\CirrusShellEx"
Remove-RegistryKey -Path "$regRoot\Classes\Directory\shellex\ContextMenuHandlers\CirrusShellEx"

# 卸载 BeyondCompare.5.ShellExt App
Get-AppxPackage -Name 'ScooterSoftware.BeyondCompare.5.ShellExt' -AllUsers | Remove-AppxPackage -AllUsers | Out-Null
