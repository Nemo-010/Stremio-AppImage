#!/bin/sh

set -eu

ARCH=$(uname -m)

# upstream only publishes a 64bit x86 deb
if [ "$ARCH" != 'x86_64' ]; then
	echo "Stremio has no $ARCH build, bailing out..."
	exit 1
fi

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
# pipewire-jack provides the libjack.so that libmpv and ffmpeg link against, it
# has to be installed first so pacman picks it instead of the jack server
pacman -Syu --noconfirm \
	curl              \
	git               \
	mpv               \
	nodejs            \
	patchelf          \
	pipewire-jack     \
	qt5-quickcontrols \
	qt5-quickcontrols2

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
# ffmpeg-mini is also the ffmpeg stremio spawns for HLS and casting
get-debloated-pkgs --add-common --prefer-nano ffmpeg-mini

echo "Installing Qt5 WebEngine and OpenSSL 1.1..."
echo "---------------------------------------------------------------"
# qt5-webengine and the qt5-webchannel and qt5-location it needs were dropped
# from the Arch repos, and the shell still links against the OpenSSL 1.1 ABI
# (OpenSSL 3 does not carry the OPENSSL_1_1_0 symbol versions it asks for)
make-aur-package --archlinuxcn openssl-1.1 qt5-webengine

echo "Getting Stremio..."
echo "---------------------------------------------------------------"
# the deb linked from the official downloads page is the build upstream ships
# to Linux users, there is no API or feed that lists the shell releases
DEB_LINK=$(curl -sSfL --retry 5 https://www.stremio.com/downloads |
	grep -oE 'https://dl\.strem\.io/shell-linux/v[0-9.]+/stremio_[0-9.]+-1_amd64\.deb' |
	head -n 1) || :

if [ -z "${DEB_LINK-}" ]; then
	# if the page ever changes, walk the release tags and use the newest one
	# that actually has a published deb
	echo "No deb found in the downloads page, checking the release tags..."
	for v in $(git ls-remote --tags --refs https://github.com/Stremio/stremio-shell.git |
		awk -F/ '{print $NF}' | sed 's/^v\.\?//' | sort -rV); do
		link="https://dl.strem.io/shell-linux/v$v/stremio_$v-1_amd64.deb"
		if curl -sSfI -o /dev/null "$link"; then
			DEB_LINK=$link
			break
		fi
	done
fi

if [ -z "${DEB_LINK-}" ]; then
	echo "ERROR: could not find a published Stremio deb!"
	exit 1
fi

echo "Downloading $DEB_LINK"
curl -sSfL --retry 30 --retry-connrefused "$DEB_LINK" -o /tmp/stremio.deb

CONTROL=$(bsdtar -tf /tmp/stremio.deb | grep -E '^control\.tar')
DATA=$(bsdtar -tf /tmp/stremio.deb | grep -E '^data\.tar')

# the version declared inside the deb is the authoritative one
bsdtar -xOf /tmp/stremio.deb "$CONTROL" |
	bsdtar -xOf - ./control |
	awk -F': ' '/^Version:/{print $2; exit}' |
	cut -d- -f1 > ~/version

echo "Stremio version: $(cat ~/version)"

echo "Preparing AppDir..."
echo "---------------------------------------------------------------"
mkdir -p ./AppDir/bin
# ./opt/stremio/* -> ./AppDir/bin
bsdtar -xOf /tmp/stremio.deb "$DATA" |
	bsdtar -xf - --strip-components=3 -C ./AppDir/bin/

# this is a symlink to /usr/bin/node, which does not exist inside an AppImage,
# the real node binary is deployed by quick-sharun instead
rm -f ./AppDir/bin/node

# the shell links against the libmpv 1 ABI, the client API it uses did not
# change in libmpv 2, so pointing it at the soname Arch ships is enough
if patchelf --print-needed ./AppDir/bin/stremio | grep -qx 'libmpv\.so\.1'; then
	patchelf --replace-needed libmpv.so.1 libmpv.so.2 ./AppDir/bin/stremio
fi

# stremio's own updater downloads and runs the upstream AppImage when it sees
# that it runs from /tmp/.mount_*, which is exactly where uruntime mounts this
# AppImage. Updates are handled by quick-sharun's self-updater instead.
# NOTE: the replacement has to be the same length, otherwise the rest of the
# file shifts and the ELF is corrupted
if grep -aq -m 1 '/tmp/\.mount_' ./AppDir/bin/stremio; then
	sed -i -e 's|/tmp/\.mount_|/nonexistent|' ./AppDir/bin/stremio
fi

# the desktop entry and the window and tray icons are looked up by name from
# the icon theme, they are named <app>_<size>.png inside the deb
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
