# Scoop-Private

一个私有 Scoop 软件库，用于存放官方未收录软件、自用汉化包、破解版软件等，不对外开放。<br>
破解版的二进制文件包以附件的形式存放在本项目 `Release v1.0` 下<br>

## 收录软件

### 常规版

| 软件                    | 简介                                                                                          |
| ----------------------- | --------------------------------------------------------------------------------------------- |
| clash-for-windows-cn      | 一个基于 Clash 的 Windows 图形用户界面 (集成[第三方汉化包](https://github.com/BoyceLig/Clash_Chinese_Patch))

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

## Manifest 书写规范

`bucket/` 与 `deprecated/` 下的 manifest 统一遵循以下规定。修改 manifest 后请执行：

```powershell
.\bin\format-manifests.ps1        # 一键修正
.\bin\format-manifests.ps1 -Check # 只检查不写入（CI 会跑）
```

### 文件

- JSON manifest：UTF-8 无 BOM、CRLF、4 空格缩进、文件末尾一个换行、无行尾空格。
- 含中文的 `.ps1`/`.psm1`/`.reg`：**UTF-16 LE with BOM**（见上文「关于文件编码」），同样使用 CRLF 与末尾换行。

### 顶层键顺序

```
##  version  description  homepage  license  notes  suggest  depends
architecture  url  hash  extract_dir  extract_to  innosetup
pre_install  installer  post_install
bin  shortcuts  env_add_path  env_set  persist
uninstaller  pre_uninstall  post_uninstall
checkver  autoupdate
```

未列出的键排在已知键之后，并保持原有相对顺序。

### 嵌套键顺序

| 对象 | 顺序 |
| --- | --- |
| `license` | `identifier`, `url` |
| `architecture.<arch>` | `url`, `hash`, `extract_dir`, `extract_to`, `pre_install`, `post_install`, `bin`, `shortcuts` |
| `autoupdate` | `architecture`, `url`, `extract_dir`, `hash` |
| `autoupdate.architecture.<arch>` | `url`, `hash`, `extract_dir`, `extract_to` |
| `installer` / `uninstaller` | `file`, `script`, `args` |
| `checkver` | `github`, `url`, `script`, `jsonpath`, `regex`, `replace`, `reverse`, `mode` |
| `hash`（对象形式） | `url`, `regex`, `jsonpath`, `mode`, `type` |
| `env_set` / `env_add_path` 等数据映射 | 保持原顺序，不排序 |

### `##` 注释

- 只能是第一个键，紧跟 `{`。
- 单条说明用字符串；多个来源用数组，首元素固定 `"_edited_from:"`，其后每行一个来源 URL。
- 注释文本允许中文，但不重写他人措辞。

### 值

- `license`：SPDX 标识或 `Freeware`/`Shareware`/`Proprietary`/`EULA`/`Unknown`，首字母大写；`identifier` 与 `url` 成对出现，只有一个键时用字符串形式。
- `hash`：sha256 不写算法前缀；`md5:`/`sha1:`/`sha512:` 必须写前缀。
- `checkver`：autoupdate 的下载地址是 GitHub Releases 时**不要**再写 `autoupdate.hash`，Scoop 会自动取 GitHub 的校验值（取不到时下载后本地计算）。
- `description`/`notes` 的语言与措辞保持原样。

### 内嵌脚本

- 使用 Scoop 内置 helper：`Expand-7zipArchive`、`Invoke-ExternalCommand`、`Get-HelperPath`、`ensure`、`New-DirectoryJunction`。
- `New-DirectoryJunction` 的第一个参数是**链接位置**，迁移块统一用 `$link`（应用真实数据目录）与 `$target`（`$persist_dir\...`）。
- 数据迁移块固定写法（与 Scoop 自己的 `persist_data` 策略一致：persist 为空就搬进来，persist 已有数据就把应用侧目录改名留档）：

  ```powershell
  # 数据迁移
  $link = "$env:LocalAppData\<app>\<dir>"
  $target = ensure "$persist_dir\<dir>"
  if (!(Get-Item $link -Force -ErrorAction SilentlyContinue).LinkType) {
      if ((Test-Path $link) -and (Get-ChildItem $target -Force -ErrorAction SilentlyContinue)) {
          Remove-Item -Path "$link.original" -Force -Recurse -ErrorAction SilentlyContinue
          Move-Item -Force $link "$link.original"
      } elseif (Test-Path $link) {
          Remove-Item -Path $target -Force -Recurse -ErrorAction SilentlyContinue
          Move-Item -Path $link -Destination $target -Force
      }
      New-DirectoryJunction $link $target | Out-Null
  }
  ```

  - `$link` 已经是软连接时整块跳过，所以重装/更新是幂等的。
  - `persist_data` 跑在 `post_install` 之前，`$target` 往往已被建成**空目录**，因此判断"有没有数据"要用 `Get-ChildItem`，不能只用 `Test-Path`。
  - `Move-Item` 前**必须**先删掉空的 `$target`：`Move-Item -Destination <已存在的目录>` 会把源目录整个搬进去变成 `$target\<目录名>`，而不是重命名。
  - `ensure` 放在 `$target` 赋值里，不能省：`New-Item -ItemType Junction` 指向不存在的目标会直接失败。
  - 对应的 `post_uninstall` 使用 `# 删除数据软连接` 标签并删除 `$link`。
- 注册表脚本注入块（`scripts\$app\*.reg` 复制到 `$dir` 并替换 `$install_dir`）固定写法，`reg import` 前加 `# 导入注册表`（字体用 `# 导入字体注册表`）：

  ```powershell
  $dir_escaped = "$dir".Replace('\', '\\')
  @('install-<名>.reg', 'uninstall-<名>.reg') | ForEach-Object {
      if (Test-Path "$bucketsdir\$bucket\scripts\$app\$_") {
          $content = Get-Content "$bucketsdir\$bucket\scripts\$app\$_" -Encoding Unicode
          $content = $content.Replace('$install_dir', $dir_escaped)
          if ($global) {
              $content = $content.Replace('HKEY_CURRENT_USER', 'HKEY_LOCAL_MACHINE')
          }
          Set-Content -Path "$dir\$_" $content -Encoding Unicode
      }
  }
  # 导入注册表
  reg import "$dir\install-<名>.reg"
  ```

- 直接写字体注册表时固定写法（`# 注册字体` / `# 注销字体`）：

  ```powershell
  $registryRoot = if ($global) { "HKLM" } else { "HKCU" }
  $registryKey = "${registryRoot}:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
  Get-ChildItem $dir -Filter '<字体文件通配符>' | ForEach-Object {
      New-ItemProperty -Path $registryKey -Name $_.Name.Replace($_.Extension, ' (TrueType)') -Value "$dir\$($_.Name)" -Force | Out-Null
  }
  ```

- 注册表相关变量固定命名：hive 用 `$registryRoot`，键路径用 `$registryKey`；不要再用 `$regpath`、`$rkey`、`$regKey` 等别名。
  - 不用 `$rKey` 这种缩写：PowerShell 变量名大小写不敏感，`$rKey` 与 `$rkey` 是同一个变量，混写只会增加误读。
- `Remove-Item` 一律显式写 `-Path`，参数顺序统一 `-Force -Recurse`，不使用 `-R` 别名；只有把管道结果当路径时（`... | Remove-Item -Force -Recurse`）才不写 `-Path`。
- 批量清理写在数组管道里：`@('a', 'b') | ForEach-Object { Remove-Item -Path "$dir\$_" -Force -ErrorAction SilentlyContinue }`。
- 运行外部程序一律用 `Invoke-ExternalCommand`，显式写 `-FilePath` 与 `-ArgumentList`；**不要**用 `Start-Process` 或 `New-Object System.Diagnostics.ProcessStartInfo`。

  ```powershell
  # 普通调用（等待结束、检查退出码）
  Invoke-ExternalCommand -FilePath "$dir\<exe>" -ArgumentList @('<参数>')
  # 需要 UAC 提权：-RunAs 等价于 -Verb RunAs（已经提权时不会再弹）
  Invoke-ExternalCommand -FilePath "$dir\<exe>" -ArgumentList @('<参数>') -RunAs
  # 需要隐藏窗口：-Quiet 等价于 -WindowStyle Hidden；两者都有时写成 -Quiet -RunAs
  Invoke-ExternalCommand -FilePath "$dir\<exe>" -ArgumentList @('<参数>') -Quiet -RunAs
  # 需要容忍特定退出码
  Invoke-ExternalCommand -FilePath "$dir\<exe>" -ContinueExitCodes @{ 3010 = '需要重启' }
  ```

  - `Invoke-ExternalCommand` 内部就是 `Process` + `WaitForExit` + 退出码检查，非零退出会报错并返回 `$false`，所以不需要自己拿 `-PassThru` 判退出码。
  - 要按成功/失败分支时写 `if (!(Invoke-ExternalCommand -FilePath "$dir\<exe>")) { break }`（hook 脚本里的 `break` 会终止整个脚本块）。
  - 提权与隐藏窗口必须保留：`-Verb RunAs` → `-RunAs`，`-WindowStyle Hidden` → `-Quiet`，原本不隐藏/不提权的不要擅自加上。
  - **`-FilePath` 直接写目标程序，不要拿 shell 当中间人**：`-FilePath powershell.exe -ArgumentList @('-Command', 'sc.exe delete X')` 要写成 `-FilePath sc.exe -ArgumentList @('delete', 'X')`。只有这两种情况才保留 `cmd`/`powershell`：
    1. 需要在**同一次提权**里连跑多条命令（拆成多次 `-RunAs` 会弹多次 UAC）。此时**用 `cmd` 而不是 `powershell`**：单次启动约 142ms vs 736ms。把命令与 `&` 作为**独立参数**传，别塞进一个字符串，Scoop 会自己给带空格的参数加引号：

       ```powershell
       Invoke-ExternalCommand -FilePath cmd.exe -ArgumentList @('/c', 'sc.exe', 'stop', $ServiceName, '&', 'sc.exe', 'delete', $ServiceName) -Quiet -RunAs
       ```
    2. 需要管道/重定向把输入喂给程序，例如 `cmd /c "echo y | tool.exe"`（`Invoke-ExternalCommand` 没有 stdin 重定向）。
  - 只有"在当前会话里执行 .ps1"才用 `&`（如 we-meet 注入的注册脚本），这不属于外部程序调用。
- 脚本内注释用 `#`（不用 `##`），不使用行尾空格做对齐。

## 参考
- [Scoop Wiki - Buckets](https://github.com/ScoopInstaller/scoop/wiki/Buckets)
- [Scoop Wiki - App Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
- [Scoop Wiki - Autoupdate](https://github.com/ScoopInstaller/scoop/wiki/App-Manifest-Autoupdate)
- [Contributing Guide](https://github.com/ScoopInstaller/.github/blob/main/.github/CONTRIBUTING.md)
