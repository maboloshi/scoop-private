# Usage: scoop resetx <app>
# Summary: 🚀 增强的 Scoop reset 命令，重置应用以解决冲突，并通过运行 post_install 来重置本地化设置
# Help: 用于解决特定应用程序之间的冲突，并通过运行 post_install 来重置本地化设置。
# 例如，若您同时安装了'python'和'python27'，可通过'scoop resetx'命令在两者之间切换使用。
#
# 您可以使用 '*' 替代 <app> 或 `-a`/`--all` 开关来重置所有应用。

# 检查SCOOP环境变量
if (-not $env:SCOOP) {
    abort "环境变量 SCOOP 未设置，请确保 Scoop 已正确安装。"
}

. "$env:SCOOP\apps\scoop\current\lib\getopt.ps1"
. "$env:SCOOP\apps\scoop\current\lib\manifest.ps1" # 'Select-CurrentVersion' (indirectly)
. "$env:SCOOP\apps\scoop\current\lib\system.ps1" # 'env_add_path' (indirectly)
. "$env:SCOOP\apps\scoop\current\lib\install.ps1"
. "$env:SCOOP\apps\scoop\current\lib\psmodules.ps1" # 'install_psmodule' (indirectly)
. "$env:SCOOP\apps\scoop\current\lib\versions.ps1" # 'Select-CurrentVersion'
. "$env:SCOOP\apps\scoop\current\lib\shortcuts.ps1"

$opt, $apps, $err = getopt $args 'a' 'all'
if($err) { "scoop reset: $err"; exit 1 }
$all = $opt.a -or $opt.all

if(!$apps -and !$all) { error '<app> missing'; my_usage; exit 1 }

if($apps -eq '*' -or $all) {
    $local = installed_apps $false | ForEach-Object { ,@($_, $false) }
    $global = installed_apps $true | ForEach-Object { ,@($_, $true) }
    $apps = @($local) + @($global)
}

$apps | ForEach-Object {
    ($app, $global) = $_

    $app, $bucket, $version = parse_app $app

    if(($global -eq $null) -and (installed $app $true)) {
        # set global flag when running reset command on specific app
        $global = $true
    }

    if($app -eq 'scoop') {
        # skip scoop
        return
    }

    if(!(installed $app)) {
        error "'$app' isn't installed"
        return
    }

    if ($null -eq $version) {
        $version = Select-CurrentVersion -AppName $app -Global:$global
    }

    $manifest = installed_manifest $app $version $global
    # if this is null we know the version they're resetting to
    # is not installed
    if ($manifest -eq $null) {
        error "'$app ($version)' isn't installed"
        return
    }

    if($global -and !(is_admin)) {
        warn "'$app' ($version) is a global app. You need admin rights to reset it. Skipping."
        return
    }

    write-host "Resetting $app ($version)."

    $dir = Convert-Path (versiondir $app $version $global)
    $original_dir = $dir
    $persist_dir = persistdir $app $global

    #region Workaround for #2952
    if (test_running_process $app $global) {
        return
    }
    #endregion Workaround for #2952

    $install = install_info $app $version $global
    $architecture = $install.architecture

    $dir = link_current $dir
    create_shims $manifest $dir $global $architecture
    create_startmenu_shortcuts $manifest $dir $global $architecture
    # uninstall_psmodule $manifest $refdir $global
    install_psmodule $manifest $dir $global
    # unset all potential old env before re-adding
    env_rm_path $manifest $dir $global $architecture
    env_rm $manifest $global $architecture
    env_add_path $manifest $dir $global $architecture
    env_set $manifest $global $architecture
    # unlink all potential old link before re-persisting
    unlink_persist_data $manifest $original_dir
    persist_data $manifest $original_dir $persist_dir
    persist_permission $manifest $global

    Invoke-HookScript -HookType 'post_install' -Manifest $manifest -ProcessorArchitecture $architecture

    success "'$app' ($version) was reseted successfully!"

    show_notes $manifest $dir $original_dir $persist_dir
}

exit 0
