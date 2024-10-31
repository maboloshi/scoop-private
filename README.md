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

本仓库新增了一个`resetx`命令。当重装系统后，若直接使用`reset`命令，会出现不会执行`Manifest`文件中`post_install`节进行本地化设置的情况。而`resetx`命令恰好能解决此问题，给用户操作带来便利。

> 关于`post_install`：它可能涉及一些本地化设置，例如对右键菜单中路径进行调整。

创建别名：

```powershell
scoop alias add resetx "$env:SCOOP\buckets\scoop-private\Scripts\scoop-resetx.ps1"
```

使用方法参考`reset`命令：

```powershell
scoop resetx <app>
```

## 参考
- [Scoop Wiki - Buckets](https://github.com/ScoopInstaller/scoop/wiki/Buckets)
- [Scoop Wiki - App Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
- [Scoop Wiki - Autoupdate](https://github.com/ScoopInstaller/scoop/wiki/App-Manifest-Autoupdate)
- [Contributing Guide](https://github.com/ScoopInstaller/.github/blob/main/.github/CONTRIBUTING.md)
