# Scoop-Private

一个私有 Scoop 软件库，用于存放官方未收录软件、自用汉化包、破解版软件等，不对外开放。<br>
破解版的二进制文件包以附件的形式存放在本项目 `Release v1.0` 下<br>

## 收录软件

### 常规版

| 软件                    | 简介                                                                                          |
| ----------------------- | --------------------------------------------------------------------------------------------- |
clash-for-windows-cn      | 一个基于 Clash 的 Windows 图形用户界面 (集成[第三方汉化包](https://github.com/BoyceLig/Clash_Chinese_Patch))

### 破解版文件来源和文件状态

程序名|版本号|二进制文件状态|来源
:---------------|:-------------:|:--:|:----------------------------------------------------------
XXX             | x.x.x         | ✔ | https://xxxx


## 安装和使用

确保你已经有 Scoop 环境，执行以下命令订阅本软件仓库：

```powershell
scoop bucket add scoop-private https://github.com/maboloshi/scoop-private
```

执行以下命令安装本仓库中的软件：

```powershell
scoop install scoop-private/<软件名>
```

## 扩展

### resetx 命令

本仓库新增了一个`resetx`命令。当重装系统后，若直接使用`reset`命令，会出现不会执行`Manifest`文件中`post_install`节进行本地化设置的情况。而`resetx`命令恰好能解决此问题，给用户操作带来便利。

> 关于`post_install`：它可能涉及一些本地化设置，例如对右键菜单中路径进行调整。

创建别名：

```powershell
scoop alias add resetx "$env:SCOOP\buckets\scoop-private\Scripts\scoop-resetx.ps1"
```

或安装到 Scoop：

```powershell
Copy-Item "$env:SCOOP\buckets\scoop-private\Scripts\scoop-resetx.ps1" "$env:SCOOP\apps\scoop\current\libexec\"
```

使用方法参考`reset`命令：

```powershell
scoop resetx <app>
```

> [!TIP]
> 如果遇到运行权限问题，可使用以下命令解锁
> ```powershell
> Unblock-File -Path 'xxx.ps1'
> ```

### updatex 命令

本仓库新增了一个`updatex`命令，解决了原始`scoop update`在更新多个应用时，单个应用更新失败会导致整个更新过程中断的问题。`updatex`命令提供增强的错误处理能力，确保单个应用的更新失败不会影响其他应用的更新。

主要特性：
- ✅ 基于原始 scoop update 逻辑，优先更新 Scoop 自身
- ✅ 单个应用更新失败不会中断整个更新过程
- ✅ 提供详细的更新摘要报告
- ✅ 支持交互式错误处理

> [!TIP]
> 如果在更新应用时遇到"运行中的进程阻止更新"的错误，可以设置 `ignore_running_processes` 配置项来忽略这些进程：
> ```powershell
> scoop config ignore_running_processes $true
> ```
> 这会让 Scoop 在更新时忽略正在运行的进程。请注意，这可能会导致数据丢失或应用不稳定，建议在设置前确保相关应用已关闭。

创建别名：

```powershell
scoop alias add updatex "$env:SCOOP\buckets\scoop-private\Scripts\scoop-updatex.ps1"
```

或安装到 Scoop：

```powershell
Copy-Item "$env:SCOOP\buckets\scoop-private\Scripts\scoop-updatex.ps1" "$env:SCOOP\apps\scoop\current\libexec\"
```

使用方法：

```powershell
# 基本用法
scoop updatex                        # 更新 Scoop 及 Buckets
scoop updatex git nodejs             # 只更新 git 和 nodejs

# 增强功能
scoop updatex -SkipErrors            # 遇到错误时跳过并继续更新
scoop updatex -SkipErrors -Force     # 强制更新所有应用，跳过错误

# 支持原始 update 命令的所有参数
scoop updatex -Global                # 更新全局安装的应用
scoop updatex * -NoCache             # 更新所有应用，不使用缓存
scoop updatex -All -SkipHashCheck    # 更新所有应用，跳过哈希验证
```

## 参考
- [Scoop Wiki - Buckets](https://github.com/ScoopInstaller/scoop/wiki/Buckets)
- [Scoop Wiki - App Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
- [Scoop Wiki - Autoupdate](https://github.com/ScoopInstaller/scoop/wiki/App-Manifest-Autoupdate)
- [Contributing Guide](https://github.com/ScoopInstaller/.github/blob/main/.github/CONTRIBUTING.md)
