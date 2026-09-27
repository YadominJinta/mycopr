#!/bin/sh
# Fedora 包用的启动器。
#
# Zen 官方的启动器是应用目录里的 zen（ELF，用 /proc/self/exe 判断自己所在目录），
# 它会在同目录里找 libxul.so、libnss3.so 等自带库，所以整棵树必须一起装，
# 不能把 zen 单独拷到 /usr/bin —— 这里只是转一道。
#
# flatpak 版会多传 --name app.zen_browser.zen（沙箱里需要独立的 D-Bus 名字），
# 原生安装不需要（AUR 的原生包同样不加），保持默认即可。
exec @APP_DIR@/zen "$@"
