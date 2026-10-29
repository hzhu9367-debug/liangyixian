# 桌面晾衣杆

基于 [Alejandro Buján 的 Tendedero](https://github.com/alejandrobujan/tendedero) 修改的 macOS 桌面截图与文字便签工具，另附独立 Windows 测试版源码。本仓库公开提供源码，无需登录 GitHub 即可浏览或下载；以下原版介绍保留作来源参考，不代表本定制版的全部行为。

## 当前定制功能

- 截图与文字便签单排悬挂，自动缩放，悬停放大。
- 原图造型便签、文字自动换行、小锤子新建便签和显示模式选择。截图与便签使用原来的显示大小，数量多时自动缩小，始终保持单排。
- 小锤子与显示模式按钮随晾衣绳一起收起；顶部悬停唤出后即可使用，也可从菜单栏操作。
- 便签工坊：导入自己的底图，调整文字区域、夹子位置、悬挂角度和文字样式。
- 沿晾衣线拖动调整顺序，自动保存，支持撤销；拖到其他应用仍可复制。
- 图片直接拖入、待上绳队列和撤销；便签及截图不再提供图钉锁定。
- 点击右上角叉号仅从晾衣线移除，截图仍保留在截图文件夹（拖入图片保留在原位置），便签原文件也保留；支持撤销，不再显示“最近收起”。只有明确选择“移到废纸篓”才删除文件。
- 点击小图钉选择“始终显示”或“顶部悬停显示”，模式会记住；`Option + Shift + A` 快速切换两种模式，`Option + Shift + N` 新建文字便签。

仓库仅包含源码、构建脚本和界面素材，不包含个人截图、便签文字、登录凭据或编译产物。

## 自定义便签

点击晾衣线左侧的小锤子，在新建文字便签窗口中打开“便签工坊”；也可以从应用菜单直接打开。

文字编辑框支持 `Command + V`、右键“粘贴”和“编辑”菜单粘贴，复制来的文字会以纯文本插入，保留换行。Mac 1.1.12 补齐编辑菜单与快捷键处理；在便签或工坊窗口编辑时，`Command + Z` 撤销输入。

导入 PNG、JPG/JPEG、WebP、GIF、HEIC/HEIF、TIFF、BMP 等本机可读取的图片（最大 20 MB、6000 万像素）。文件选择器和实际读取使用同一份系统支持格式列表，额外格式取决于 macOS 版本。动图和多页图片取第一张作为静态底图。推荐透明背景 PNG，长边至少 600 像素；大图会自动缩小到最长边 2048 像素，透明背景会保留。

拖动文字区域移动位置，拖动右下角调整大小；切到“夹子位置”后，点击或拖动底图设置夹子。设置名称、颜色、字号、对齐和角度后保存，即可在新建便签的外形列表中选择。已有样式可以从左侧列表再次编辑；移除样式不会改变已经挂上的便签。

调整悬挂角度会自动切到“悬挂预览”，使用与晾衣线一致的夹点和旋转方式，完整展示图片与夹子；编辑文字或夹点时可切回对应模式。

样式和底图只保存在本机的 `~/Library/Application Support/Tendedero/Styles`，无需登录，不会上传。

Mac 1.1.2 修复了工坊上传及编辑卡顿：工坊和文字编辑使用非阻塞窗口，图片在后台读取，预览缓存并限制刷新频率。读取失败会保留原底图；关闭工坊后，原便签文字仍然保留。

## 本仓库构建

```sh
git clone https://github.com/hzhu9367-debug/liangyixian.git
cd liangyixian
scripts/build-app.sh
open "build/桌面晾衣杆.app"
```

需要 macOS 14 或以上及 Swift 工具链。

### Windows 测试版

新增独立 Electron 移植版，目标为 Windows 10/11 x64。安装包无需 GitHub 登录或开发工具；使用方式、构建命令和当前限制见 [Windows 使用说明](windows/README.md)。与 Mac 版的数据不自动同步，尚未完成真实 Windows 机器上的安装、截图和全屏验证，请按测试版使用。

## 来源与素材许可

原作者版权与 MIT 源码许可保留在 [LICENSE](LICENSE)。原项目名称、图标及文档图片不包含在 MIT 源码授权中；公开发布修改版前，须依原作者要求更换应用名称和图标。新增便签参考素材仅作个人使用，公开分发前应确认相应图片权利。

---

## 原项目说明

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/hero-dark.png">
  <img src="docs/hero-light.png" alt="Tendedero. Screenshots, hung out to dry. Three screenshots in glass frames hang from a thin line under the macOS menu bar.">
</picture>

<p align="center">
  Free and open source. For macOS 14 and later.
  <br>
  <a href="../../releases/latest">Download&nbsp;&rsaquo;</a>
  &nbsp;&nbsp;
  <a href="#build-from-source">Build from source&nbsp;&rsaquo;</a>
</p>

<br>

## Out of sight. Within reach.

Every screenshot you take hangs on a line just above your screen.
Rest the pointer in the menu bar and it glides down. Move away and it's gone.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/demo-dark.gif">
  <img src="docs/demo-light.gif" alt="The pointer rests against the top edge, the line slides down with three screenshots swinging gently, a click copies one, and the line tucks away when the pointer leaves.">
</picture>

<br>
<br>

## A gesture for everything.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/bento-dark.png">
  <img src="docs/bento-light.png" alt="Click to copy. Hold to mark up. Drag to share. Let it go.">
</picture>

<br>
<br>

| | |
|:--|:--|
| Click | Copy the image. |
| Press and hold | Open it in Markup. |
| Double click | Open it in Preview. |
| Drag into an app | Send a copy. It stays on the line. |
| Drag into a folder | Keep it there. It leaves the line. |
| Click × at the top right | Remove from the line while keeping its file. |
| Choose Move to Trash | Delete the file explicitly. |
| Rest the pointer in the menu bar | Bring the line down on that screen. |
| Click anything in the menu bar | Put it away. |
| <kbd>⌥</kbd>&thinsp;<kbd>⇧</kbd>&thinsp;<kbd>A</kbd> | Show or hide the line. |
| <kbd>⌥</kbd>&thinsp;<kbd>⇧</kbd>&thinsp;<kbd>N</kbd> | Create a text note. |
| <kbd>⌘</kbd>&thinsp;<kbd>Z</kbd> | Undo a take-down, deletion or replacement. |

<br>

## Your Desktop. Finally clear.

Hand Tendedero your screenshots<sup>1</sup> and they skip the Desktop
entirely. No floating thumbnail. No five-second wait. Each capture hangs
the instant you take it, and only what you drag out is kept.

Same shortcuts. Same muscle memory. Just less mess.

<br>

## Private by design.

No account. No network. No analytics.
Tendedero runs entirely on your Mac, and your screenshots never leave it.

<br>

## Tech Specs

| | |
|:--|:--|
| **Compatibility** | macOS 14 Sonoma or later, on Apple silicon and Intel. Designed for macOS 27. |
| **Size** | 1.7 MB |
| **Languages** | English, Spanish |
| **Built with** | Swift, AppKit and SwiftUI |
| **Network access** | None |
| **Price** | Free |
| **License** | MIT for the code. The name and icon are not included. |

<br>

## Install

Download the disk image from the [latest release](../../releases/latest),
open it and drag Tendedero to Applications.

Tendedero is not notarized by Apple yet, so the first time macOS will say it
cannot verify it. Open System Settings, go to Privacy & Security, and click
Open Anyway next to the message about Tendedero. You only need to do this once.

<br>

## Build from source

```sh
git clone git@github.com:alejandrobujan/tendedero.git
cd tendedero
scripts/build-app.sh
open build/Tendedero.app
```

Requires the Swift toolchain. Xcode is optional. With the Command Line Tools for macOS 27, the script falls back to the macOS 26 SDK they install alongside, because the new SDK needs a SwiftUI macro plugin only Xcode includes. Local builds are signed ad hoc,
so macOS asks again for access to the Desktop after each rebuild.

<details>
<summary>Inside the app</summary>
<br>

| File | Role |
|:--|:--|
| `AppDelegate.swift` | Menu bar, shortcut, revealing and tucking away the line |
| `LinePanel.swift` | The transparent strip along the top of the screen |
| `LineView.swift` | The line and where each photo hangs |
| `PeggedView.swift` | One photo: glass frame, clip, swing and breeze |
| `GrabArea.swift` | Click, long press, drag and drop |
| `ScreenshotWatcher.swift` | Notices new screenshots |
| `Inbox.swift` | Takes over screenshot settings and puts them back |
| `Markup.swift` | Opens the system Markup editor and saves the result |
| `FullScreen.swift` | Knows when to stay hidden |
| `Line.swift` | What is hanging, and what you can do with it |

Every image here, the icon included, is drawn in code by
`scripts/make-icon.swift` and `scripts/make-readme-art.swift`.
`scripts/make-dmg.sh` builds the disk image for releases.

</details>

<br>

---

<sub>
1. On first launch, Tendedero offers to handle your screenshots. If you accept, it turns off the floating thumbnail and saves new screenshots to its own folder, two settings also found under Options in Cmd+Shift+5. Your previous settings are saved and restored when Tendedero quits or the option is turned off from the menu bar. Tendedero hides automatically while an app is in full screen.
</sub>

<br>
<br>

<p align="center">
  <img src="docs/icon.png" width="64" height="64" alt="">
  <br>
  <sub>The code is MIT licensed. The Tendedero name and icon are not, so forks need their own. See <a href="LICENSE">LICENSE</a>.</sub>
  <br>
  <sub>Designed and built by <a href="https://alejandrobujan.com">Alejandro Buján</a>.</sub>
</p>
