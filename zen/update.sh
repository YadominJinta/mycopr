#!/usr/bin/env bash
#
# 把 zen.spec 更新到上游新版本：
#   1. 从 GitHub API 取 zen-browser/desktop 的最新 release（或指定版本）
#   2. 改 spec 里的 Version（Source 都用 %{version} 拼，不用动）
#   3. 重写 sources 校验和：两个架构的 tarball 用 GitHub 给的 digest，
#      其余小文件（desktop / metainfo / svg / LICENSE）下载后自己算
#   4. 在 %changelog 顶部插一条
#
# 版本号同时是 zen-browser/desktop 和 zen-browser/flatpak 两个仓库的 tag，
# 脚本会检查 flatpak 那边也有这个 tag（desktop 文件、AppStream 元数据、图标从那儿取）。
#
# 用法:
#   ./update.sh                  # 更新到上游最新 release
#   ./update.sh --check          # 只看有没有新版本，不改文件
#   ./update.sh 1.23b            # 指定版本
#   ./update.sh --force 1.22.3b  # 版本相同也重跑一遍
#
# 网络：curl 会走 https_proxy / http_proxy 环境变量。

set -euo pipefail

cd "$(dirname "$(realpath "$0")")"

gh_repo=zen-browser/desktop
gh_fp=zen-browser/flatpak
specfile=zen.spec
sources_file=sources

check_only=0
force=0
version_arg=''
while [[ $# -gt 0 ]]; do
    case $1 in
        --check) check_only=1 ;;
        --force) force=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "未知参数: $1" >&2; exit 2 ;;
        *) version_arg=$1 ;;
    esac
    shift
done

curl_json() { curl -sSfL --retry 3 --retry-delay 5 "$@"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

api=https://api.github.com/repos/$gh_repo
if [[ -n $version_arg ]]; then
    tag=${version_arg#v}
    echo "查 $tag ..."
    curl_json "$api/releases/tags/$tag" > "$tmp/release.json" || {
        echo "错误: 上游没有 $tag 这个 release" >&2; exit 1; }
else
    echo "查上游最新 release ..."
    curl_json "$api/releases/latest" > "$tmp/release.json"
fi

version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"].removeprefix("v"))' "$tmp/release.json")
current=$(awk -F': *' '/^Version:/{print $2; exit}' "$specfile")

echo "spec 当前版本: $current"
echo "上游版本:      $version"

if [[ $current == "$version" && $force -eq 0 ]]; then
    echo "已经是最新，什么都不用改。"
    exit 0
fi
[[ $check_only -eq 1 ]] && exit 0

# flatpak 仓库的 desktop 文件 / metainfo / 图标都按版本号打 tag，先确认有
if ! curl_json -o /dev/null "https://api.github.com/repos/$gh_fp/git/ref/tags/$version"; then
    echo "错误: zen-browser/flatpak 里没有 tag $version，先确认那边发了这个版本" >&2
    exit 1
fi

# ---- sources ---------------------------------------------------------------
# 架构 tarball：优先用 GitHub API 给的 digest（省掉 200MB 下载）
python3 - "$version" "$tmp/release.json" > "$tmp/arch_rows" <<'PY'
import json, sys
version, path = sys.argv[1], sys.argv[2]
assets = {a["name"]: a for a in json.load(open(path))["assets"]}
rows = []
for arch in ("x86_64", "aarch64"):
    name = f"zen.linux-{arch}.tar.xz"
    asset = assets.get(name)
    if asset is None:
        sys.exit(f"错误: release 里没有 {name}")
    digest = (asset.get("digest") or "").removeprefix("sha256:")
    rows.append("\t".join([name, "all", digest, asset["browser_download_url"]]))
print("\n".join(rows))
PY

# 其余小文件：下载后自己算（本地文件名 -> URL）
small_files=(
    "app.zen_browser.zen.desktop|https://raw.githubusercontent.com/$gh_fp/$version/app.zen_browser.zen.desktop"
    "app.zen_browser.zen.metainfo.xml|https://raw.githubusercontent.com/$gh_fp/$version/app.zen_browser.zen.metainfo.xml"
    "app.zen_browser.zen.svg|https://raw.githubusercontent.com/$gh_fp/$version/icons/app.zen_browser.zen.svg"
    "LICENSE|https://raw.githubusercontent.com/$gh_repo/$version/LICENSE"
)
: > "$tmp/extra_rows"
for entry in "${small_files[@]}"; do
    name=${entry%%|*}
    url=${entry#*|}
    echo "下载 $url"
    curl_json -o "$tmp/$name" "$url"
    printf '%s\tall\t%s\t%s\n' \
        "$name" "$(sha256sum "$tmp/$name" | cut -d' ' -f1)" "$url" >> "$tmp/extra_rows"
done

# digest 缺失时（老 release 没给 digest）兜底：老实下载算一次
while IFS=$'\t' read -r name arch sha256 url; do
    [[ -n $sha256 ]] && continue
    echo "GitHub 没给 $name 的 digest，下载计算校验和（比较慢）..."
    curl_json -o "$tmp/$name" "$url"
    sha=$(sha256sum "$tmp/$name" | cut -d' ' -f1)
    python3 - "$tmp/arch_rows" "$name" "$sha" <<'PY'
import sys
path, name, sha = sys.argv[1:4]
rows = []
for line in open(path):
    f = line.rstrip("\n").split("\t")
    if f[0] == name:
        f[2] = sha
    rows.append("\t".join(f))
open(path, "w").write("\n".join(rows) + "\n")
PY
done < "$tmp/arch_rows"

{
    echo "# 每行: <文件名>  <架构(all|x86_64|aarch64)>  <sha256>  <URL>"
    echo "# 由 update.sh 自动生成，手工改的话记得同步 spec 里的 Source。"
    echo "#"
    echo "# 两个 tarball 都写成 all：COPR 一次构建只生成一个 SRPM、所有 chroot 共用，"
    echo "# 所以 SRPM 里必须两个架构的包都有，构建时由 spec 用 ifarch 选一个解包。"
    cat "$tmp/arch_rows" "$tmp/extra_rows"
} > "$sources_file"
echo "已更新 $sources_file"

# ---- spec ------------------------------------------------------------------
sed -i -e "s|^Version:.*|Version:        $version|" "$specfile"

packager_name=$(git config user.name || true)
packager_mail=$(git config user.email || true)
if [[ -z $packager_name || -z $packager_mail ]]; then
    echo "警告: 没设 git user.name/user.email，changelog 里的署名会是空的" >&2
fi
date_str=$(LC_ALL=C date '+%a %b %d %Y')
entry="* $date_str $packager_name <$packager_mail> - $version-1
- Update to $version"
awk -v entry="$entry" '
    { print }
    /^%changelog$/ && !done { print entry; done = 1 }
' "$specfile" > "$tmp/spec" && mv "$tmp/spec" "$specfile"
echo "已更新 $specfile（Version = $version，changelog 加了一条）"

# ---- 下一步 ----------------------------------------------------------------
cat <<EOF

接下来：
    git -C .. diff                          # 看一眼改动
    ../scripts/build-local.sh zen --srpm    # 先出个 SRPM 试试
    ../scripts/build-local.sh zen --podman  # 有条件就整个构建一遍
    # 确认没问题后提交推送，COPR 那边 rebuild / 等 webhook 触发
EOF
