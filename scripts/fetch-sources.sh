#!/usr/bin/env bash
#
# 按「包目录/sources」清单下载并校验源码，放到 spec 旁边（= rpmbuild 的 %_sourcedir）。
#
# sources 文件格式，每行一条（# 开头是注释，空行忽略）：
#
#   <文件名>  <架构>  <sha256>  <URL>
#
# 架构写 all / x86_64 / aarch64：只有 all 和当前架构的行会被下载。
#
# 用法:
#   fetch-sources.sh <spec 路径> [输出目录]
#   fetch-sources.sh --all-arches <spec 路径> [输出目录]   # 维护时把两个架构都拉下来

set -euo pipefail

fetch_all=0
if [[ ${1:-} == --all-arches ]]; then
    fetch_all=1
    shift
fi

spec=${1:?用法: fetch-sources.sh [--all-arches] <spec 路径> [输出目录]}
spec=$(realpath "$spec")
pkgdir=$(dirname "$spec")
outdir=${2:-$pkgdir}
sources_file=$pkgdir/sources

if [[ ! -f $sources_file ]]; then
    echo "错误: 找不到 $sources_file" >&2
    exit 1
fi

# 目标架构：优先问 rpm（和 rpmbuild 保持一致），没有 rpm 就退回 uname
arch=$(rpm --eval '%{_arch}' 2>/dev/null | tail -n1)
[[ -n $arch ]] || arch=$(uname -m)

mkdir -p "$outdir"

while read -r filename row_arch sha256 url; do
    case ${filename:-} in ''|\#*) continue ;; esac
    if [[ $fetch_all -eq 0 && $row_arch != all && $row_arch != "$arch" ]]; then
        continue
    fi

    target=$outdir/$filename
    if [[ -f $target ]] && printf '%s  %s\n' "$sha256" "$target" | sha256sum --check --status 2>/dev/null; then
        echo "已存在且校验通过: $filename"
        continue
    fi

    echo "下载 $filename"
    curl --fail --location --retry 3 --retry-delay 5 --continue-at - \
        --output "$target" "$url"
    printf '%s  %s\n' "$sha256" "$target" | sha256sum --check -
done < "$sources_file"
