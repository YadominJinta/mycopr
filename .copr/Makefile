# COPR SCM 的 "make srpm" 入口（整个仓库共用这一个 Makefile）。
#
# COPR 以「包目录」为 cwd 调用它：
#   make -f <repo>/.copr/Makefile srpm outdir=<输出目录> spec=<spec 路径>
# 所以每个包在 COPR 里这样配：
#   Subdirectory        = <包目录>        （例如 zed）
#   Spec File           = <包名>.spec     （例如 zed.spec）
#   SRPM 生成方式        = make srpm
#
# 本地不用跑 make，直接用 ./scripts/build-local.sh <包目录>。

# 从 -f 传入的路径反推仓库根目录
REPO_ROOT := $(patsubst %/.copr/Makefile,%,$(lastword $(MAKEFILE_LIST)))
ifeq ($(REPO_ROOT),$(lastword $(MAKEFILE_LIST)))
  ifneq ($(wildcard $(CURDIR)/.copr/Makefile),)
REPO_ROOT := $(CURDIR)
  else
REPO_ROOT := $(CURDIR)/..
  endif
endif
REPO_ROOT := $(abspath $(REPO_ROOT))

spec   ?= $(firstword $(wildcard $(CURDIR)/*.spec))
outdir ?= $(CURDIR)

.PHONY: srpm
srpm:
	@command -v rpmbuild >/dev/null 2>&1 || dnf -y install rpm-build
	@command -v curl     >/dev/null 2>&1 || dnf -y install curl
	$(REPO_ROOT)/scripts/make-srpm.sh "$(spec)" "$(outdir)"
