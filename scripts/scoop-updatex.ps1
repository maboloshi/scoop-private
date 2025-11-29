# 用法：scoop updatex <app> [选项]
# Summary: 🚀 增强的 Scoop 更新命令，更新应用程序或 Scoop 自身
# Help: 'scoop updatex' 将 Scoop 更新至最新版本
# 'scoop updatex <app>' 将安装该应用的新版本（如果存在）
#
# 参数:
#  [app...]         要更新的特定应用列表，不指定则更新所有应用
#  *                更新所有应用（与 -All 相同）
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

# 检查SCOOP环境变量
if (-not $env:SCOOP) {
    Write-Error "环境变量 SCOOP 未设置，请确保 Scoop 已正确安装。"
    exit 1
}

# 只导入必要的核心库
. "$env:SCOOP\apps\scoop\current\lib\getopt.ps1"
. "$env:SCOOP\apps\scoop\current\lib\core.ps1"
. "$env:SCOOP\apps\scoop\current\lib\buckets.ps1"
. "$env:SCOOP\apps\scoop\current\lib\manifest.ps1"
. "$env:SCOOP\apps\scoop\current\lib\versions.ps1"

# 设置 scoop-update.ps1 路径
$scoop_update_path = "$env:SCOOP\apps\scoop\current\libexec\scoop-update.ps1"

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

# === 精简的主逻辑 ===

if (-not ($apps -or $all)) {
    # 没有指定应用，直接调用原脚本更新 Scoop 自身和 buckets
    & "$scoop_update_path"
    exit $LASTEXITCODE
} else {
    if ($global -and !(is_admin)) {
        '错误：您需要管理员权限才能更新全局应用程序。'; exit 1
    }

    # 检查是否需要更新 Scoop 自身
    $updateScoop = $null -ne ($apps | Where-Object { $_ -eq 'scoop' }) -or (is_scoop_outdated)
    if ($updateScoop) {
        # 更新 Scoop 自身和 buckets
        & "$scoop_update_path"
    }

    # 构建应用列表
    $apps_param = $apps | Where-Object { $_ -ne 'scoop' }

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

    # 过滤出需要更新的应用
    $outdated = @()
    $apps | ForEach-Object {
        ($app, $global) = $_
        $status = app_status $app $global
        if ($status.installed -and ($force -or $status.outdated)) {
            if (!$status.hold) {
                # 使用 applist 构建结构化的应用对数组
                $outdated += applist $app $global
                Write-Host -f yellow ("$app`: $($status.version) -> $($status.latest_version){0}" -f ('', ' (global)')[$global])
            } else {
                warn "'$app' 被锁定在 $($status.version) 版本"
            }
        }
    }

    if ($outdated.Count -eq 0) {
        Write-Host -f Green "所有应用的最新版本均已安装！如需更多信息，请尝试运行 'scoop status' 命令"
        exit 0
    } else {
        Write-Host -f DarkCyan "发现 $($outdated.Count) 个应用需要更新"
    }

    # === 增强部分：逐个更新应用并处理错误 ===
    $successCount = 0
    $skipCount = 0
    $failCount = 0
    $failedApps = @()
    $skippedApps = @()

    $outdated | ForEach-Object {
        $app = $_[0]
        $global = $_[1]

        # 获取应用状态以显示版本信息
        $status = app_status $app $global
        $old_version = $status.version

        # 构建 scoop update 命令参数
        $updateArgs = @($app)
        if ($global) { $updateArgs += '--global' }
        if ($force) { $updateArgs += '--force' }
        if ($independent) { $updateArgs += '--independent' }
        if (!$use_cache) { $updateArgs += '--no-cache' }
        if (!$check_hash) { $updateArgs += '--skip-hash-check' }
        if ($quiet) { $updateArgs += '--quiet' }

        try {
            # 调用原脚本进行更新
            & "$scoop_update_path" @updateArgs
            $exitCode = $LASTEXITCODE

            # 检查版本是否真的更新了
            $newStatus = app_status $app $global
            $isActuallyUpdated = $newStatus.version -ne $old_version

            if ($exitCode -eq 0 -and $isActuallyUpdated) {
                $script:successCount++
            } elseif ($exitCode -eq 0 -and -not $isActuallyUpdated) {
                $script:skipCount++
                $script:skippedApps += @{Name = $app; Reason = "版本未变化"}
            } else {
                throw "scoop update 返回代码: $exitCode"
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Host "❌ $app 更新失败: $errorMsg" -ForegroundColor Red

            $script:failCount++
            $script:failedApps += $app

            if (-not $script:skip_errors) {
                # 询问用户是否继续
                do {
                    $response = Read-Host "是否继续更新其他应用? (y/N)"
                    if ($response -eq '') { $response = 'N' }
                } while ($response -notmatch '^[yYnN]$')

                if ($response -notmatch '^[yY]$') {
                    Write-Host "⏹️ 用户中止更新过程" -ForegroundColor Yellow
                    # 使用 return 退出管道，但需要标记中止状态
                    $script:userAborted = $true
                    return
                }
            }
        }
    }

    # 显示更新摘要
    if (!$quiet) {
        Write-Host "`n" -NoNewline
        Write-Host ("-" * 50) -ForegroundColor Cyan
        Write-Host "📊 UpdateX 更新摘要" -ForegroundColor Cyan
        Write-Host "✅ 成功: $successCount" -ForegroundColor Green

        if ($skipCount -gt 0) {
            Write-Host "⏭️ 跳过: $skipCount" -ForegroundColor Yellow
            foreach ($skippedApp in $skippedApps) {
                Write-Host "   $($skippedApp.Name) - $($skippedApp.Reason)" -ForegroundColor Gray
            }
        }

        if ($failCount -gt 0) {
            Write-Host "❌ 失败: $failCount" -ForegroundColor Red
            Write-Host "失败的应用: $($failedApps -join ', ')" -ForegroundColor Yellow

            Write-Host "`n💡 提示: 可以使用以下命令重试失败的应用:" -ForegroundColor Cyan
            foreach ($failedApp in $failedApps) {
                Write-Host "  scoop update $failedApp" -ForegroundColor Gray
            }
        }

        if ($successCount -eq 0 -and $skipCount -eq 0 -and $failCount -eq 0) {
            Write-Host "ℹ️  没有需要更新的应用" -ForegroundColor Cyan
        } elseif ($failCount -eq 0 -and $skipCount -eq 0) {
            Write-Host "🎉 所有应用更新成功!" -ForegroundColor Green
        }

        Write-Host ("-" * 50) -ForegroundColor Cyan
    }

    # 返回适当的退出代码
    if ($failCount -gt 0) {
        exit $failCount
    } else {
        exit 0
    }
}

exit 0
