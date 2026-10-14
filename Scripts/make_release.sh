#!/bin/zsh
# 打包一个签名并公证的 DMG：Developer ID 签名 → 公证 → 把票据钉进 App 和 DMG。
#
# 需要：钥匙串里的 “Developer ID Application” 证书，以及 App Store Connect API 密钥：
#   NOTARY_KEY=/path/AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER=uuid Scripts/make_release.sh
# 产物：build/Dist/HangDry-<版本>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

: "${NOTARY_KEY:?需要 NOTARY_KEY（.p8 路径）}" "${NOTARY_KEY_ID:?需要 NOTARY_KEY_ID}" "${NOTARY_ISSUER:?需要 NOTARY_ISSUER}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
TEAM=$(security find-certificate -c "$IDENTITY" -p | openssl x509 -noout -subject | sed -E 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/')

xcodegen generate
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO：不加调试用的 get-task-allow，否则公证会被拒
xcodebuild -project HangDry.xcodeproj -scheme HangDry -configuration Release -derivedDataPath build/DistData clean build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" ENABLE_HARDENED_RUNTIME=YES

APP=build/DistData/Build/Products/Release/HangDry.app
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
DMG="build/Dist/HangDry-$VERSION.dmg"

notarize() {
  xcrun notarytool submit "$1" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  xcrun stapler staple "$1"
}

make_dmg() {
  /bin/rm -rf build/Dist
  mkdir -p build/Dist/stage
  ditto "$APP" build/Dist/stage/HangDry.app
  ln -s /Applications build/Dist/stage/Applications
  hdiutil create -volname "HangDry $VERSION" -srcfolder build/Dist/stage -ov -format UDZO -fs HFS+ "$DMG"
  codesign --sign "$IDENTITY" --timestamp "$DMG"
}

# 先公证一次拿到 App 的票据并钉进 App（离线首次打开也不会被拦），再用钉好的 App 打最终的 DMG 并公证
make_dmg && notarize "$DMG"
xcrun stapler staple "$APP"
make_dmg && notarize "$DMG"

spctl -a -t open --context context:primary-signature -v "$DMG"
shasum -a 256 "$DMG"
