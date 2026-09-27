# mycopr

自用的 Fedora COPR 打包仓库：按 **COPR SCM + `make srpm`** 的方式组织，一个包一个目录，
spec 和下载清单入库，源码/产物不入库。

| 包 | 版本 | 上游 | 打包形式 |
| --- | --- | --- | --- |
| `zed` | 1.21.0 | [zed-industries/zed](https://github.com/zed-industries/zed) | 重打包官方预编译 tarball |
| `zen-browser` | 1.22.3b | [zen-browser/desktop](https://github.com/zen-browser/desktop) | 重打包官方预编译 tarball |

## 目录结构

```
.copr/Makefile            COPR SCM 的 "make srpm" 入口（全仓库共用）
scripts/
  fetch-sources.sh        按 <包>/sources 清单下载并校验源码
  make-srpm.sh            生成 SRPM（本地和 COPR 走同一份逻辑）
  build-local.sh          本地构建：--srpm / --podman / --mock
  new-package.sh          新包骨架
zed/
  zed.spec                RPM spec
  sources                 文件名 / 架构 / sha256 / URL 清单（update.sh 生成）
  update.sh               跟进上游新版本
zen/
  zen.spec                RPM spec（RPM 包名是 zen-browser，目录/spec 文件名保持短）
  zen.sh                  装成 /usr/bin/zen 的启动脚本（本仓库自己维护）
  policies.json           关掉内置更新（本仓库自己维护）
  sources / update.sh     同上
```

## 一次性准备

本机（想本地出包才需要）：

```bash
sudo dnf install rpm-build rpmdevtools          # 生成 SRPM 用
sudo dnf install mock rpmlint                   # 可选：mock 构建 / 静态检查
# podman 已装的话，--podman 方式不需要 root，也不用装上面这些
```

## 在 COPR 上配置

1. COPR → **New Project**，名字随意（下文假设 `mycopr`）。
2. Chroots 勾上 `fedora-43-x86_64`、`fedora-44-x86_64`、`fedora-45-x86_64` 和对应的
   `aarch64`（Zed 官方两种架构的产物都有，同一个 spec 直接出两个包）。
3. Packages → **New Package**，按下表填：

   | 字段 | 值 |
   | --- | --- |
   | Package name | `zed` |
   | Source type | `SCM` |
   | Clone URL | `https://github.com/<你的用户名>/mycopr.git` |
   | Committish | `master`（或你的默认分支） |
   | Subdirectory | `zed` |
   | Spec File | `zed.spec` |
   | SRPM 生成方式 | **`make srpm`** ← 别用默认的 rpkg，本仓库的校验和检查在 Makefile 里 |

4. 把仓库推上去，回到 COPR 点 **Rebuild**。

   再加一个包 `zen-browser`：同样 **New Package**，`Subdirectory` 填 `zen`、
   `Spec File` 填 `zen.spec`、SRPM 生成方式选 **`make srpm`**，勾同样的 chroots。

COPR 每次构建会：调用 `.copr/Makefile` → `scripts/make-srpm.sh` →
`scripts/fetch-sources.sh` 按 `zed/sources` 下载并校验 sha256 → `rpmbuild -bs` → 构建 RPM。

> ⚠ **一次 build 只生成一个 SRPM，所有 chroot 共用**（COPR 官方文档：
> "The SRPM is downloaded once per build, regardless of the number of chroots"）。
> 所以 spec 里的 `Source` 文件名/URL **不能按 `%{_arch}` 变**——否则 SRPM 只在某一个架构的
> srpm-build chroot 里生成，另一个架构去 `rpmbuild -bs` 时就会报
> `Bad file: .../xxx-<arch>.tar.gz: No such file or directory`。
> 架构相关的源码要两个都写进 `Source`（都标 `all`），构建时用 `%ifarch` 选：见 `zed/zed.spec`。

## 本地构建

```bash
./scripts/build-local.sh zed --srpm            # 只出 SRPM
./scripts/build-local.sh zed --podman          # 在 fedora:45 容器里整个构建（不需要 root，推荐）
./scripts/build-local.sh zed --mock            # 用 mock（需要 root）
./scripts/build-local.sh zed                   # 直接本机 rpmbuild（要先 dnf builddep）
./scripts/build-local.sh zed --lint            # 顺便跑 rpmlint
```

产物都在 `.build/` 下（SRPM、RPM、容器/mock 各一份），这些都不入库。

想快速试装刚打出来的包：

```bash
sudo dnf install ./.build/rpm/x86_64/zed-*.rpm
```

## 升级到上游新版本

```bash
cd zed
./update.sh --check         # 只看有没有新版，不改文件
./update.sh                 # 改 spec 的 Version、重写 sources 校验和、在 changelog 顶部插一条
cd ..
./scripts/build-local.sh zed --podman
git add -A && git commit -m "zed: update to x.y.z" && git push
```

`update.sh` 走 GitHub API，两个 120MB 的 tarball 用 API 给的 sha256 digest，
不会真的下载；只有那几个小文件（metainfo 模板、两个 LICENSE）会下载后自己算。

## 加新包

```bash
./scripts/new-package.sh nvim      # 建 nvim/{nvim.spec,sources} 骨架
# 填 spec 里的 TODO + 按 sources 文件头的格式写清单，然后：
./scripts/build-local.sh nvim --podman
```

COPR 那边再加一个 SCM 包，Subdirectory 填 `nvim`，其余照抄 zed 的配置。

## 让 COPR 自动重建（可选）

COPR 项目 → **Settings → Integrations** 复制 webhook URL，然后到 GitHub 仓库
**Settings → Webhooks → Add webhook**（Content type 选 `application/json`）。
之后 push 就会触发构建。

想跟着上游自动更新的话，再加一个定时跑 `zed/update.sh` 并提交的 GitHub Action 即可。

## 用户怎么装

```bash
sudo dnf copr enable <你的用户名>/mycopr
sudo dnf install zed
```

## zed 包的说明与坑

- **重打包二进制，不是源码构建。** 上游只发 `zed-linux-{x86_64,aarch64}.tar.gz`，
  从源码构建要 cargo vendor 源 + 几小时构建 + 大内存，COPR 上很折腾，所以这里直接重打包官方产物。
- **两个架构的 tarball 都在 SRPM 里。** COPR 一次 build 只生成一个 SRPM 给所有 chroot 用
  （见上文），所以 `Source0`/`Source1` 分别是 x86_64/aarch64 的包，`%prep` 里用 `%ifarch`
  选一个解包。SRPM 因此有 ~250MB，但只解一个，构建时间不受影响。
- **目录布局不能改。** 两个二进制（`bin/zed` CLI 和 `libexec/zed-editor` 编辑器）的 rpath 都是
  `$ORIGIN/../lib`，CLI 还会在「自己所在目录的 `../libexec`」里找编辑器实例
  （见上游 `crates/cli/src/main.rs`）。所以整棵 `zed.app` 树一起装在
  `/usr/lib64/zed/`，`/usr/bin/zed` 只是指向它的相对软链。
- **自带的 .so**（libstdc++、libxcb、libxkbcommon…）放在 `/usr/lib64/zed/lib` 私有目录，
  不会被别的程序加载，也不参与依赖生成（spec 里用 `__provides_exclude_from` /
  `__requires_exclude_from` 排掉），否则本包会凭空 `Provides: libstdc++.so.6`，误导依赖解析。
  系统侧的 glib2、alsa-lib、libxcb 等按 rpm 自动依赖正常装上。
- **glibc 要求 ≥ 2.30**（上游 Ubuntu 20.04 工具链编的），F43/44/45 都满足。
- **不要用 `zed --uninstall` 来卸载。** 它只会删 `~/.local` 下的安装和
  `~/.local/share/zed` 的数据库，删不掉 RPM 的文件；用 `dnf remove zed`。
- 以前用官方 `install.sh` 装在 `~/.local` 的话，PATH 里 `/usr/bin` 通常优先，
  建议把旧的删掉免得两套混用。
- Desktop 文件、图标、AppStream 元数据都装了（软件中心里能看到 Zed），
  desktop 文件用 `desktop-file-validate` 校验过。
- 构建时 `%check` 会跑 `zed --version`（构建机是 root，所以要 `ZED_ALLOW_ROOT=true`）、
  检查自带 .so 是否都能加载，并确认装进去的确实是本架构的二进制（`ld-linux-x86-64` /
  `ld-linux-aarch64`），防止 Source 选错时静默打出跨架构的包。

## zen-browser 包的说明与坑

- **同样是重打包官方预编译产物**（`zen.linux-{x86_64,aarch64}.tar.xz`），装在
  `/usr/lib64/zen`，`/usr/bin/zen` 是本仓库自己维护的转发脚本
  （`exec /usr/lib64/zen/zen "$@"`；AUR 的原生包也是这么做的，不加 flatpak 那个 `--name`）。
  启动器是 ELF，靠 `/proc/self/exe` 判断自己所在目录，再在同目录里按 `dependentlibs.list`
  加载 `libxul.so`、`libnss3.so` 等，所以整棵树不能拆。
- **依赖过滤要分两半**（这点和 zed 不同，因为自带 .so 和二进制在同一层目录）：
  provides 用 `__provides_exclude_from` 排除整个应用目录，免得本包声称提供
  `libnss3.so` / `libnspr4.so` 这类系统库的 soname；requires 只能用 `__requires_exclude`
  按「自带 .so 的文件名」过滤（构建时现场算 soname 列表），这样 libxul 依赖的
  gtk3 / dbus / X11 还是会被正确记下来。写法照搬 Fedora 官方 `firefox.spec`。
- 上游的 `libonnxruntime.so` 带了个字面量 `$` 的 RUNPATH（大概是构建时 `$ORIGIN` 被 shell 吃了），
  `check-rpaths` 会判它非法，所以 spec 里写了 `__brp_check_rpaths` 置空跳过这个检查。
- **desktop 文件 / AppStream 元数据 / 矢量图标取自 [zen-browser/flatpak]** 同 tag 的文件
  （官方 native 包没有自己的桌面文件），只把 `Exec=launch-script.sh` 换成 `Exec=zen`，
  上游那 400 多条翻译都保留；16~128 的位图用 tarball 自带的 Zen 图标，名字统一成
  desktop 文件的 `Icon=app.zen_browser.zen`，所以图标名看着有点怪但是自洽的。
- 内置更新用 `distribution/policies.json` 里的 `DisableAppUpdate` 关了（装在 `/usr/lib64` 下
  普通用户也写不进去），升级走 dnf。
- `dictionaries` / `hyphenation` 软链到系统的 `/usr/share/hunspell`、`/usr/share/hyphen`，
  系统装的拼写词典就能用上（上游 tarball 不带词典）。
- `%check` 会真的把浏览器跑一次（`zen --version`），所以 BuildRequires 里带了 gtk3、alsa-lib、
  libX11-xcb。注意 Fedora 构建 root 关掉了 weak deps，libX11-xcb 不会被 gtk3 拖进来，
  必须显式写（第一次提交就栽在这里：chroot 里缺它，冒烟测试起不来）。
- 版本号形如 `1.22.3b`（Zen 的 stable 通道就带这个 b 后缀），rpm 会比较成「比 1.22.3 新」，
  update.sh 直接拿 release 的 tag 当版本号（它没有 `v` 前缀）。
- tarball 里带一套自己的 NSS/NSPR，我们没有换成系统的（AUR 会 symlink 系统的
  `libnssckbi.so`，那有 ABI 风险），所以 Zen 用的是自带的 CA 库。
- `zen` 和 `zen-bin` 在这个版本里是同一份二进制，两个都保留（上游就是这么发的）。
- 装完约 400MB（浏览器）。`twilight` 通道不是 release tag 的形式，没做。

[zen-browser/flatpak]: https://github.com/zen-browser/flatpak

## 已本地验证

在 `fedora:45` 容器里跑通过（x86_64）：

`zed`：

- `make srpm` → `rpmbuild --rebuild` 构建成功、无 warning（除了 changelog 日期导致的
  SOURCE_DATE_EPOCH 提示）；
- 安装后 `/usr/bin/zed --version` 正确解析到 `/usr/lib64/zed/libexec/zed-editor`，
  运行时确实加载的是私有目录里的 `libxcb.so.1` / `libstdc++.so.6`；
- `rpm -V`/卸载正常，`appstreamcli validate` 通过，`desktop-file-validate` 通过。

`zen-browser`：

- 同一个流程构建成功、无 warning；装完（约 400MB）`/usr/bin/zen --version` 输出
  `Mozilla Zen 1.22.3b`；
- 自动依赖里能看到 `libgtk-3.so.0` / `libdbus-1.so.3` / `libasound.so.2` / `xdg-desktop-portal`，
  而 `Provides` 里没有 `libnss3` / `libnspr4` / `libxul`（自带库过滤生效）；
- desktop 文件（含 5 个 action）的 Exec 全换成了 `zen`，444 条上游翻译还在；
  图标（16~128 + scalable SVG）、元数据、`policies.json`、词典软链都在位，卸载正常；
- 两个包都是 aarch64 走同一个 spec（两个架构的 tarball 都在 SRPM 里，用 `ifarch` 选），
  未实机验证。
