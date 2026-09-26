# mycopr

自用的 Fedora COPR 打包仓库：按 **COPR SCM + `make srpm`** 的方式组织，一个包一个目录，
spec 和下载清单入库，源码/产物不入库。

| 包 | 版本 | 上游 | 打包形式 |
| --- | --- | --- | --- |
| `zed` | 1.21.0 | [zed-industries/zed](https://github.com/zed-industries/zed) | 重打包官方预编译 tarball |

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

COPR 每次构建会：调用 `.copr/Makefile` → `scripts/make-srpm.sh` →
`scripts/fetch-sources.sh` 按 `zed/sources` 下载并校验 sha256 → `rpmbuild -bs` → 构建 RPM。

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
- 构建时 `%check` 会跑 `zed --version`（构建机是 root，所以要 `ZED_ALLOW_ROOT=true`）
  并检查自带 .so 是否都能加载。

## 已本地验证

在 `fedora:45` 容器里跑通过（x86_64）：

- `make srpm` → `rpmbuild --rebuild` 构建成功、无 warning（除了 changelog 日期导致的
  SOURCE_DATE_EPOCH 提示）；
- 安装后 `/usr/bin/zed --version` 正确解析到 `/usr/lib64/zed/libexec/zed-editor`，
  运行时确实加载的是私有目录里的 `libxcb.so.1` / `libstdc++.so.6`；
- `rpm -V`/卸载正常，`appstreamcli validate` 通过，`desktop-file-validate` 通过。
- aarch64 用同一个 spec（`Source0` 按 `%{_arch}` 拼），未实机验证。
