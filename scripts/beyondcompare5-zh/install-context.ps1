$regRoot = "HKLM:\SOFTWARE"
$bcExePath = "$PSScriptRoot\BCompare.exe"

# 使用动态注册表路径
New-Item -Path "$regRoot\Scooter Software\Beyond Compare 5" -Force | Out-Null
New-ItemProperty -Path "$regRoot\Scooter Software\Beyond Compare 5" -Name "ExePath" -Value $bcExePath -Force | Out-Null
New-Item -Path "$regRoot\Scooter Software\Beyond Compare 5\BcShellEx" -Force | Out-Null
New-ItemProperty -Path "$regRoot\Scooter Software\Beyond Compare 5\BcShellEx" -Name "SavedLeft" -Value $bcExePath -Force | Out-Null

New-Item -Path "$regRoot\WOW6432Node\Scooter Software\Beyond Compare 5" -Force | Out-Null
New-ItemProperty -Path "$regRoot\WOW6432Node\Scooter Software\Beyond Compare 5" -Name "ExePath" -Value $bcExePath -Force | Out-Null
New-Item -Path "$regRoot\WOW6432Node\Scooter Software\Beyond Compare 5\BcShellEx" -Force | Out-Null
New-ItemProperty -Path "$regRoot\WOW6432Node\Scooter Software\Beyond Compare 5\BcShellEx" -Name "SavedLeft" -Value $bcExePath -Force | Out-Null

$clsidPath = "$regRoot\Classes\CLSID\{812BC6B5-83CF-4AD9-97C1-6C60C8D025C5}"
New-Item -Path $clsidPath -Force | Out-Null
New-ItemProperty -Path $clsidPath -Name "(default)" -Value "CirrusShellEx" -Force | Out-Null
New-Item -Path "$clsidPath\InProcServer32" -Force | Out-Null
New-ItemProperty -Path "$clsidPath\InProcServer32" -Name "(default)" -Value "$PSScriptRoot\BCShellEx64.dll" -Force | Out-Null
New-ItemProperty -Path "$clsidPath\InProcServer32" -Name "ThreadingModel" -Value "Apartment" -Force | Out-Null

# 注册 App Paths
$appPaths = "$regRoot\Microsoft\Windows\CurrentVersion\App Paths\BCompare.exe"
New-Item -Path $appPaths -Force | Out-Null
New-ItemProperty -Path $appPaths -Name "(default)" -Value $bcExePath -Force | Out-Null
New-ItemProperty -Path $appPaths -Name "UseURL" -Value 1 -PropertyType "DWord" -Force | Out-Null

# 注册文件扩展名和图标
$regClasses = @(
    @{Path = "$regRoot\Classes\.bcss"; Value = "BeyondCompare.Snapshot"},
    @{Path = "$regRoot\Classes\.bcpkg"; Value = "BeyondCompare.SettingsPackage"},
    @{Path = "$regRoot\Classes\BeyondCompare.Snapshot"; Value = "Beyond Compare Snapshot"},
    @{Path = "$regRoot\Classes\BeyondCompare.Snapshot\DefaultIcon"; Value = "$bcExePath,0"},
    @{Path = "$regRoot\Classes\BeyondCompare.Snapshot\shell\open\command"; Value = "`"$bcExePath`" `"%1`""},
    @{Path = "$regRoot\Classes\BeyondCompare.SettingsPackage"; Value = "Beyond Compare Settings Package"},
    @{Path = "$regRoot\Classes\BeyondCompare.SettingsPackage"; Name = "EditFlags"; Value = 0x00100000; PropertyType = "DWord"},
    @{Path = "$regRoot\Classes\BeyondCompare.SettingsPackage\DefaultIcon"; Value = "$bcExePath,0"},
    @{Path = "$regRoot\Classes\BeyondCompare.SettingsPackage\shell\open\command"; Value = "`"$bcExePath`" `"%1`""}
)

foreach ($item in $regClasses) {
    New-Item -Path $item.Path -Force | Out-Null
    if ($item.PropertyType) {
        New-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -PropertyType $item.PropertyType -Force | Out-Null
    } else {
        Set-ItemProperty -Path $item.Path -Name "(default)" -Value $item.Value -Force | Out-Null
    }
}

# 注册上下文菜单扩展
$menuHandlers = @(
    "$regRoot\Classes\*\shellex\ContextMenuHandlers\CirrusShellEx",
    "$regRoot\Classes\Folder\shellex\ContextMenuHandlers\CirrusShellEx",
    "$regRoot\Classes\lnkfile\shellex\ContextMenuHandlers\CirrusShellEx",
    "$regRoot\Classes\Directory\shellex\ContextMenuHandlers\CirrusShellEx"
)

foreach ($handler in $menuHandlers) {
    New-Item -Path $handler -Force | Out-Null
    Set-ItemProperty -LiteralPath $handler -Name "(default)" -Value "{812BC6B5-83CF-4AD9-97C1-6C60C8D025C5}" -Force | Out-Null
}

# 注册 Shell 扩展批准
New-Item -Path "$regRoot\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved" -Force | Out-Null
New-ItemProperty -Path "$regRoot\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved" -Name "{812BC6B5-83CF-4AD9-97C1-6C60C8D025C5}" -Value "Beyond Compare 5 Shell Extension" -Force | Out-Null

# 安装 BeyondCompare.5.ShellExt App
Add-AppxPackage -Path "$PSScriptRoot\BCShellEx.msix" -AllUsers | Out-Null
