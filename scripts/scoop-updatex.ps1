# 用法：scoop updatex <app> [选项]
# Summary: 🚀 增强的 Scoop 更新命令，更新应用程序或 Scoop 自身
# Help: 'scoop updatex' 将 Scoop 更新至最新版本
# 'scoop updatex <app>' 将安装该应用的新版本（如果存在）
#
# 参数:
#  [app...]         要更新的特定应用列表，不指定则更新所有应用
#  *                   更新所有应用（与 -All 相同）
#
# 选项：
#   -f, --force            即使没有新版本也强制更新
#   -g, --global           更新全局安装的应用
#   -i, --independent      不自动安装依赖项
#   -k, --no-cache         不使用下载缓存
#   -s, --skip-hash-check  跳过哈希值校验（请谨慎使用！）
#   -q, --quiet            隐藏非必要信息
#   -a, --all              更新所有应用（可作为 '*' 的替代方案）
#   -e, --skip-errors      遇到错误时跳过并继续更新其他应用
#
# 示例:
#  scoop updatex                          # 更新所有应用
#  scoop updatex git nodejs               # 只更新 git 和 nodejs
#  scoop updatex -e -f                    # 强制更新所有应用，跳过错误（使用短参数）
#  scoop updatex * --global --skip-errors # 更新所有全局应用，跳过错误（使用长参数）
#
# 特点:
#  ✅ 基于原始 scoop update 逻辑，优先更新 Scoop 自身
#  ✅ 单个应用更新失败不会中断整个更新过程
#  ✅ 提供详细的更新摘要报告
#  ✅ 支持交互式错误处理

# 导入必要的库（与原脚本相同）
. "$PSScriptRoot\..\lib\getopt.ps1" # 'getopt'
. "$PSScriptRoot\..\lib\json.ps1" # 'save_install_info' in 'manifest.ps1' (indirectly)
# . "$PSScriptRoot\..\lib\system.ps1"
# . "$PSScriptRoot\..\lib\shortcuts.ps1"
# . "$PSScriptRoot\..\lib\psmodules.ps1"
# . "$PSScriptRoot\..\lib\decompress.ps1"
. "$PSScriptRoot\..\lib\manifest.ps1" # 'manifest' 'install_info' 'Select-CurrentVersion' (indirectly)
. "$PSScriptRoot\..\lib\versions.ps1" # 'Select-CurrentVersion'
# . "$PSScriptRoot\..\lib\depends.ps1"
# . "$PSScriptRoot\..\lib\install.ps1"
. "$PSScriptRoot\..\lib\download.ps1" # 'Get-UserAgent'
if (get_config USE_SQLITE_CACHE) {
    . "$PSScriptRoot\..\lib\database.ps1" # 'Set-ScoopDB'
}

$opt, $apps, $err = getopt $args 'gfiksqae' 'global', 'force', 'independent', 'no-cache', 'skip-hash-check', 'quiet', 'all', 'skip-errors'
if ($err) { "scoop updatex: $err"; exit 1 }
$global = $opt.g -or $opt.global
$force = $opt.f -or $opt.force
$check_hash = !($opt.s -or $opt.'skip-hash-check')
$use_cache = !($opt.k -or $opt.'no-cache')
$quiet = $opt.q -or $opt.quiet
$independent = $opt.i -or $opt.independent
$all = $opt.a -or $opt.all
$skip_errors = $opt.e -or $opt.'skip-errors'

# load config
$configRepo = get_config SCOOP_REPO
if (!$configRepo) {
    $configRepo = 'https://github.com/ScoopInstaller/Scoop'
    set_config SCOOP_REPO $configRepo | Out-Null
}

# Find current update channel from config
$configBranch = get_config SCOOP_BRANCH
if (!$configBranch) {
    $configBranch = 'master'
    set_config SCOOP_BRANCH $configBranch | Out-Null
}

if (($PSVersionTable.PSVersion.Major) -lt 5) {
    # check powershell version
    Write-Output 'PowerShell 5 or later is required to run Scoop.'
    Write-Output 'Upgrade PowerShell: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-windows'
    break
}
$show_update_log = get_config SHOW_UPDATE_LOG $true

# 以下是原始脚本的函数定义，保持不变
function Sync-Scoop {
    [CmdletBinding()]
    Param (
        [Switch]$Log
    )
    # Test if Scoop Core is hold
    if (Test-ScoopCoreOnHold) {
        return
    }

    # check for git
    if (!(Test-GitAvailable)) { abort "Scoop 使用 Git 进行自我更新。请运行 'scoop install git' 后重试。" }

    Write-Host '正在更新 Scoop...'
    $currentdir = versiondir 'scoop' 'current'
    if (!(Test-Path "$currentdir\.git")) {
        $newdir = "$currentdir\..\new"
        $olddir = "$currentdir\..\old"

        # get git scoop
        Invoke-Git -ArgumentList @('clone', '-q', $configRepo, '--branch', $configBranch, '--single-branch', $newdir)

        # check if scoop was successful downloaded
        if (!(Test-Path "$newdir\bin\scoop.ps1")) {
            Remove-Item $newdir -Force -Recurse
            abort "Scoop 下载失败。如果多次出现此问题，请尝试通过 'scoop config rm SCOOP_REPO' 命令移除 SCOOP_REPO 配置。"
        } else {
            # replace non-git scoop with the git version
            try {
                Rename-Item $currentdir 'old' -ErrorAction Stop
                Rename-Item $newdir 'current' -ErrorAction Stop
            } catch {
                Write-Warning $_
                abort "Scoop 更新失败。文件夹正在使用中。请将文件夹 $currentdir 重命名为 ``old``，并将 $newdir 重命名为 ``current``。"
            }
        }
    } else {
        if (Test-Path "$currentdir\..\old") {
            Remove-Item "$currentdir\..\old" -Recurse -Force -ErrorAction SilentlyContinue
        }

        $previousCommit = Invoke-Git -Path $currentdir -ArgumentList @('rev-parse', 'HEAD')
        $currentRepo = Invoke-Git -Path $currentdir -ArgumentList @('config', 'remote.origin.url')
        $currentBranch = Invoke-Git -Path $currentdir -ArgumentList @('branch')

        $isRepoChanged = !($currentRepo -match $configRepo)
        $isBranchChanged = !($currentBranch -match "\*\s+$configBranch")

        # Stash uncommitted changes
        if (Invoke-Git -Path $currentdir -ArgumentList @('diff', 'HEAD', '--name-only')) {
            if (get_config AUTOSTASH_ON_CONFLICT) {
                warn '检测到未提交的更改。正在暂存...'
                Invoke-Git -Path $currentdir -ArgumentList @('stash', 'push', '-m', "WIP at $([System.DateTime]::Now.ToString('o'))", '-u', '-q')
            } else {
                warn '检测到未提交的更改。更新已中止。'
                return
            }
        }

        # Change remote url if the repo is changed
        if ($isRepoChanged) {
            Invoke-Git -Path $currentdir -ArgumentList @('config', 'remote.origin.url', $configRepo)
        }

        # Fetch and reset local repo if the repo or the branch is changed
        if ($isRepoChanged -or $isBranchChanged) {
            # Reset git fetch refs, so that it can fetch all branches (GH-3368)
            Invoke-Git -Path $currentdir -ArgumentList @('config', 'remote.origin.fetch', '+refs/heads/*:refs/remotes/origin/*')
            # fetch remote branch
            Invoke-Git -Path $currentdir -ArgumentList @('fetch', '--force', 'origin', "refs/heads/$configBranch`:refs/remotes/origin/$configBranch", '-q')
            # checkout and track the branch
            Invoke-Git -Path $currentdir -ArgumentList @('checkout', '-B', $configBranch, '-t', "origin/$configBranch", '-q')
            # reset branch HEAD
            Invoke-Git -Path $currentdir -ArgumentList @('reset', '--hard', "origin/$configBranch", '-q')
        } else {
            Invoke-Git -Path $currentdir -ArgumentList @('pull', '-q')
        }

        $res = $lastexitcode
        if ($Log) {
            Invoke-GitLog -Path $currentdir -CommitHash $previousCommit
        }

        if ($res -ne 0) {
            abort '更新失败。'
        }
    }

    shim "$currentdir\bin\scoop.ps1" $false
}

function Sync-Bucket {
    Param (
        [Switch]$Log
    )
    Write-Host '正在更新 Buckets...'

    if (!(Test-Path (Join-Path (Find-BucketDirectory 'main' -Root) '.git'))) {
        info "将 'main' buckets 转换为 git 仓库..."
        $status = rm_bucket 'main'
        if ($status -ne 0) {
            abort "未能移除本地 “main” Buckets。"
        }
        $status = add_bucket 'main' (known_bucket_repo 'main')
        if ($status -ne 0) {
            abort "无法添加远程 'main' bucket."
        }
    }


    $buckets = Get-LocalBucket | ForEach-Object {
        $path = Find-BucketDirectory $_ -Root
        return @{
            name  = $_
            valid = Test-Path (Join-Path $path '.git')
            path  = $path
        }
    }

    $buckets | Where-Object { !$_.valid } | ForEach-Object { Write-Host "'$($_.name)' is not a git repository. Skipped." }

    $updatedFiles = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    $removedFiles = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        # Parallel parameter is available since PowerShell 7
        $buckets | Where-Object { $_.valid } | ForEach-Object -ThrottleLimit 5 -Parallel {
            . "$using:PSScriptRoot\..\lib\core.ps1"
            . "$using:PSScriptRoot\..\lib\buckets.ps1"

            $name = $_.name
            $bucketLoc = $_.path
            $innerBucketLoc = Find-BucketDirectory $name

            $previousCommit = Invoke-Git -Path $bucketLoc -ArgumentList @('rev-parse', 'HEAD')
            Invoke-Git -Path $bucketLoc -ArgumentList @('pull', '-q')
            if ($using:Log) {
                Invoke-GitLog -Path $bucketLoc -Name $name -CommitHash $previousCommit
            }
            if (get_config USE_SQLITE_CACHE) {
                Invoke-Git -Path $bucketLoc -ArgumentList @('diff', '--name-status', $previousCommit) | ForEach-Object {
                    $status, $file = $_ -split '\s+', 2
                    $filePath = Join-Path $bucketLoc $file
                    if ($filePath -match "^$([regex]::Escape($innerBucketLoc)).*\.json$") {
                        switch ($status) {
                            { $_ -in 'A', 'M', 'R' } {
                                [void]($using:updatedFiles).Add($filePath)
                            }
                            'D' {
                                [void]($using:removedFiles).Add([pscustomobject]@{
                                        Name   = ([System.IO.FileInfo]$file).BaseName
                                        Bucket = $name
                                    })
                            }
                        }
                    }
                }
            }
        }
    } else {
        $buckets | Where-Object { $_.valid } | ForEach-Object {
            $name = $_.name
            $bucketLoc = $_.path
            $innerBucketLoc = Find-BucketDirectory $name

            $previousCommit = Invoke-Git -Path $bucketLoc -ArgumentList @('rev-parse', 'HEAD')
            Invoke-Git -Path $bucketLoc -ArgumentList @('pull', '-q')
            if ($Log) {
                Invoke-GitLog -Path $bucketLoc -Name $name -CommitHash $previousCommit
            }
            if (get_config USE_SQLITE_CACHE) {
                Invoke-Git -Path $bucketLoc -ArgumentList @('diff', '--name-status', $previousCommit) | ForEach-Object {
                    $status, $file = $_ -split '\s+', 2
                    $filePath = Join-Path $bucketLoc $file
                    if ($filePath -match "^$([regex]::Escape($innerBucketLoc)).*\.json$") {
                        switch ($status) {
                            { $_ -in 'A', 'M', 'R' } {
                                [void]($updatedFiles).Add($filePath)
                            }
                            'D' {
                                [void]($removedFiles).Add([pscustomobject]@{
                                        Name   = ([System.IO.FileInfo]$file).BaseName
                                        Bucket = $name
                                    })
                            }
                        }
                    }
                }
            }
        }
    }
    if ((get_config USE_SQLITE_CACHE) -and ($updatedFiles.Count -gt 0 -or $removedFiles.Count -gt 0)) {
        info '正在更新缓存...'
        Set-ScoopDB -Path $updatedFiles
        $removedFiles | Remove-ScoopDBItem
    }
}

# 主逻辑开始
if (-not ($apps -or $all)) {
    # 没有指定应用，更新 Scoop 自身
    if ($global) {
        error 'scoop updatex：当未指定 <app> 时，--global参数无效。'
        exit 1
    }
    if (!$use_cache) {
        error 'scoop updatex：未指定 <app> 时，--no-cache参数无效。'
        exit 1
    }
    Sync-Scoop -Log:$show_update_log
    Sync-Bucket -Log:$show_update_log
    set_config LAST_UPDATE ([System.DateTime]::Now.ToString('o')) | Out-Null
    success 'Scoop 已成功更新！'
} else {
    if ($global -and !(is_admin)) {
        '错误：您需要管理员权限才能更新全局应用程序。'; exit 1
    }

    $outdated = @()
    $updateScoop = $null -ne ($apps | Where-Object { $_ -eq 'scoop' }) -or (is_scoop_outdated)
    $apps = $apps | Where-Object { $_ -ne 'scoop' }
    $apps_param = $apps

    if ($updateScoop) {
        Sync-Scoop -Log:$show_update_log
        Sync-Bucket -Log:$show_update_log
        set_config LAST_UPDATE ([System.DateTime]::Now.ToString('o')) | Out-Null
        success 'Scoop 已成功更新！'
    }

    if ($apps_param -eq '*' -or $all) {
        $apps = applist (installed_apps $false) $false
        if ($global) {
            $apps += applist (installed_apps $true) $true
        }
    } else {
        if ($apps_param) {
            $apps = Confirm-InstallationStatus $apps_param -Global:$global
        }
    }

    if ($apps) {
        $apps | ForEach-Object {
            ($app, $global) = $_
            $status = app_status $app $global
            if ($status.installed -and ($force -or $status.outdated)) {
                if (!$status.hold) {
                    $outdated += applist $app $global
                    Write-Host -f yellow ("$app`: $($status.version) -> $($status.latest_version){0}" -f ('', ' (global)')[$global])
                } else {
                    warn "'$app' 被锁定在 $($status.version) 版本"
                }
            } elseif ($apps_param -ne '*' -and !$all) {
                if ($status.installed) {
                    ensure_none_failed $app
                    Write-Host "$app`: $($status.version)（最新版本）" -ForegroundColor Green
                } else {
                    info '请重新安装或修复清单文件。'
                }
            }
        }

        if ($outdated -and ((Test-Aria2Enabled) -and (get_config 'aria2-warning-enabled' $true))) {
            warn "Scoop 使用 'aria2c' 进行多连接下载。"
            warn "如果出现问题，请运行 'scoop config aria2-enabled false' 来禁用它。"
            warn "要禁用此警告，请运行 'scoop config aria2-warning-enabled false'。"
        }
        if ($outdated.Length -gt 1) {
            Write-Host -f DarkCyan "正在更新 $($outdated.Length) 个过时应用程序："
        } elseif ($outdated.Length -eq 0) {
            Write-Host -f Green "所有应用的最新版本均已安装！如需更多信息，请尝试运行 'scoop status' 命令"
        } else {
            Write-Host -f DarkCyan '正在更新一个过时的应用程序：'
        }
    }

    # === 增强部分：逐个更新应用并处理错误 ===
    $successCount = 0
    $failCount = 0
    $failedApps = @()

    foreach ($appInfo in $outdated) {
        ($app, $isGlobal) = $appInfo

        # 获取应用状态以显示版本信息
        $status = app_status $app $isGlobal
        $old_version = $status.version
        $new_version = $status.latest_version

        # 显示原脚本的更新提示
        Write-Host "🔄 正在更新: '$app' ($old_version -> $new_version)"

        # 构建 scoop update 命令参数
        $updateArgs = @('update', $app)
        if ($isGlobal) { $updateArgs += '--global' }
        if ($Force) { $updateArgs += '--force' }
        if ($Independent) { $updateArgs += '--independent' }
        if ($NoCache) { $updateArgs += '--no-cache' }
        if ($SkipHashCheck) { $updateArgs += '--skip-hash-check' }
        if ($Quiet) { $updateArgs += '--quiet' }

        try {
            # 直接调用 scoop update 命令（而不是调用 install_app）
            & scoop @updateArgs

            if ($LASTEXITCODE -eq 0) {
                $successCount++
            } else {
                throw "scoop update 返回代码: $LASTEXITCODE"
            }
        } catch {
            Write-Host "错误：'$app' 更新失败" -ForegroundColor Red
            $failCount++
            $failedApps += $app

            if (-not $skip_errors) {
                # 询问用户是否继续
                do {
                    $response = Read-Host "是否继续更新其他应用? (y/N)"
                    if ($response -eq '') { $response = 'N' }
                } while ($response -notmatch '^[yYnN]$')

                if ($response -notmatch '^[yY]$') {
                    Write-Host "⏹️ 用户中止更新过程" -ForegroundColor Yellow
                    break
                }
            } else {
                Write-Host "跳过错误并继续处理其他应用..." -ForegroundColor Yellow
            }
        }
    }

    # 显示更新摘要
    Write-Host "`n" -NoNewline
    Write-Host ("-" * 50) -ForegroundColor Cyan
    Write-Host "📊 更新摘要" -ForegroundColor Cyan
    Write-Host "✅ 成功: $successCount" -ForegroundColor Green
    if ($failCount -gt 0) {
        Write-Host "❌ 失败: $failCount" -ForegroundColor Red
        Write-Host "失败的应用: $($failedApps -join ', ')" -ForegroundColor Yellow

        if (-not $quiet) {
            Write-Host "`n💡 提示：您可以使用以下命令重试失败的应用：" -ForegroundColor Cyan
            foreach ($failedApp in $failedApps) {
                Write-Host "  scoop update $failedApp" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "🎉 所有应用更新成功!" -ForegroundColor Green
    }
    Write-Host ("-" * 50) -ForegroundColor Cyan
}

exit 0
