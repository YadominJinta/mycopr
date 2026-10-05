# ---------------------------------------------------------------------------
# zen-browser —— 重打包 Zen Browser 官方预编译产物
#
# Zen 是 Firefox 的 fork，官方 Linux 只发 zen.linux-{x86_64,aarch64}.tar.xz
# （另有 .mar 增量包和 AppImage，都不适合做成系统包）。这里直接重打包 tarball。
#
# 目录布局和 Firefox 一样，整棵树不能拆，装在 /usr/lib64/zen：
#   zen         启动器，用 /proc/self/exe 判断自己所在目录
#   zen-bin     同一份二进制（这个版本里它俩内容完全一样）
#   libxul.so   真正的主体，按 dependentlibs.list 预加载
#   libnss3.so、libnspr4.so、libssl3.so…  自带的一套 NSS/NSPR
# 自带 .so 和 zen 在同一层目录，所以过滤依赖要分开处理：
#   provides：整个应用目录全部排除，免得本包声称提供 libnss3.so 这类系统库的 soname；
#   requires：只按「自带 .so 的文件名」过滤，libxul 依赖的 gtk3/dbus/X11 要留着。
# 这个写法是照抄 Fedora 官方 firefox.spec 的。
#
# 和 zed 一样的坑：COPR 一次构建只生成一个 SRPM、所有 chroot 共用它，
# 所以两个架构的 tarball 都写进 Source，构建时用 ifarch 选一个解包。
# ---------------------------------------------------------------------------

%global app_id  app.zen_browser.zen
%global appdir  %{_libdir}/zen
%global gh      zen-browser/desktop
%global gh_fp   zen-browser/flatpak

# 重打包二进制：不打 debuginfo，也不重新 strip
%global debug_package %{nil}
%global __strip /bin/true

# 上游的 libonnxruntime.so 带了个残废的 RUNPATH（字面量 "$"，大概是构建时 $ORIGIN
# 被 shell 吃掉了），会被 check-rpaths 判成非法。我们既不打补丁也不重新链接，直接跳过。
%global __brp_check_rpaths %{nil}

%global __provides_exclude_from ^%{appdir}
%global __requires_exclude ^(%%(find %{buildroot}%{appdir} -name '*.so' | xargs -n1 basename | sort -u | paste -s -d '|' -))

Name:           zen-browser
Version:        1.23b
Release:        1%{?dist}
Summary:        Privacy-focused web browser based on Firefox
# 上游 metainfo 里写的就是 MPL-2.0（tarball 里还带了一批第三方组件，许可清单打包在 omni.ja 中）
License:        MPL-2.0
URL:            https://zen-browser.app

Source0:        https://github.com/%{gh}/releases/download/%{version}/zen.linux-x86_64.tar.xz
Source1:        https://github.com/%{gh}/releases/download/%{version}/zen.linux-aarch64.tar.xz
Source2:        https://raw.githubusercontent.com/%{gh_fp}/%{version}/app.zen_browser.zen.desktop
Source3:        https://raw.githubusercontent.com/%{gh_fp}/%{version}/app.zen_browser.zen.metainfo.xml
Source4:        https://raw.githubusercontent.com/%{gh_fp}/%{version}/icons/app.zen_browser.zen.svg
Source5:        https://raw.githubusercontent.com/%{gh}/%{version}/LICENSE
# 下面两个是本仓库自己维护的，不是下载来的
Source6:        zen.sh
Source7:        policies.json

# 真正要解包的那个（两个 tarball 都在 SRPM 里）
%ifarch x86_64
%global zen_tarball zen.linux-x86_64.tar.xz
%else
%global zen_tarball zen.linux-aarch64.tar.xz
%endif

BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib
# 下面三个只为 check 段里跑一次 --version：启动器要加载 libxul.so，
# 需要 gtk3、alsa 和 libX11-xcb（最后这个在 Fedora 构建 root 里不会被 gtk3 拖进来，
# 因为构建 root 关掉了 weak deps）
BuildRequires:  gtk3
BuildRequires:  alsa-lib
BuildRequires:  libX11-xcb

ExclusiveArch:  x86_64 aarch64

Requires:       hicolor-icon-theme
Requires:       xdg-desktop-portal

%description
Zen Browser 是基于 Firefox 的浏览器，主打隐私，并自带垂直标签页、分屏、
侧边栏等界面改造。

本包重打包上游官方 Linux 预编译产物（并非从源码构建）。整棵应用树装在
/usr/lib64/zen 下，/usr/bin/zen 是转发到它的启动脚本；自带 libxul、NSS/NSPR
等库都在这个私有目录里，不会被其它程序加载，也不会和系统的 nss/nspr 冲突。
内置更新已关闭，升级请用 dnf。

%prep
# 压缩包顶层目录就是 zen/，直接解到构建目录
# （注意：spec 注释里别写宏写法，rpm 连注释里的宏都会展开）
rm -rf zen
tar -xf %{_sourcedir}/%{zen_tarball}

%build
# 纯重打包，没有编译步骤

%install
install -d %{buildroot}%{appdir}
cp -a zen/. %{buildroot}%{appdir}/

# 启动脚本
install -d %{buildroot}%{_bindir}
sed -e 's|@APP_DIR@|%{appdir}|' %{_sourcedir}/zen.sh > %{buildroot}%{_bindir}/zen
chmod 0755 %{buildroot}%{_bindir}/zen

# 关掉内置更新：装在 /usr/lib64 下普通用户也写不进去，升级交给 dnf
install -Dpm 0644 %{_sourcedir}/policies.json \
    %{buildroot}%{appdir}/distribution/policies.json

# 用系统的拼写词典（上游 tarball 里不带 dictionaries/hyphenation）
ln -s ../../share/hunspell %{buildroot}%{appdir}/dictionaries
ln -s ../../share/hyphen   %{buildroot}%{appdir}/hyphenation

# 桌面文件：用 flatpak 仓库那份（带完整翻译），把 Exec 从 flatpak 的 launch-script.sh 换成 zen
install -d %{buildroot}%{_datadir}/applications
sed -e 's|^Exec=launch-script\.sh|Exec=zen|' %{_sourcedir}/%{app_id}.desktop \
    > %{buildroot}%{_datadir}/applications/%{app_id}.desktop
chmod 0644 %{buildroot}%{_datadir}/applications/%{app_id}.desktop

# 图标：矢量图来自 flatpak 仓库，位图用 tarball 里的 Zen 图标，名字都跟 desktop 文件的 Icon 对齐
install -Dpm 0644 %{_sourcedir}/%{app_id}.svg \
    %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/%{app_id}.svg
for size in 16 32 48 64 128; do
    install -Dpm 0644 zen/browser/chrome/icons/default/default${size}.png \
        %{buildroot}%{_datadir}/icons/hicolor/${size}x${size}/apps/%{app_id}.png
done

install -Dpm 0644 %{_sourcedir}/%{app_id}.metainfo.xml \
    %{buildroot}%{_datadir}/metainfo/%{app_id}.metainfo.xml

install -Dpm 0644 %{_sourcedir}/LICENSE %{buildroot}%{_datadir}/licenses/%{name}/LICENSE

%check
export HOME=$(mktemp -d)

# 启动器跑得起来（会加载 libxul.so，所以上面 BuildRequires 里带了它的几个运行时库）
%{buildroot}%{appdir}/zen --version

# spec 版本要和包里的 application.ini 一致
grep -q "^Version=%{version}$" %{buildroot}%{appdir}/application.ini

# dependentlibs.list 里列的库都得在
while read -r lib; do
    test -e %{buildroot}%{appdir}/"$lib" || { echo "错误: 缺少自带库 $lib"; exit 1; }
done < %{buildroot}%{appdir}/dependentlibs.list

# 防呆：确认装进去的确实是本架构的二进制（万一 Source 选错了，这里会炸）
%ifarch x86_64
ldd %{buildroot}%{appdir}/zen-bin | grep -q 'ld-linux-x86-64'
%else
ldd %{buildroot}%{appdir}/zen-bin | grep -q 'ld-linux-aarch64'
%endif

desktop-file-validate %{buildroot}%{_datadir}/applications/%{app_id}.desktop
appstream-util validate-relax --nonet %{buildroot}%{_datadir}/metainfo/%{app_id}.metainfo.xml

%files
%license %{_datadir}/licenses/%{name}/LICENSE
%{_bindir}/zen
# 整个应用目录一起打包：浏览器内部文件多且会跟着上游变，逐条列没意义
%{appdir}/
%{_datadir}/applications/%{app_id}.desktop
%{_datadir}/icons/hicolor/scalable/apps/%{app_id}.svg
%{_datadir}/icons/hicolor/*/apps/%{app_id}.png
%{_datadir}/metainfo/%{app_id}.metainfo.xml

%changelog
* Mon Oct 05 2026  <> - 1.23b-1
- Update to 1.23b
* Sun Sep 27 2026 Yadomin <i@yadom.in> - 1.22.3b-1
- 首个版本：重打包上游预编译产物（zen.linux-{x86_64,aarch64}.tar.xz），
  用 flatpak 仓库的 desktop/metainfo/图标，关闭内置更新
