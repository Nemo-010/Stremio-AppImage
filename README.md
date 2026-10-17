<div align="center">

# Stremio AppImage 🐧

[![GitHub Downloads](https://img.shields.io/github/downloads/nubesurrealista/Stremio-AppImage/total?logo=github&label=GitHub%20Downloads)](https://github.com/nubesurrealista/Stremio-AppImage/releases/latest)
[![CI Build Status](https://img.shields.io/github/actions/workflow/status/nubesurrealista/Stremio-AppImage/appimage.yml?label=CI%20Build)](https://github.com/nubesurrealista/Stremio-AppImage/actions/workflows/appimage.yml)
[![Latest Stable Release](https://img.shields.io/github/v/release/nubesurrealista/Stremio-AppImage)](https://github.com/nubesurrealista/Stremio-AppImage/releases/latest)

<p align="center">
  <img src="https://raw.githubusercontent.com/Stremio/stremio-web/development/assets/images/icon_512x512.png" width="128" />
</p>

| Latest Stable Release | Upstream URL |
| :---: | :---: |
| [Click here](https://github.com/nubesurrealista/Stremio-AppImage/releases/latest) | [Click here](https://www.stremio.com/) |

</div>

---

AppImage made using [quick-sharun](https://github.com/pkgforge-dev/Anylinux-AppImages/blob/main/useful-tools/quick-sharun.sh), which makes it extremely easy to turn any binary into a portable package reliably without using containers or similar tricks.

**This AppImage bundles everything and it should work on any Linux distro, including old and musl-based ones.**

This AppImage doesn't require FUSE to run at all, thanks to the [uruntime](https://github.com/VHSgunzo/uruntime).

This AppImage is also supplied with a self-updater by default, so any updates to this application won't be missed, you will be prompted for permission to check for updates and if you are then notified when a new update is available.

Self-updater is disabled by default if AppImage managers like [am](https://github.com/ivan-hc/AM), [soar](https://github.com/pkgforge/soar) or [dbin](https://github.com/xplshn/dbin) exist, which manage AppImage updates.

---

## How this is packaged

Upstream does not publish a tarball or a standalone binary for Linux, only a
`.deb` built around a Qt5 shell, a bundled `server.js` and a `node` symlink.
Building the shell from source is not an option here, so the deb is unpacked
and repackaged:

- **Version tracking** - there is no release feed for the Linux shell, so the
  deb is taken from the link on the official downloads page, and the version is
  read back out of the deb's own control file rather than parsed from the URL.
  If the page ever stops exposing it, the release tags on
  [stremio-shell](https://github.com/Stremio/stremio-shell) are walked instead.
- **`libmpv1` → `libmpv2`** - the shell links against `libmpv.so.1`, which no
  longer exists anywhere, `patchelf --replace-needed` points it at the
  `libmpv.so.2` Arch ships. The mpv client API used here did not change.
- **`node`** - the deb ships a symlink to `/usr/bin/node`, which is useless
  inside an AppImage, so the real node binary is deployed next to `server.js`.
- **upstream self-updater** - the shell replaces itself with the upstream
  AppImage when it detects that it runs from `/tmp/.mount_*`, which is exactly
  where uruntime mounts this AppImage. That path is neutralized and updates go
  through quick-sharun's self-updater instead.
- **Qt5 WebEngine** - `qt5-webengine`, `qt5-webchannel` and `qt5-location` are
  no longer in the Arch repos, and OpenSSL 1.1 is needed for the
  `OPENSSL_1_1_0` symbols the shell imports, so both come from archlinuxcn.

Only `x86_64` is built, because that is the only architecture upstream ships.

---

More at: [AnyLinux-AppImages](https://pkgforge-dev.github.io/Anylinux-AppImages/)
