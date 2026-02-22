# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1 pypi

DESCRIPTION="Compact tool for building and debugging applications for Flipper Zero"
HOMEPAGE="
	https://github.com/flipperdevices/flipperzero-ufbt
	https://pypi.org/project/ufbt/
"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64 ~arm64 ~x86"

RDEPEND="
	>=dev-python/oslex-0.1.3[${PYTHON_USEDEP}]
"

src_prepare() {
	distutils-r1_src_prepare

	# setuptools-git-versioning is listed as a build requirement but is not
	# needed when building from a PyPI sdist; provide the version statically
	# to avoid requiring it at build time.
	cat >> setup.cfg <<-EOF
		[metadata]
		version = ${PV}
	EOF

	# Remove the dynamic version plugin to avoid the extra build dep.
	# The range deletion must run before the general pattern match that
	# would otherwise delete the section header first, leaving orphaned
	# keys folded into the preceding [project.scripts] table.
	sed -i \
		-e '/^\[tool\.setuptools-git-versioning\]/,/^$/d' \
		-e '/setuptools-git-versioning/d' \
		-e 's/"setuptools-git-versioning<2",//' \
		pyproject.toml || die
}
