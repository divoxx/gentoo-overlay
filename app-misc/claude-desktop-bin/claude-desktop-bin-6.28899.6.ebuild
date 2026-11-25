# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit chromium-2 linux-info optfeature unpacker xdg

MY_PN="${PN%-bin}"

DESCRIPTION="Official desktop app for Claude, Anthropic's AI assistant"
HOMEPAGE="
	https://claude.com/download
	https://code.claude.com/docs/en/desktop-linux
"
# Anthropic publishes Linux builds only through its APT repository. The
# dists/stable/main/binary-amd64/Packages index there lists every version.
SRC_URI="https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/${MY_PN}/${MY_PN}_${PV}_amd64.deb"
S="${WORKDIR}"

# Claude Desktop itself is proprietary. The other licenses cover the bundled
# Electron/Chromium runtime, FFmpeg, SwiftShader, the Vulkan loader and node-pty.
LICENSE="all-rights-reserved Apache-2.0 BSD LGPL-2.1+ MIT"
SLOT="0"
KEYWORDS="-* ~amd64"
# Off by default because Cowork pulls in QEMU.
IUSE="cowork"
RESTRICT="bindist mirror strip"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-crypt/libsecret
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/mesa[opengl]
	media-video/pipewire
	net-print/cups
	sys-apps/dbus
	sys-apps/xdg-desktop-portal
	virtual/libudev
	x11-libs/cairo
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/pango
	x11-misc/xdg-utils
	cowork? (
		app-emulation/qemu[qemu_softmmu_targets_x86_64]
		app-emulation/virtiofsd
		|| (
			sys-firmware/edk2-bin[qemu_softmmu_targets_x86_64(+)]
			sys-firmware/edk2
		)
	)
"

QA_PREBUILT="opt/${MY_PN}/*"

pkg_setup() {
	chromium_suid_sandbox_check_kernel_config

	if use cowork && [[ ${MERGE_TYPE} != buildonly ]]; then
		CONFIG_CHECK="~KVM ~VHOST_VSOCK"
		WARNING_KVM="CONFIG_KVM is required for the Cowork virtual machine"
		WARNING_VHOST_VSOCK="CONFIG_VHOST_VSOCK is required for Cowork (/dev/vhost-vsock)"
		check_extra_config
	fi
}

src_prepare() {
	default

	local res="usr/lib/${MY_PN}/resources"

	# The app falls back to its bundled virtiofsd only on Ubuntu 22.04.
	rm -f "${res}"/virtiofsd{,.LICENSE-APACHE,.LICENSE-BSD-3-Clause} || die

	# D-Bus starts the GNOME Shell search provider from the install location.
	local service="${res}/gnome-search-provider/com.anthropic.Claude.SearchProvider.service"
	sed -i "s|/usr/lib/${MY_PN}/|${EPREFIX}/opt/${MY_PN}/|" "${service}" || die
	grep -q "${EPREFIX}/opt/${MY_PN}/" "${service}" || die "search provider path not rewritten"
}

src_install() {
	local app="usr/lib/${MY_PN}"

	dodir /opt
	cp -r "${app}" "${ED}/opt/${MY_PN}" || die
	fperms 4711 "/opt/${MY_PN}/chrome-sandbox"
	dosym -r "/opt/${MY_PN}/${MY_PN}" "/usr/bin/${MY_PN}"

	insinto /usr/share
	doins -r usr/share/{applications,icons}

	# Upstream's Debian maintainer scripts copy these into place on install.
	insinto /usr/share/mime/packages
	doins "${app}"/resources/linux-mime/com.anthropic.Claude.xml
	insinto /usr/share/gnome-shell/search-providers
	doins "${app}"/resources/gnome-search-provider/com.anthropic.Claude.search-provider.ini
	insinto /usr/share/dbus-1/services
	doins "${app}"/resources/gnome-search-provider/com.anthropic.Claude.SearchProvider.service

	if use cowork; then
		# Cowork looks for UEFI firmware only in Debian's /usr/share/OVMF and
		# derives the variable store template from the code image's name.
		local fw
		for fw in OVMF_CODE.fd OVMF_VARS.fd; do
			dosym -r "/usr/share/edk2/OvmfX64/${fw}" "/usr/share/OVMF/${fw}"
		done
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	optfeature "saving the sign-in to a keyring" virtual/secret-service
	optfeature "sandboxing commands in Claude Code sessions" "sys-apps/bubblewrap net-misc/socat"
	optfeature "SSH remote sessions" virtual/openssh

	if use cowork; then
		elog "Cowork needs access to /dev/kvm and /dev/vhost-vsock. Add your user"
		elog "to the kvm group, then log out and back in. Load the vhost_vsock"
		elog "kernel module if /dev/vhost-vsock is missing."
	elif [[ -z ${REPLACING_VERSIONS} ]]; then
		elog "Cowork runs its tasks in a QEMU virtual machine. Enable USE=cowork"
		elog "to install QEMU, virtiofsd and the UEFI firmware it needs."
	fi
}
