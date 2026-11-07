#!/bin/sh
set -eu
: "${APELIN_PACKAGE_DIR:?run this through apelin_project_build}"
: "${APELIN_PROJECT_ROOT:?}" "${APELIN_BOOTSTRAP:?}" "${APELIN_ARCHITECTURE:?}"
: "${APELIN_BUILD_ID:?}" "${TMPDIR:?}"
: "${APELIN_PREFIX?}" # set, and empty on roothide
stage="$(mktemp -d "${TMPDIR:?}stage.XXXXXX")"
trap 'rm -rf -- "${stage:?}"' EXIT

cd "${APELIN_PROJECT_ROOT:?}"

APP_NAME="ExifOne"
BUNDLE_ID="com.melon.exifone"
PKG_ID="com.melon.exifone"
VERSION="1.0.1"

if [ "${APELIN_BOOTSTRAP}" = "roothide" ]; then
    DEFS="-DAPELIN_BOOTSTRAP_ROOTHIDE=1"
    ARCHS="arm64e"
else
    DEFS="-DAPELIN_BOOTSTRAP_ROOTLESS=1"
    ARCHS="arm64 arm64e"
fi

mkdir -p "${stage:?}/bin"
bins=""
for arch in ${ARCHS}; do
    out="${stage:?}/bin/ExifOne-${arch}"
    clang -arch "${arch}" -O2 -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
        -miphoneos-version-min=16.0 ${DEFS} -ISources \
        -DAPELIN_PACKAGE_ID="\"${PKG_ID}\"" \
        Sources/main.m Sources/EXAppDelegate.m Sources/EXRootViewController.m \
        Sources/EXDevice.m Sources/EXMetadata.m Sources/EXEnhancer.m \
        -o "${out}" \
        -framework UIKit -framework Foundation -framework PhotosUI -framework Photos \
        -framework ImageIO -framework CoreLocation -framework CoreGraphics -framework CoreImage \
        -framework UniformTypeIdentifiers
    bins="${bins} ${out}"
done

app="${stage:?}/app/${APP_NAME}.app"
mkdir -p "${app:?}"
# shellcheck disable=SC2086
lipo -create ${bins} -output "${app:?}/${APP_NAME}"
chmod 0755 "${app:?}/${APP_NAME}"

sed -e "s|__BUNDLE_ID__|${BUNDLE_ID}|g" -e "s|__VERSION__|${VERSION}|g" \
    Resources/Info.plist > "${app:?}/Info.plist"
printf 'APPL????' > "${app:?}/PkgInfo"
cp Resources/Icon-120.png "${app:?}/Icon-60@2x.png"
cp Resources/Icon-180.png "${app:?}/Icon-60@3x.png"
cp Resources/Icon-152.png "${app:?}/Icon-76@2x.png"
cp Resources/Icon-167.png "${app:?}/Icon-83.5@2x.png"
chmod 0644 "${app:?}/Info.plist" "${app:?}/PkgInfo" "${app:?}"/Icon-*.png

ldid -S"${APELIN_PROJECT_ROOT:?}/apelin/App.entitlements" "${app:?}/${APP_NAME}"

pkg="${stage:?}/pkg"
mkdir -p "${pkg:?}${APELIN_PREFIX}/Applications" "${pkg:?}/DEBIAN"
cp -R "${app:?}" "${pkg:?}${APELIN_PREFIX}/Applications/${APP_NAME}.app"

cat > "${pkg:?}/DEBIAN/control" <<EOF
Package: ${PKG_ID}
Version: ${VERSION}
Architecture: ${APELIN_ARCHITECTURE}
Name: jexi
Author: xiaolvmao
Maintainer: xiaolvmao <849477678@qq.com>
Section: Applications
Description: 把照片的 EXIF 换成设备真实数据（机型、系统版本、时间与时区、
 真实或附近随机定位、随机的镜头与曝光参数），支持批量、超清增强、
 HEIF/JPEG 输出、自定义文件名与 GPS 清除。另存为新照片，原图不动。
EOF

dpkg-deb -b --root-owner-group "${pkg:?}" "${APELIN_PACKAGE_DIR:?}/"
