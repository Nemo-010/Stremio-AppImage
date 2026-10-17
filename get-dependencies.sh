#!/bin/sh

set -eu

ARCH=$(uname -m)

# upstream only publishes a 64bit x86 deb, and the shell is only built for it
if [ "$ARCH" != 'x86_64' ]; then
	echo "Stremio has no $ARCH build, bailing out..."
	exit 1
fi

SHELL_REPO=https://github.com/Stremio/stremio-shell.git
BUILD_DIR=$PWD/build

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
# pipewire-jack provides the libjack.so that libmpv links against, it has to be
# installed first so pacman picks it instead of the jack server
pacman -Syu --noconfirm \
	cmake             \
	curl              \
	gcc               \
	git               \
	librsvg           \
	make              \
	mpv               \
	nodejs            \
	patchelf          \
	pipewire-jack     \
	qt5-base          \
	qt5-declarative   \
	qt5-quickcontrols \
	qt5-quickcontrols2

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano ffmpeg-mini

echo "Installing Qt5 WebEngine..."
echo "---------------------------------------------------------------"
# qt5-webengine and the qt5-webchannel and qt5-location it needs were dropped
# from the Arch repos, the archlinuxcn build is compiled against the qt5-base
# Arch ships so it is a drop in replacement
make-aur-package --archlinuxcn qt5-webengine

echo "Finding the latest shell version..."
echo "---------------------------------------------------------------"
# the shell is versioned by its git tags, this is the only place the version
# exists as a number that can be discovered without scraping a web page
# the tags also contain a few branches of work in progress like -qt6, which
# is why only plain dotted numbers are considered
# a tag on its own does not mean the version was released, so the tag is only
# accepted once upstream has published the matching deb for it, otherwise we
# would be packaging a commit nobody can install
LATEST_VERSION=
for v in $(git ls-remote --tags --refs "$SHELL_REPO" |
	awk -F/ '{print $NF}' |
	sed -e 's|^v\.\?||' |
	grep -E '^[0-9]+(\.[0-9]+)+$' |
	sort -rV); do
	if curl -sSfI -o /dev/null \
		"https://dl.strem.io/shell-linux/v$v/stremio_$v-1_amd64.deb"; then
		LATEST_VERSION=$v
		break
	fi
done

if [ -z "$LATEST_VERSION" ]; then
	echo "ERROR: could not find a released shell version!"
	exit 1
fi

VERSION=$LATEST_VERSION
echo "Stremio version: $VERSION"
echo "$VERSION" > ~/version

echo "Getting the shell sources..."
echo "---------------------------------------------------------------"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
git clone --depth 1 --branch "v$VERSION" "$SHELL_REPO" "$BUILD_DIR/shell"

# the shell vendors the mpv headers and SingleApplication as submodules, the
# upstream URLs are used as is, there is nothing to substitute
git -C "$BUILD_DIR/shell" submodule update --init --depth 1 deps/libmpv deps/singleapplication

echo "Getting the streaming server..."
echo "---------------------------------------------------------------"
# the shell does not contain server.js, the URL is pinned per shell tag in
# server-url.txt, so the version of the server always matches the shell
# without having to guess a version number for it
SERVER_URL=$(cat "$BUILD_DIR/shell/server-url.txt")
echo "Downloading $SERVER_URL"
curl -sSfL --retry 30 --retry-connrefused "$SERVER_URL" -o "$BUILD_DIR/shell/server.js"

echo "Building the shell..."
echo "---------------------------------------------------------------"
mkdir -p "$BUILD_DIR/build"
(
	cd "$BUILD_DIR/build"
	cmake -G "Unix Makefiles" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$BUILD_DIR/staging" \
		"$BUILD_DIR/shell"
	make -j"$(nproc)"
	make install
)

# cmake only installs the binary itself, the streaming server, the desktop
# entry and the icons are added by the shell's release.makefile, which we do
# not use because it would download server.js behind our back
STAGING=$BUILD_DIR/staging/opt/stremio
install -Dm 644 "$BUILD_DIR/shell/server.js" "$STAGING/server.js"
install -Dm 644 "$BUILD_DIR/shell/smartcode-stremio.desktop" "$STAGING/smartcode-stremio.desktop"
mkdir -p "$STAGING/icons"
for s in 16 22 24 32 64 128; do
	rsvg-convert "$BUILD_DIR/shell/images/stremio.svg" \
		-w "$s" -o "$STAGING/icons/smartcode-stremio_$s.png"
	rsvg-convert "$BUILD_DIR/shell/images/stremio_tray_white.svg" \
		-w "$s" -o "$STAGING/icons/smartcode-stremio-tray_$s.png"
done

echo "Preparing AppDir..."
echo "---------------------------------------------------------------"
mkdir -p ./AppDir/bin
# ./opt/stremio/* -> ./AppDir/bin
cp -r "$BUILD_DIR"/staging/opt/stremio/. ./AppDir/bin/

# make install links node to the host /usr/bin/node, which does not exist
# inside an AppImage, the real node binary is deployed by quick-sharun
rm -f ./AppDir/bin/node

# stremio's own updater downloads and runs the upstream AppImage when it sees
# that it runs from /tmp/.mount_*, which is exactly where uruntime mounts this
# AppImage. Updates are handled by quick-sharun's self-updater instead.
# NOTE: the replacement has to be the same length, otherwise the rest of the
# file shifts and the ELF is corrupted
if grep -aq -m 1 '/tmp/\.mount_' ./AppDir/bin/stremio; then
	sed -i -e 's|/tmp/\.mount_|/nonexistent|' ./AppDir/bin/stremio
fi

# the desktop entry and the window and tray icons are looked up by name from
# the icon theme, make install generates them as <app>_<size>.png
cp -v ./AppDir/bin/smartcode-stremio.desktop ./AppDir
rm -f ./AppDir/bin/smartcode-stremio.desktop

for f in ./AppDir/bin/icons/*.png; do
	name=${f##*/}
	name=${name%.png}
	size=${name##*_}
	name=${name%_*}
	mkdir -p ./AppDir/share/icons/hicolor/"${size}x${size}"/apps
	cp -v "$f" ./AppDir/share/icons/hicolor/"${size}x${size}"/apps/"$name".png
done
rm -rf ./AppDir/bin/icons
