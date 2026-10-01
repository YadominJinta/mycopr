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
#
# 下载策略：先下到 <文件>.part 并校验，通过才改名成正式文件。
# 这样断点续传不会把「上一个版本的旧文件」当成半成品接着下
# （上游换版本、文件名不变时会踩到：旧文件哈希对不上，但字节数还是旧的）。

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

verify() {  # verify <sha256> <文件>
    printf '%s  %s\n' "$1" "$2" | sha256sum --check --status 2>/dev/null
}

fetch() {   # fetch <文件名> <URL> <sha256>
    local filename=$1 url=$2 sha256=$3
    local target=$outdir/$filename
    local part=$target.part

    if [[ -f $target ]] && verify "$sha256" "$target"; then
        echo "已存在，校验通过: $filename"
        return 0
    fi

    if [[ -f $part ]] && verify "$sha256" "$part"; then
        echo "上次已经下完: $filename"
    else
        echo "下载 $filename"
        curl --fail --location --retry 3 --retry-delay 5 --retry-all-errors \
            --continue-at - --output "$part" "$url"
        if ! verify "$sha256" "$part"; then
            # 续传下来的半成品可能来自别的内容，老老实实重头下一次
            echo "校验不符，重新完整下载: $filename"
            rm -f "$part"
            curl --fail --location --retry 3 --retry-delay 5 --retry-all-errors \
                --output "$part" "$url"
        fi
    fi

    if ! verify "$sha256" "$part"; then
        echo "错误: $filename 的 sha256 和 sources 里记的对不上" >&2
        exit 1
    fi
    mv -f "$part" "$target"
    echo "$filename: OK"
}

while read -r filename row_arch sha256 url; do
    case ${filename:-} in ''|\#*) continue ;; esac
    if [[ $fetch_all -eq 0 && $row_arch != all && $row_arch != "$arch" ]]; then
        continue
    fi
    fetch "$filename" "$url" "$sha256"
done < "$sources_file"
