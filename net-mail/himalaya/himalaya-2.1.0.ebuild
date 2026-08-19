# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	abnf-core@0.6.0
	aho-corasick@1.1.5
	allocator-api2@0.2.21
	android_system_properties@0.1.6
	anstream@1.0.0
	anstyle@1.0.14
	anstyle-parse@1.0.0
	anstyle-query@1.1.5
	anstyle-wincon@3.0.11
	anyhow@1.0.104
	ar_archive_writer@0.5.3
	ariadne@0.6.0
	autocfg@1.5.1
	aws-lc-rs@1.18.0
	aws-lc-sys@0.44.0
	base64@0.22.1
	base64@0.23.1
	bitflags@1.3.2
	bitflags@2.13.1
	block-buffer@0.12.1
	block2@0.6.2
	bounded-static@0.8.0
	bounded-static-derive@0.8.0
	bumpalo@3.20.3
	bytes@1.12.1
	cc@1.4.3
	cfg-if@1.0.4
	cfg_aliases@0.2.2
	chacha20@0.10.1
	charset@0.1.5
	chrono@0.4.45
	chumsky@0.13.0
	clap@4.6.6
	clap_builder@4.6.6
	clap_complete@4.6.9
	clap_derive@4.6.4
	clap_lex@1.1.0
	clap_mangen@0.3.3
	cmake@0.1.58
	cmov@0.5.4
	colorchoice@1.0.5
	combine@4.6.7
	comfy-table@8.0.0
	convert_case@0.10.0
	convert_case@0.11.0
	core-foundation@0.10.1
	core-foundation-sys@0.8.7
	cpufeatures@0.3.0
	crossterm@0.29.0
	crossterm_winapi@0.9.1
	crypto-common@0.2.2
	ctrlc@3.5.2
	ctutils@0.4.2
	defmt@1.1.1
	defmt-macros@1.1.1
	defmt-parser@1.0.0
	derive_more@2.1.1
	derive_more-impl@2.1.1
	digest@0.11.3
	dirs@6.0.0
	dirs-sys@0.5.0
	dispatch2@0.3.1
	displaydoc@0.2.7
	document-features@0.2.12
	domain@0.12.2
	domain-macros@0.12.2
	dunce@1.0.5
	dyn-clone@1.0.20
	encoding_rs@0.8.35
	env_filter@2.0.0
	env_logger@0.11.11
	equivalent@1.0.2
	errno@0.3.14
	fallible-iterator@0.3.0
	fallible-streaming-iterator@0.1.9
	fastrand@2.5.0
	find-msvc-tools@0.1.11
	foldhash@0.1.5
	foldhash@0.2.0
	foreign-types@0.3.2
	foreign-types-shared@0.1.1
	form_urlencoded@1.2.2
	fs_extra@1.3.0
	futures-core@0.3.34
	futures-task@0.3.34
	futures-util@0.3.34
	fuzzy-matcher@0.3.7
	gethostname@1.1.0
	getrandom@0.2.17
	getrandom@0.4.3
	git2@0.21.0
	hashbrown@0.15.5
	hashbrown@0.17.1
	hashify@0.2.9
	heck@0.5.0
	hmac@0.13.0
	httparse@1.10.1
	humansize@2.1.3
	hybrid-array@0.4.14
	iana-time-zone@0.1.65
	iana-time-zone-haiku@0.1.2
	icu_collections@2.3.0
	icu_locale_core@2.3.0
	icu_normalizer@2.3.0
	icu_normalizer_data@2.3.0
	icu_properties@2.3.0
	icu_properties_data@2.3.0
	icu_provider@2.3.0
	idna@1.1.0
	idna_adapter@1.2.2
	imap-codec@2.0.0-alpha.9
	imap-types@2.0.0-alpha.7
	indexmap@2.14.0
	inquire@0.9.4
	io-gmail@0.3.0
	io-http@0.5.0
	io-imap@0.5.0
	io-jmap@0.3.0
	io-m2dir@0.2.1
	io-maildir@0.3.0
	io-msgraph@0.3.0
	io-pim-discovery@0.7.0
	io-pimdir@0.2.0
	io-proxy@0.1.0
	io-replica@0.3.0
	io-sasl@0.1.0
	io-smtp@0.3.0
	ipconfig@0.3.4
	is-docker@0.2.0
	is-wsl@0.4.0
	is_terminal_polyfill@1.70.2
	itoa@1.0.18
	jiff@0.2.35
	jiff-core@0.1.0
	jiff-static@0.2.35
	jni@0.22.4
	jni-macros@0.22.4
	jni-sys@0.4.1
	jni-sys-macros@0.4.1
	jobserver@0.1.35
	js-sys@0.3.104
	libc@0.2.189
	libgit2-sys@0.18.7+1.9.6
	libm@0.2.16
	libredox@0.1.20
	libsqlite3-sys@0.38.2
	libz-sys@1.1.29
	linux-raw-sys@0.12.1
	litemap@0.8.3
	litrs@1.0.0
	lock_api@0.4.14
	log@0.4.33
	mail-builder@0.4.4
	mail-parser@0.11.6
	memchr@2.8.3
	memoffset@0.9.1
	mime@0.3.17
	mime_guess@2.0.5
	minimal-lexical@0.2.1
	mio@1.2.2
	native-tls@0.2.18
	nix@0.31.3
	nom@7.1.3
	num-traits@0.2.19
	objc2@0.6.4
	objc2-encode@4.1.0
	object@0.39.1
	octseq@0.6.1
	once_cell@1.21.4
	once_cell_polyfill@1.70.2
	open@5.4.1
	openssl@0.10.81
	openssl-macros@0.1.1
	openssl-probe@0.2.1
	openssl-src@300.6.1+3.6.3
	openssl-sys@0.9.117
	option-ext@0.2.0
	parking_lot@0.12.5
	parking_lot_core@0.9.12
	pbkdf2@0.13.0
	percent-encoding@2.3.2
	pimalaya-cli@0.2.2
	pimalaya-config@0.1.4
	pimalaya-stream@0.3.0
	pin-project-lite@0.2.17
	pkg-config@0.3.34
	portable-atomic@1.15.0
	portable-atomic-util@0.2.7
	potential_utf@0.1.6
	proc-macro2@1.0.107
	psm@0.1.32
	quote@1.0.47
	quoted_printable@0.5.2
	r-efi@6.0.0
	rand@0.10.2
	rand_core@0.10.1
	redox_syscall@0.5.18
	redox_users@0.5.2
	ref-cast@1.0.26
	ref-cast-impl@1.0.26
	regex@1.13.1
	regex-automata@0.4.18
	regex-syntax@0.8.11
	resolv-conf@0.7.6
	rfc2047-decoder@1.1.2
	ring@0.17.14
	roff@1.1.1
	rusqlite@0.40.2
	rustc_version@0.4.1
	rustix@1.1.4
	rustls@0.23.43
	rustls-native-certs@0.8.4
	rustls-pki-types@1.15.1
	rustls-platform-verifier@0.7.0
	rustls-platform-verifier-android@0.1.1
	rustls-webpki@0.103.14
	rustversion@1.0.23
	same-file@1.0.6
	schannel@0.1.29
	schemars@1.2.2
	schemars_derive@1.2.2
	scopeguard@1.2.0
	secrecy@0.10.3
	security-framework@3.7.0
	security-framework-sys@2.17.0
	semver@1.0.28
	serde@1.0.229
	serde-xml-rs@0.8.2
	serde_core@1.0.229
	serde_derive@1.0.229
	serde_derive_internals@0.30.0
	serde_json@1.0.151
	serde_spanned@1.1.1
	serde_variant@0.1.3
	sha2@0.11.0
	shellexpand@3.1.2
	shlex@2.0.1
	signal-hook@0.3.18
	signal-hook-mio@0.2.5
	signal-hook-registry@1.4.8
	simd_cesu8@1.2.0
	simdutf8@0.1.5
	slab@0.4.12
	smallvec@1.15.2
	socket2@0.6.5
	stable_deref_trait@1.2.1
	stacker@0.1.25
	strsim@0.11.1
	subtle@2.6.1
	syn@2.0.119
	syn@3.0.3
	synstructure@0.13.2
	tempfile@3.27.0
	terminal_size@0.4.4
	thiserror@2.0.20
	thiserror-impl@2.0.20
	thread_local@1.1.10
	tinystr@0.8.4
	toml@1.1.4+spec-1.1.0
	toml_datetime@1.1.1+spec-1.1.0
	toml_parser@1.1.3+spec-1.1.0
	toml_writer@1.1.2+spec-1.1.0
	typenum@1.20.1
	uds_windows@1.2.1
	unicase@2.9.0
	unicode-ident@1.0.24
	unicode-segmentation@1.13.3
	unicode-width@0.2.2
	untrusted@0.9.0
	url@2.5.8
	utf8_iter@1.0.4
	utf8parse@0.2.2
	vcpkg@0.2.15
	walkdir@2.5.0
	wasi@0.11.1+wasi-snapshot-preview1
	wasm-bindgen@0.2.127
	wasm-bindgen-macro@0.2.127
	wasm-bindgen-macro-support@0.2.127
	wasm-bindgen-shared@0.2.127
	webpki-root-certs@1.0.9
	widestring@1.2.1
	winapi@0.3.9
	winapi-i686-pc-windows-gnu@0.4.0
	winapi-util@0.1.11
	winapi-x86_64-pc-windows-gnu@0.4.0
	windows-core@0.62.2
	windows-implement@0.60.2
	windows-interface@0.59.3
	windows-link@0.2.1
	windows-registry@0.6.1
	windows-result@0.4.1
	windows-strings@0.5.1
	windows-sys@0.52.0
	windows-sys@0.61.2
	windows-targets@0.52.6
	windows_aarch64_gnullvm@0.52.6
	windows_aarch64_msvc@0.52.6
	windows_i686_gnu@0.52.6
	windows_i686_gnullvm@0.52.6
	windows_i686_msvc@0.52.6
	windows_x86_64_gnu@0.52.6
	windows_x86_64_gnullvm@0.52.6
	windows_x86_64_msvc@0.52.6
	winnow@1.0.4
	writeable@0.6.4
	xml@1.4.0
	yansi@1.0.1
	yoke@0.8.3
	yoke-derive@0.8.2
	zerofrom@0.1.8
	zerofrom-derive@0.1.7
	zeroize@1.9.0
	zerotrie@0.2.5
	zerovec@0.11.7
	zerovec-derive@0.11.4
	zmij@1.0.23
"

RUST_MIN_VER="1.89.0"

inherit cargo

DESCRIPTION="CLI to manage emails"
HOMEPAGE="https://pimalaya.org https://github.com/pimalaya/himalaya"
SRC_URI="
	https://github.com/pimalaya/himalaya/archive/v${PV}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"

LICENSE="|| ( Apache-2.0 MIT )"
# Dependent crate licenses
LICENSE+="
	0BSD Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD CC0-1.0
	CDLA-Permissive-2.0 ISC MIT MPL-2.0 public-domain Unicode-3.0
	Unlicense ZLIB
	|| ( Apache-2.0 MIT )
"
SLOT="0"
KEYWORDS="~amd64"
# pimdir is off by default: io-pimdir hardcodes rusqlite[bundled], so enabling
# it compiles a bundled copy of SQLite instead of using dev-db/sqlite.
IUSE="+gmail +imap +jmap +m2dir maildir +msgraph pimdir +smtp native-tls rustls-aws +rustls-ring"
REQUIRED_USE="^^ ( native-tls rustls-aws rustls-ring )"

RDEPEND="
	native-tls? ( dev-libs/openssl:= )
"
DEPEND="${RDEPEND}"
# git2/libgit2-sys and libz-sys are pulled in by the pimalaya-cli "build"
# feature, which is only used from build.rs, so they are build-host only.
BDEPEND="
	dev-libs/libgit2:=
	sys-libs/zlib:=
	virtual/pkgconfig
	rustls-aws? ( dev-build/cmake )
"

QA_FLAGS_IGNORED="usr/bin/himalaya"

src_configure() {
	local myfeatures=(
		$(usev gmail)
		$(usev imap)
		$(usev jmap)
		$(usev m2dir)
		$(usev maildir)
		$(usev msgraph)
		$(usev native-tls)
		$(usev pimdir)
		$(usev rustls-aws)
		$(usev rustls-ring)
		$(usev smtp)
	)
	cargo_src_configure
}

src_install() {
	cargo_src_install
	dodoc README.md
}
