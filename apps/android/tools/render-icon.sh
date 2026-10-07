#!/bin/zsh
# Renders the Android launcher icon's foreground from the iOS app's own logo code (AqraArchLogo), on a Mac:
#
#   apps/android/tools/render-icon.sh
#
# The logo is drawn by SwiftUI exactly as on the iOS icon (mark scale 1.15), shrunk into the middle 72 of the adaptive
# icon's 108 units, and written as one PNG per screen density. The background is a vector (ic_launcher_background.xml).
set -euo pipefail
root=${0:A:h:h:h:h}
ios=$root/apps/ios/Aqra/DesignSystem
res=$root/apps/android/app/src/main/res
work=$(mktemp -d)
trap 'rm -rf $work' EXIT

{
  cat <<'SWIFT'
import SwiftUI
import AppKit

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(.sRGB, red: Double((light >> 16) & 0xFF) / 255, green: Double((light >> 8) & 0xFF) / 255,
                  blue: Double(light & 0xFF) / 255, opacity: 1)
    }
}
SWIFT
  # StarShape, from the iOS logo file.
  awk '/^\/\/\/ A star with softly rounded points./{p=1} p{print} p&&/^}$/{exit}' $ios/AqraLogo.swift
  sed -e '/^#Preview/,$d' -e '/^import SwiftUI/d' $ios/AqraArchLogo.swift
  cat <<'SWIFT'

@MainActor
func render(size: CGFloat, to path: String) {
    let logo = AqraArchLogo(withBackground: false, markScale: 1.15 * 72 / 108)
    let renderer = ImageRenderer(content: logo.frame(width: 1024, height: 1024).scaleEffect(size / 1024).frame(width: size, height: size))
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("Couldn't render \(path)") }
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let res = CommandLine.arguments[1]
MainActor.assumeIsolated {
    for (density, size) in [("mdpi", 108.0), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)] {
        render(size: size, to: "\(res)/mipmap-\(density)/ic_launcher_foreground.png")
    }
}
SWIFT
} > $work/icon.swift

swiftc -O $work/icon.swift -o $work/icon
for density in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  mkdir -p $res/mipmap-$density
  rm -f $res/mipmap-$density/ic_launcher_foreground.webp
done
$work/icon $res
echo "Wrote the launcher icon's foreground to $res/mipmap-*/"
