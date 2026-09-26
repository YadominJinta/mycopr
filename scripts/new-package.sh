#!/usr/bin/env bash
#
# 新建一个包的骨架：<包名>/{<包名>.spec,sources}
#
# 用法: new-package.sh <包名>
#
# 之后要做的事：
#   1. 填 spec 里的 TODO，把 Source 的 URL 和校验和写进 sources（格式见文件头注释）
#   2. ./scripts/build-local.sh <包名>  --mock   验证能构建
#   3. 提交推送后，在 COPR 项目里加一个 SCM 包（Subdirectory/Spec File/make srpm）

set -euo pipefail

name=${1:?用法: new-package.sh <包名>}
root=$(cd "$(dirname "$(realpath "$0")")/.." && pwd)

[[ $name =~ ^[a-zA-Z0-9._+-]+$ ]] || { echo "错误: 包名不合法: $name" >&2; exit 1; }
[[ -e $root/$name ]] && { echo "错误: $root/$name 已存在" >&2; exit 1; }

mkdir -p "$root/$name"

cat > "$root/$name/$name.spec" <<EOF
# 翻译/说明写这里，或者删掉。

Name:           $name
Version:        0.0.0
Release:        1%{?dist}
Summary:        TODO 一句话说明

License:        TODO SPDX（例如 MIT / GPL-3.0-or-later / Apache-2.0）
URL:            TODO 上游主页
Source0:        TODO 上游源码或产物 URL（用 %{version} 拼出来，方便 update.sh 更新）

# 预编译产物重打包时通常要写：
#   %global debug_package %{nil}
#   %global __strip /bin/true
# 并把上游自带的 .so 放进私有目录、排除依赖生成：
#   %global __provides_exclude_from ^%{_libdir}/$name/lib/.*\$
#   %global __requires_exclude_from ^%{_libdir}/$name/lib/.*\$

BuildRequires:  TODO
# ExclusiveArch: x86_64 aarch64

%description
TODO

%prep
%autosetup -n TODO

%build
%configure   # 或 cargo build / cmake ...
%make_build

%install
%make_install

%files
%license TODO
%{_bindir}/TODO

%changelog
EOF

cat > "$root/$name/sources" <<'EOF'
# 每行: <文件名>  <架构(all|x86_64|aarch64)>  <sha256>  <URL>
# 用 zed/update.sh 那种脚本自动生成，或者手动填：
#   curl -sL <URL> -o <文件名> && sha256sum <文件名>
EOF

echo "已创建 $name/："
ls -l "$root/$name"
echo
echo "别忘了在 README 的包列表里加上 $name。"
