#!/usr/bin/env bash
#
# 本地构建某个包：先出 SRPM，再构建成 RPM。
#
# 用法:
#   build-local.sh <包目录名> [选项]
#
#   -s, --srpm              只生成 SRPM，不构建 RPM
#   -p, --podman [镜像]     在 podman 容器里构建（不需要 root，推荐；默认 fedora:45）
#   -m, --mock [CHROOT]     用 mock 构建（需要 root；chroot 默认 $MOCK_CHROOT 或 fedora-45-x86_64）
#   -c, --clean             构建前清掉 .build/
#   -l, --lint              额外跑 rpmlint（装了才跑）
#
# 产物都在仓库的 .build/ 下：
#   .build/srpm/                SRPM
#   .build/rpm/                 本机 rpmbuild 出来的 RPM
#   .build/mock/<chroot>/       mock 产物
#   .build/podman/<镜像>/       容器产物
#   .build/build.log            本机构建日志
#
# 默认的 rpmbuild 方式要求本机装好 rpm-build 和 spec 里的 BuildRequires：
#   sudo dnf install rpm-build rpmdevtools
#   sudo dnf builddep <包目录>/<包名>.spec

set -euo pipefail

root=$(cd "$(dirname "$(realpath "$0")")/.." && pwd)

pkg=''
mode=rpmbuild
image=${PODMAN_IMAGE:-fedora:45}
chroot=${MOCK_CHROOT:-fedora-45-x86_64}
srpm_only=0
lint=0
clean=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--srpm)   srpm_only=1 ;;
        -p|--podman) mode=podman; [[ ${2:-} && ${2:-} != -* ]] && { image=$2; shift; } ;;
        -m|--mock)   mode=mock;   [[ ${2:-} && ${2:-} != -* ]] && { chroot=$2; shift; } ;;
        -c|--clean)  clean=1 ;;
        -l|--lint)   lint=1 ;;
        -h|--help)   sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)          echo "未知参数: $1" >&2; exit 2 ;;
        *)           pkg=$1 ;;
    esac
    shift
done

[[ -n $pkg ]] || { echo "用法: build-local.sh <包目录名> [-s|--srpm] [-p|--podman [镜像]] [-m|--mock [CHROOT]] [-c] [-l]" >&2; exit 2; }

spec=$root/$pkg/$pkg.spec
[[ -f $spec ]] || { echo "错误: 找不到 $spec" >&2; exit 1; }

out=$root/.build
[[ $clean -eq 1 ]] && rm -rf "$out"
# 每次重新生成 SRPM，免得旧版本的 SRPM 混在里面
rm -rf "$out/srpm"
mkdir -p "$out/srpm"

echo "== 包: $pkg    方式: $mode"

if [[ $mode == podman ]]; then
    # ---------------------------------------------------------------- 容器
    command -v podman >/dev/null 2>&1 || { echo "错误: 没装 podman" >&2; exit 1; }
    tag=$(echo "$image" | tr '/:' '__')
    rpm_dir=$out/podman/$tag
    mkdir -p "$rpm_dir"

    script=$(cat <<EOF
set -euo pipefail
dnf -y -q install rpm-build curl >/dev/null
dnf -y -q install dnf5-plugins || dnf -y -q install dnf-plugins-core || true
/srv/scripts/make-srpm.sh /srv/$pkg/$pkg.spec /srv/.build/srpm
EOF
)
    if [[ $srpm_only -eq 0 ]]; then
        # 开头空一行：上面那次 $(cat ...) 会把末尾换行吃掉，不隔开两段命令会粘在一起
        script+=$(cat <<EOF

dnf -y -q builddep /srv/.build/srpm/$pkg-*.src.rpm >/dev/null
rpmbuild --rebuild /srv/.build/srpm/$pkg-*.src.rpm \\
    --define '_rpmdir /srv/.build/podman/$tag' \\
    --define '_topdir /tmp/rpmbuild'
EOF
)
    fi

    # 容器里的 127.0.0.1 就是宿主机，所以本机代理可以直接透传（没设的话 podman 就不传）
    podman run --rm --network=host \
        -e https_proxy -e http_proxy -e HTTPS_PROXY -e HTTP_PROXY \
        -v "$root:/srv:Z" -w "/srv/$pkg" "$image" bash -c "$script"
else
    # ------------------------------------------------------------ 本机
    "$root/scripts/make-srpm.sh" "$spec" "$out/srpm"
    srpm=$(ls -t "$out/srpm"/*.src.rpm | head -n1)

    if [[ $srpm_only -eq 0 && $mode == mock ]]; then
        command -v mock >/dev/null 2>&1 || {
            echo "错误: 没装 mock（sudo dnf install mock），或者改用 --podman" >&2; exit 1; }
        rpm_dir=$out/mock/$chroot
        mock -r "$chroot" --rebuild "$srpm" --resultdir "$rpm_dir"
    elif [[ $srpm_only -eq 0 ]]; then
        rpm_dir=$out/rpm
        if ! rpmbuild --rebuild "$srpm" \
                --define "_topdir $out/rpmbuild" \
                --define "_rpmdir $rpm_dir" 2>&1 | tee "$out/build.log"; then
            echo >&2
            echo "构建失败。常见原因是 BuildRequires 没装：" >&2
            echo "    sudo dnf builddep $spec" >&2
            echo "或者用容器构建（不需要 root）：build-local.sh $pkg --podman" >&2
            exit 1
        fi
    fi
fi

echo
if [[ $srpm_only -eq 1 ]]; then
    echo "生成的 SRPM："
    find "$out/srpm" -name '*.src.rpm' -printf '%p\n'
elif [[ -n ${rpm_dir:-} ]]; then
    echo "生成的 RPM："
    find "$rpm_dir" -name '*.rpm' -printf '%p\n' | sort
fi

if [[ $lint -eq 1 ]]; then
    if command -v rpmlint >/dev/null 2>&1; then
        echo
        echo "== rpmlint =="
        rpmlint "$out/srpm"/*.src.rpm ${rpm_dir:-}/**/*.rpm || true
    else
        echo "(没装 rpmlint，跳过：sudo dnf install rpmlint)"
    fi
fi
