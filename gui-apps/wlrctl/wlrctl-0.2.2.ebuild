# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit meson

DESCRIPTION="Command line utility for miscellaneous wlroots Wayland extensions"
HOMEPAGE="https://git.sr.ht/~brocellous/wlrctl"
SRC_URI="https://git.sr.ht/~brocellous/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${PN}-v${PV}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="
	dev-libs/wayland
	x11-libs/libxkbcommon
"
RDEPEND="${DEPEND}"
BDEPEND="
	app-text/scdoc
	dev-util/wayland-scanner
	virtual/pkgconfig
"

src_configure() {
	local emesonargs=(
		-Dman-pages=enabled
		-Dzsh-completions=true
	)
	meson_src_configure
}
