#!/usr/bin/env bash
#
# 生成 SRPM：本地和 COPR 的 "make srpm" 都走这里。
# 会先按「包目录/sources」把源码下载/校验到 spec 旁边，再调 rpmbuild -bs。
#
# 用法: make-srpm.sh <spec> [输出目录]     # 输出目录默认当前目录

set -euo pipefail

spec_arg=${1:?用法: make-srpm.sh <spec> [输出目录]}
outdir=${2:-$PWD}
script_dir=$(dirname "$(realpath "$0")")

# COPR 传进来的 spec 路径可能是相对「包目录」也可能是相对「仓库根目录」，两种都试
resolve_spec() {
    local cand
    for cand in "$spec_arg" "$PWD/$spec_arg" "$PWD/../$spec_arg"; do
        [[ -f $cand ]] && { realpath "$cand"; return 0; }
    done
    echo "错误: 找不到 spec 文件 $spec_arg" >&2
    return 1
}

spec=$(resolve_spec)
pkgdir=$(dirname "$spec")

"$script_dir/fetch-sources.sh" "$spec" "$pkgdir"

mkdir -p "$outdir"
# 独立的 _topdir，避免碰到 ~/rpmbuild
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

rpmbuild -bs \
    --define "_topdir $workdir" \
    --define "_sourcedir $pkgdir" \
    --define "_srcrpmdir $outdir" \
    "$spec"

echo
echo "生成的 SRPM："
ls -l "$outdir"/*.src.rpm
