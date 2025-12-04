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

## 小技巧

### 开启缓存

为加速 `search` 查询功能，可执行以下命令开启缓存：

```powershell
scoop config use_sqlite_cache $True
```

### 关于遇到 “运行中的进程阻止更新” 的错误

如果在 `reset/uninstall/update` 应用时遇到 “运行中的进程阻止更新” 的错误，可以设置 `ignore_running_processes` 配置项来忽略这些进程：

```powershell
scoop config ignore_running_processes $true
```

这会让 Scoop 在`reset/uninstall/update`时忽略正在运行的进程。***请注意，这可能会导致数据丢失或应用不稳定，建议在设置前确保相关应用已关闭。***

### 关于文件编码

由于历史遗留问题 Win 10/11 自带的 Windows PowerShell 5.1 仅支持编码格式为 **UTF-16 LE with BOM** 的**包含中文字符**的脚本文件(.ps1)和注册表文件(.reg)等正确显示和执行。

如果你需要修改或创建包含中文的脚本、注册表文件等，请确保使用支持该编码的编辑器（如 VS Code、Notepad++ 等）并正确设置编码格式。

## 扩展

### 增强命令

本仓库新增了三个增强命令：`resetx`、`updatex` 和 `cleanupx`，它们分别解决了原生命令在某些场景下的不足。

#### 安装方法

将以下脚本文件复制到 `$env:SCOOP\shims\` 目录即可安装这三个增强命令：
> 规避直接安装到 `$env:SCOOP\apps\scoop\current\libexec\` 目录，导致无法更新 Scoop 自身。

```powershell
Copy-Item "$env:SCOOP\buckets\scoop-private\Scripts\scoop-*.ps1" "$env:SCOOP\shims\"
```

> [!TIP]
> 如果遇到运行权限问题，可使用以下命令解锁:
>
> ```powershell
> Unblock-File -Path 'xxx.ps1'
> ```

### resetx 命令

解决了原始`scoop reset`不会执行`Manifest`文件中`post_install`节进行本地化设置的问题。
> 关于`post_install`节：一般可能涉及一些本地化设置，例如对右键菜单中路径进行调整。

```powershell
scoop resetx <app>
```

### updatex 命令

解决了原始`scoop update`在更新多个应用时，单个应用更新失败会导致整个更新过程中断的问题。

```powershell
scoop updatex [<app>...]
```

### cleanupx 命令

解决了原始`scoop cleanup`在清理多个应用时，单个应用清理失败会导致整个清理过程中断的问题。

```powershell
scoop cleanupx [<app>...]
```

## 参考
- [Scoop Wiki - Buckets](https://github.com/ScoopInstaller/scoop/wiki/Buckets)
- [Scoop Wiki - App Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
- [Scoop Wiki - Autoupdate](https://github.com/ScoopInstaller/scoop/wiki/App-Manifest-Autoupdate)
- [Contributing Guide](https://github.com/ScoopInstaller/.github/blob/main/.github/CONTRIBUTING.md)
