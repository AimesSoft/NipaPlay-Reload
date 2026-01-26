EAPI=8
inherit desktop xdg unpacker
DESCRIPTION="NipaPlay-Reload 是一个现代化的跨平台本地视频播放器，支持 Windows、macOS、Linux、Android 和 iOS。集成了弹幕显示、多格式字幕支持、多音频轨道切换，新番查看等功能，支持挂载Emby/Jellyfin媒体库。采用 Flutter 开发，提供统一的用户体验。"

HOMEPAGE="https://github.com/MCDFsteve/NipaPlay-Reload
	https://nipaplay.aimes-soft.com/"
MYPN="nipaplay"
SRC_URI="https://github.com/MCDFsteve/NipaPlay-Reload/releases/download/v${PV}/NipaPlay-${PV}-Linux-amd64.deb -> ${MYPN}.deb"
LICENSE="MIT"
KEYWORDS="~amd64"
SLOT="0"
RESTRICT="mirror strip"

S="${WORKDIR}"
IUSE=""
DEPEND=""
RDEPEND="
	media-video/ffmpeg
	media-video/mpv
	>=x11-libs/gtk+-3.0:3
	x11-libs/pango
	dev-libs/keybinder
	media-libs/libass
"

pkg_pretend() {
	use amd64 || die "only works on amd64"
}

src_unpack() {
	unpack_deb ${DISTDIR}/${MYPN}.deb
}

src_install() {
	local install_dir="/opt/${MYPN}"
	local bin_dir="${install_dir}/NipaPlay"
	insinto "${install_dir}"
	doins -r opt/${MYPN}/*
	fperms +x "${bin_dir}"
	dosym "${bin_dir}" /usr/bin/NipaPlay
	domenu usr/share/applications/io.github.MCDFsteve.NipaPlay-Reload.desktop
	doicon -s 512 usr/share/icons/hicolor/512x512/apps/io.github.MCDFsteve.NipaPlay-Reload.png
}

pkg_postinst() {
	xdg_icon_cache_update
	xdg_desktop_database_update
	xdg_mimeinfo_database_update

}

pkg_postrm() {
	xdg_icon_cache_update
	xdg_desktop_database_update
	xdg_mimeinfo_database_update

}
