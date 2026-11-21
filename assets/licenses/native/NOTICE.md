# Tag Music native audio components

The original Tag Music application code is licensed under 0BSD.
The bundled audio binaries are subject to the licenses listed below.

Windows: media_kit_libs_windows_audio 1.0.9 downloads
mpv-dev-x86_64-20230924-git-652a1dd.7z from:
https://github.com/media-kit/libmpv-win32-audio-build/releases/tag/2023-09-24
Runtime: mpv v0.36.0-403-g652a1dd907; FFmpeg n6.0.
The actual DLL reports -Dgpl=false and FFmpeg --disable-gpl
--disable-nonfree --enable-version3; FFmpeg reports LGPL version 3 or later.
mpv source: https://github.com/mpv-player/mpv/tree/652a1dd90711839acdccc08004056d25514ef2d8
FFmpeg source: https://github.com/FFmpeg/FFmpeg/tree/n6.0
Build scripts: https://github.com/media-kit/libmpv-win32-audio-build

Android: media_kit_libs_android_audio 1.3.8 downloads the default flavor v1.1.8:
https://github.com/media-kit/libmpv-android-audio-build/releases/tag/v1.1.8
Build source: https://github.com/media-kit/libmpv-android-audio-build/tree/87744be8b337c50ed54961249b7a97c5e8cc37c9
The build specifies mpv 0.35.1 (--enable-lgpl), FFmpeg 6.0
(--disable-gpl --disable-nonfree --enable-version3), mbedTLS 3.6.1,
and libxml2 2.10.3. The LGPL version 3 or later applies to FFmpeg.
mpv source: https://github.com/mpv-player/mpv/tree/v0.35.1
mbedTLS source: https://github.com/Mbed-TLS/mbedtls/tree/v3.6.1
libxml2 source: https://gitlab.gnome.org/GNOME/libxml2/-/tree/v2.10.3
Android helper: https://github.com/media-kit/media-kit-android-helper

Included license texts: LGPL-2.1.txt, LGPL-3.0.txt, GPL-3.0.txt (referenced by
LGPL-3.0), mpv-Copyright.txt, FFmpeg-LICENSE.md, mbedTLS-LICENSE.txt and
libxml2-Copyright.txt. Licenses and copyright notices in individual source
files also apply. Upstream patches and build flags are in the build repositories.

R1 is a local technical-validation build. Full corresponding-source capture
for the historical Windows static dependencies remains a release audit item;
the historical release tag contains only a version file. The current repository
branch alone is not proof of the exact historical build source. See
docs/THIRD_PARTY.md for the audit evidence and remaining limitations.

The application does not prohibit reverse engineering needed to debug changes
to LGPL components. No DRM or anti-tamper restriction is added for these libraries.
