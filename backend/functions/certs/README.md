# Apple's root certificates

`redeemPurchase` verifies App Store purchases against Apple's root certificates. Put Apple's root certificates
here, as DER `.cer` files, before deploying: **Apple Root CA - G3** (and, to be safe, Apple Inc. Root and Apple
Root CA - G2), from <https://www.apple.com/certificateauthority/>. Without them, production and sandbox purchases
are refused ("App Store verification isn't set up"); test purchases from Xcode's StoreKit testing are accepted
only on the emulators.
