# ---------------------------------------------------------------------------
# zed —— 重打包上游官方预编译产物（stable 通道）
#
# 为什么重打包：上游只提供 x86_64/aarch64 的 .tar.gz，从源码构建要 cargo vendor
# 源、数小时构建和大内存（见 https://zed.dev/docs/development/linux）。
#
# 目录布局必须保持和上游 zed.app 一致（x86_64/aarch64 上 /usr/lib64/zed）：
#   /usr/lib64/zed/bin/zed              CLI，rpath = $ORIGIN/../lib
#   /usr/lib64/zed/libexec/zed-editor   编辑器本体，rpath = $ORIGIN/../lib
#   /usr/lib64/zed/lib/*.so*            上游自带的 .so（libstdc++、libxcb、libxkbcommon…）
# CLI 会在「自己所在目录的 ../libexec」里找 zed-editor（crates/cli/src/main.rs），
# 两个二进制又用 $ORIGIN 相对路径找自己的 .so，所以整棵树必须一起装、不能拆。
#
# 注意：COPR 一次构建只生成、只使用一个 SRPM，所有 chroot 共用它（官方文档：
# "The SRPM is downloaded once per build, regardless of the number of chroots"）。
# 所以 Source 的文件名/URL 不能跟着构建架构变 —— 那个 SRPM 只会在某一个架构的
# srpm-build chroot 里生成，另一个架构去建 SRPM 时就找不到自己的包，报
# "Bad file: .../zed-linux-xxx.tar.gz: No such file or directory"。
# 正确做法是两个架构都放进 SRPM，构建时用 ifarch 选一个解包。
# ---------------------------------------------------------------------------

%global app_id      dev.zed.Zed
%global upstream_gh zed-industries/zed

# 重打包二进制：不打 debuginfo，也不重新 strip，保持和上游产物一致
%global debug_package %{nil}
%global __strip /bin/true

# 私有目录里是上游自带的库，不参与依赖生成
# （否则本包会凭空 Provides: libstdc++.so.6()(64bit) 之类，误导其他包的依赖解析）
%global __provides_exclude_from ^%{_libdir}/zed/lib/.*$
%global __requires_exclude_from ^%{_libdir}/zed/lib/.*$

Name:           zed
Version:        1.21.0
Release:        1%{?dist}
Summary:        High-performance, multiplayer code editor
# 上游 README：primarily GPL-3.0-or-later, with Apache-2.0 components where marked
License:        GPL-3.0-or-later AND Apache-2.0
URL:            https://zed.dev

Source0:        https://github.com/%{upstream_gh}/releases/download/v%{version}/zed-linux-x86_64.tar.gz
Source1:        https://github.com/%{upstream_gh}/releases/download/v%{version}/zed-linux-aarch64.tar.gz
Source2:        https://raw.githubusercontent.com/%{upstream_gh}/v%{version}/crates/zed/resources/flatpak/zed.metainfo.xml.in
Source3:        https://raw.githubusercontent.com/%{upstream_gh}/v%{version}/LICENSE-APACHE
Source4:        https://raw.githubusercontent.com/%{upstream_gh}/v%{version}/LICENSE-GPL

# 真正要解包的那个（两个 tarball 都在 SRPM 里，见文件头说明）
%ifarch x86_64
%global zed_tarball zed-linux-x86_64.tar.gz
%else
%global zed_tarball zed-linux-aarch64.tar.gz
%endif

BuildRequires:  desktop-file-utils
BuildRequires:  gettext-envsubst

ExclusiveArch:  x86_64 aarch64

Requires:       hicolor-icon-theme

%description
Zed 是 Atom / Tree-sitter 作者做的多人协作代码编辑器：Rust + GPU 渲染，
启动快、输入延迟低，内置 LSP、AI 助手和实时协作。

本包重打包上游官方 stable 预编译产物（并非从源码构建）。上游自带的
libstdc++、libxcb、libxkbcommon 等库放在 %{_libdir}/zed/lib 私有目录里，
不会被其它程序加载。请用 dnf 升级，不要用 Zed 自己的更新/卸载手段。

%prep
# 不用 setup 宏：tarball 直接解到构建目录（也就是这里），里面直接就是 zed.app/，
# 省得纠结 -c/-n/-T 和 buildsubdir 的差异（rpm 6 的 setup 行为和文档写的不太一样）。
# 坑：spec 注释里的宏也会被展开，所以注释里千万别出现宏写法（否则会被静默替换成
# 一段脚本）——踩过一次，表现是构建时莫名报 "cd zed-1.21.0: No such file or directory"。
# 两个架构的包都在 SRPM 里，这里只解当前架构那一个。
rm -rf zed.app
tar -xf %{_sourcedir}/%{zed_tarball}

%build
# 纯重打包，没有编译步骤

%install
install -d %{buildroot}%{_libdir}
cp -a zed.app %{buildroot}%{_libdir}/zed

install -d %{buildroot}%{_bindir}
# 用相对软链（Fedora 不欢迎 /usr 里的绝对软链）；/proc/self/exe 会解析到真实路径，
# CLI 仍然能在自己所在目录的 ../libexec 里找到 zed-editor
(cd %{buildroot}%{_bindir} && ln -s \
    "$(realpath --relative-to=%{buildroot}%{_bindir} %{buildroot}%{_libdir}/zed/bin/zed)" zed)

install -d %{buildroot}%{_datadir}/applications
install -pm 0644 zed.app/share/applications/%{app_id}.desktop \
    %{buildroot}%{_datadir}/applications/
# 私有目录里那份 desktop 只是上游附带的，去掉可执行位（否则 brp 会告警）
chmod 0644 %{buildroot}%{_libdir}/zed/share/applications/%{app_id}.desktop

for size in 512x512 1024x1024; do
    install -Dpm 0644 zed.app/share/icons/hicolor/$size/apps/zed.png \
        %{buildroot}%{_datadir}/icons/hicolor/$size/apps/zed.png
done

# AppStream 元数据：上游模板里的 $VAR 由 flatpak 打包脚本填充，这里填同样的值，
# @release_info@ 换成当前版本（顺便丢掉上游那句 0.0.0 的占位 release）
export APP_ID=%{app_id} APP_NAME=Zed BRANDING_LIGHT='#99c1f1' BRANDING_DARK='#1a5fb4'
envsubst '$APP_ID $APP_NAME $BRANDING_LIGHT $BRANDING_DARK' \
    < %{_sourcedir}/zed.metainfo.xml.in > %{app_id}.metainfo.xml
release_date=$(date -u +%%F)
sed -i -e "s|@release_info@|<release version=\"%{version}\" date=\"$release_date\"/>|" \
       -e '/<release version="0.0.0"/,/<\/release>/d' \
    %{app_id}.metainfo.xml
install -Dpm 0644 %{app_id}.metainfo.xml %{buildroot}%{_datadir}/metainfo/%{app_id}.metainfo.xml

install -Dpm 0644 %{_sourcedir}/LICENSE-APACHE \
    %{buildroot}%{_datadir}/licenses/%{name}/LICENSE-APACHE
install -Dpm 0644 %{_sourcedir}/LICENSE-GPL \
    %{buildroot}%{_datadir}/licenses/%{name}/LICENSE-GPL

%check
# CLI 跑一下 --version 当冒烟测试（不会起 GUI）。构建机/COPR 里是 root，要显式放行，
# 同时把 HOME 指到临时目录，免得往 root 家目录写东西。
export HOME=$(mktemp -d) ZED_ALLOW_ROOT=true
%{buildroot}%{_libdir}/zed/bin/zed --version

# 自带 .so 必须都能加载。系统库（glib2、alsa-lib 之类）构建环境里不一定装了，
# 那些交给 RPM 自动生成的依赖，不在这里判。
ldd_out=$(ldd %{buildroot}%{_libdir}/zed/libexec/zed-editor 2>/dev/null)
test -n "$ldd_out"

# 防呆：确认装进去的确实是本架构的二进制（万一 Source 选错了，这里会炸）
%ifarch x86_64
echo "$ldd_out" | grep -q 'ld-linux-x86-64'
%else
echo "$ldd_out" | grep -q 'ld-linux-aarch64'
%endif

missing=$(echo "$ldd_out" | awk '/not found/ {print $1}')
for so in %{buildroot}%{_libdir}/zed/lib/*.so*; do
    so=$(basename "$so")
    case " $missing " in
        *" $so "*) echo "错误: 自带库 $so 找不到"; exit 1 ;;
    esac
done

desktop-file-validate %{buildroot}%{_datadir}/applications/%{app_id}.desktop

%files
%license %{_datadir}/licenses/%{name}/LICENSE-APACHE
%license %{_datadir}/licenses/%{name}/LICENSE-GPL
# 上游生成的第三方许可清单（放在私有目录里，顺手标成 license）
%license %{_libdir}/zed/licenses.md
%{_bindir}/zed
# 下面几行刻意写细：上游要是改了 zed.app 里的目录结构，构建会直接报未打包文件
%dir %{_libdir}/zed
%{_libdir}/zed/bin/
%{_libdir}/zed/lib/
%{_libdir}/zed/libexec/
%{_libdir}/zed/share/
%{_datadir}/applications/%{app_id}.desktop
%{_datadir}/icons/hicolor/*/apps/zed.png
%{_datadir}/metainfo/%{app_id}.metainfo.xml

%changelog
* Sun Sep 27 2026 Yadomin <i@yadom.in> - 1.21.0-1
- 首个版本：重打包上游 stable 预编译产物（zed-linux-{x86_64,aarch64}.tar.gz）
