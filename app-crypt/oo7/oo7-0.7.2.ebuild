# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	aes@0.9.4
	aho-corasick@1.1.5
	anstream@1.0.0
	anstyle@1.0.14
	anstyle-parse@1.0.0
	anstyle-query@1.1.5
	anstyle-wincon@3.0.11
	anyhow@1.0.104
	ashpd@0.14.1
	async-channel@2.5.0
	async-fs@2.2.0
	async-io@2.6.0
	async-lock@3.5.0
	async-task@4.7.1
	async-trait@0.1.92
	atomic-waker@1.1.2
	autocfg@1.5.1
	base64@0.23.1
	bitflags@2.13.2
	block@0.1.6
	block-buffer@0.12.1
	block-padding@0.4.2
	blocking@1.7.0
	blowfish@0.10.0
	bumpalo@3.20.4
	byteorder@1.5.0
	bytes@1.12.2
	cargo-credential@0.4.11
	cbc@0.2.1
	cc@1.11.2
	cfg-if@1.0.5
	cipher@0.5.2
	clap@4.6.8
	clap_builder@4.6.7
	clap_derive@4.6.8
	clap_lex@1.1.2
	cmov@0.5.4
	colorchoice@1.0.5
	concurrent-queue@2.5.0
	const-oid@0.10.3
	cpubits@0.1.1
	cpufeatures@0.3.1
	crossbeam-utils@0.8.23
	crypto-common@0.2.2
	ctutils@0.4.8
	deranged@0.5.9
	digest@0.11.3
	ecb@0.2.1
	endi@1.1.1
	errno@0.3.15
	event-listener@5.4.2
	event-listener-strategy@0.5.4
	fastrand@2.5.0
	find-msvc-tools@0.1.15
	foreign-types@0.3.2
	foreign-types-shared@0.1.1
	formatx@0.4.2
	futures-channel@0.3.34
	futures-core@0.3.34
	futures-io@0.3.34
	futures-lite@2.6.1
	futures-macro@0.3.34
	futures-task@0.3.34
	futures-util@0.3.34
	getrandom@0.3.4
	getrandom@0.4.3
	gettext-rs@0.8.0
	gettext-sys@0.27.0
	heck@0.5.0
	hermit-abi@0.5.3
	hex@0.4.3
	hkdf@0.13.0
	hmac@0.13.0
	hybrid-array@0.4.15
	inout@0.2.6
	is_terminal_polyfill@1.70.2
	itoa@1.0.19
	js-sys@0.3.107
	lazy_static@1.5.1
	libc@0.2.191
	libm@0.2.16
	linux-raw-sys@0.12.1
	locale_config@0.3.0
	lock_api@0.4.14
	log@0.4.35
	malloc_buf@0.0.6
	matchers@0.2.0
	md-5@0.11.0
	memchr@2.8.3
	memoffset@0.9.1
	mio@1.2.5
	nu-ansi-term@0.50.3
	num@0.4.3
	num-bigint@0.4.8
	num-bigint-dig@0.9.1
	num-complex@0.4.6
	num-conv@0.2.2
	num-integer@0.1.47
	num-iter@0.1.46
	num-rational@0.4.2
	num-traits@0.2.19
	num_threads@0.1.8
	objc@0.2.7
	objc-foundation@0.1.1
	objc_id@0.1.1
	once_cell@1.21.4
	once_cell_polyfill@1.70.2
	openssl@0.10.82
	openssl-macros@0.1.1
	openssl-sys@0.9.118
	ordered-stream@0.2.0
	parking@2.2.1
	parking_lot@0.12.5
	parking_lot_core@0.9.12
	pbkdf2@0.13.0
	pin-project-lite@0.2.17
	piper@0.2.5
	pkg-config@0.3.34
	polling@3.11.0
	portable-atomic@1.15.0
	powerfmt@0.2.1
	ppv-lite86@0.2.21
	proc-macro2@1.0.107
	pyo3@0.30.1
	pyo3-async-runtimes@0.30.0
	pyo3-build-config@0.30.1
	pyo3-ffi@0.30.1
	pyo3-macros@0.30.1
	pyo3-macros-backend@0.30.1
	quote@1.0.47
	r-efi@5.3.0
	r-efi@6.0.0
	rand@0.9.5
	rand_chacha@0.9.0
	rand_core@0.9.5
	redox_syscall@0.5.18
	regex@1.13.2
	regex-automata@0.4.19
	regex-syntax@0.8.12
	rpassword@7.5.5
	rtoolbox@0.0.6
	rustix@1.1.6
	rustversion@1.0.23
	scopeguard@1.2.0
	serde@1.0.229
	serde_bytes@0.11.19
	serde_core@1.0.229
	serde_derive@1.0.229
	serde_json@1.0.154
	serde_repr@0.1.21
	sha1@0.11.0
	sha2@0.11.1
	sharded-slab@0.1.7
	shlex@2.0.1
	signal-hook-registry@1.4.8
	slab@0.4.12
	smallvec@1.16.6
	socket2@0.6.5
	strsim@0.11.1
	subtle@2.6.1
	syn@2.0.119
	syn@3.0.10
	target-lexicon@0.13.6
	temp-dir@0.1.16
	tempfile@3.27.0
	thiserror@2.0.21
	thiserror-impl@2.0.21
	thread_local@1.1.10
	time@0.3.55
	time-core@0.1.9
	time-macros@0.2.32
	tokio@1.54.1
	tokio-macros@2.7.2
	tokio-stream@0.1.19
	tracing@0.1.44
	tracing-attributes@0.1.31
	tracing-core@0.1.36
	tracing-journald@0.3.2
	tracing-log@0.2.0
	tracing-subscriber@0.3.23
	typenum@1.20.1
	uds_windows@1.2.1
	unicode-ident@1.0.27
	utf8parse@0.2.2
	uuid@1.29.3
	valuable@0.1.1
	vcpkg@0.2.15
	wasi@0.11.1+wasi-snapshot-preview1
	wasip2@1.0.4+wasi-0.2.12
	wasm-bindgen@0.2.130
	wasm-bindgen-macro@0.2.130
	wasm-bindgen-macro-support@0.2.130
	wasm-bindgen-shared@0.2.130
	winapi@0.3.9
	winapi-i686-pc-windows-gnu@0.4.0
	winapi-x86_64-pc-windows-gnu@0.4.0
	windows-link@0.2.1
	windows-sys@0.61.2
	winnow@1.0.5
	wit-bindgen@0.57.1
	zbus@6.3.0
	zbus_macros@6.3.0
	zbus_utils@6.1.0
	zcheapstr@1.2.0
	zerocopy@0.8.63
	zerocopy-derive@0.8.63
	zeroize@1.9.2
	zeroize_derive@1.5.0
	zgvariant@2.0.0
	zgvariant_derive@2.0.0
	zmij@1.0.23
	zruntime@0.2.3
"

RUST_MIN_VER="1.95.0"

inherit cargo desktop pam systemd

DESCRIPTION="Secret Service provider, portal backend and keyring tools"
HOMEPAGE="https://github.com/linux-credentials/oo7"
SRC_URI="
	https://github.com/linux-credentials/oo7/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"

LICENSE="MIT"
# Dependent crate licenses
LICENSE+="
	Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD MIT Unicode-3.0
	|| ( Apache-2.0 MIT )
	|| ( Apache-2.0 Apache-2.0-with-LLVM-exceptions MIT )
	|| ( Apache-2.0 BSD-2 MIT )
	|| ( Apache-2.0 LGPL-2.1+ MIT )
	|| ( MIT Unlicense )
"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+daemon openssl pam +portal"
REQUIRED_USE="pam? ( daemon )"
# The server and portal test suites need a running D-Bus session bus
RESTRICT="test"

RDEPEND="
	openssl? ( dev-libs/openssl:= )
	daemon? (
		!gnome-base/gnome-keyring
		sys-apps/dbus
		virtual/libintl
	)
	pam? ( sys-libs/pam )
	portal? ( sys-apps/xdg-desktop-portal )
"
DEPEND="${RDEPEND}"
BDEPEND="virtual/pkgconfig"

# Fill in the @placeholders@ of an upstream data/*.in template.
# Usage: _oo7_configure_file <input> <output> <key=value>...
_oo7_configure_file() {
	local in=${1} out=${2} kv sedargs=()
	shift 2
	for kv in "$@"; do
		sedargs+=( -e "s|@${kv%%=*}@|${kv#*=}|g" )
	done
	sed "${sedargs[@]}" "${in}" > "${out}" || die "configuring ${in} failed"
}

src_configure() {
	local crypto=$(usex openssl openssl_crypto native_crypto)
	local myfeatures=(
		oo7-cli/${crypto}
		oo7-cli/kwallet_migration
		git-credential-oo7/${crypto}
		cargo-credential-oo7/${crypto}
	)
	if use daemon; then
		myfeatures+=(
			oo7-daemon/${crypto}
			oo7-daemon/kwallet_migration
		)
	fi
	use portal && myfeatures+=( oo7-portal/${crypto} )

	cargo_src_configure --no-default-features
}

src_compile() {
	local packages=(
		--package oo7-cli
		--package git-credential-oo7
		--package cargo-credential-oo7
		$(usev daemon '--package oo7-daemon')
		$(usev pam '--package oo7-pam')
		$(usev portal '--package oo7-portal')
	)

	# Path of the login helper that pam_oo7.so spawns
	local -x OO7_DAEMON_LOGIN_PATH="${EPREFIX}/usr/libexec/oo7-daemon-login"
	cargo_src_compile "${packages[@]}"

	local libexecdir="${EPREFIX}/usr/libexec"
	if use daemon; then
		_oo7_configure_file server/data/oo7-daemon.service.in \
			"${T}"/oo7-daemon.service \
			binary=oo7-daemon \
			libexecdir="${libexecdir}" \
			dbus_known_name=org.freedesktop.secrets

		# Upstream only ships a systemd unit; this D-Bus service file lets
		# the daemon start on demand without systemd too.
		cat > "${T}"/org.freedesktop.secrets.service <<-EOF || die
			[D-BUS Service]
			Name=org.freedesktop.secrets
			Exec=${libexecdir}/oo7-daemon
			SystemdService=dbus-org.freedesktop.secrets.service
		EOF
	fi

	if use portal; then
		local f portalconf=(
			bin_name=oo7-portal
			dbus_name=org.freedesktop.impl.portal.desktop.oo7
			libexecdir="${libexecdir}"
			service_name=oo7-portal
		)
		for f in oo7-portal.desktop oo7-portal.portal oo7-portal.service \
			org.freedesktop.impl.portal.desktop.oo7.service; do
			_oo7_configure_file "portal/data/${f}.in" "${T}/${f}" \
				"${portalconf[@]}"
		done
	fi
}

src_install() {
	local target=$(cargo_target_dir)

	dobin "${target}"/{oo7-cli,git-credential-oo7,cargo-credential-oo7}

	if use daemon; then
		exeinto /usr/libexec
		doexe "${target}"/{oo7-daemon,oo7-daemon-login}

		insinto /usr/share/dbus-1/services
		doins "${T}"/org.freedesktop.secrets.service

		systemd_douserunit "${T}"/oo7-daemon.service
		dosym oo7-daemon.service \
			"$(systemd_get_userunitdir)"/dbus-org.freedesktop.secrets.service
	fi

	use pam && newpammod "${target}"/libpam_oo7.so pam_oo7.so

	if use portal; then
		exeinto /usr/libexec
		doexe "${target}"/oo7-portal

		domenu "${T}"/oo7-portal.desktop
		insinto /usr/share/xdg-desktop-portal/portals
		doins "${T}"/oo7-portal.portal
		insinto /usr/share/dbus-1/services
		doins "${T}"/org.freedesktop.impl.portal.desktop.oo7.service

		systemd_douserunit "${T}"/oo7-portal.service
		dosym oo7-portal.service \
			"$(systemd_get_userunitdir)"/dbus-org.freedesktop.impl.portal.desktop.oo7.service
	fi

	dodoc README.md
	newdoc cli/README.md README.cli.md
	newdoc git-credential/README.md README.git-credential.md
	newdoc cargo-credential/README.md README.cargo-credential.md
	use daemon && newdoc server/README.md README.server.md
	use pam && newdoc pam/README.md README.pam.md
	use portal && newdoc portal/README.md README.portal.md
}

pkg_postinst() {
	if use daemon; then
		elog "oo7-daemon provides org.freedesktop.secrets and is started on"
		elog "demand over D-Bus. Under systemd you can also start it at login:"
		elog "  systemctl --user enable oo7-daemon.service"
	fi
	if use pam; then
		elog "To unlock the login keyring at login, add pam_oo7.so to your PAM"
		elog "stack; see ${EPREFIX}/usr/share/doc/${PF}/README.pam.md*"
	fi
	if use portal; then
		elog "oo7-portal.portal declares UseIn=gnome only. On other desktops, set"
		elog "  org.freedesktop.impl.portal.Secret=oo7-portal"
		elog "under [preferred] in ~/.config/xdg-desktop-portal/<desktop>-portals.conf"
	fi
}
