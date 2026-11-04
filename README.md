# KeyDoubler

A native macOS (SwiftUI) app that creates 3D models (STL) of **your own keys** with an illustrated step-by-step wizard.
KeyDoubler is based on [AutoKey3D](https://github.com/choller/autokey3d) by Christian Holler (:decoder). It is an
independent port and not affiliated with that project. No OpenSCAD, Python, Inkscape or pstoedit required: the
geometry is computed in Swift.

## Features
- Step-by-step wizard: profile, measurements, cut depths, 3D preview, STL export, print tips
- Measure a key from one photo with a coin as size reference: length, height, shoulder, pin spacing and cut depths
- Key detection with Apple's Vision framework (macOS 14+), with a manual threshold as fallback
- Profile from a photo of the key's end face (contour detection) or SVG import
- Built-in profiles and lock-system definitions from the original project; add your own
- Saved keys, 3D preview (SceneKit), binary STL export
- "Expert" mode with all options on one screen

## Not (yet) supported
- Embossed branding text on the handle
- Dimple-key systems (e.g. AB-EC)
- Profile isolation from raw photos with GrabCut (`--isolate` in the original)
- Blade thickness cannot be seen in a photo from above: measure it with a caliper.
- Cut step, angle and plateau are estimates when measured from a photo.
- Results have not been compared against OpenSCAD output; always test-fit prints.

## Build
Requires macOS 13+ and Xcode / Swift 5.9+.

```bash
./build_app.sh            # builds build/KeyDoubler.app (ad-hoc signed)
./build_app.sh --install  # additionally copies it to /Applications
```

The app is ad-hoc signed, so on first launch use right-click → Open.

## License
Licensed under **CC BY-NC-SA 4.0** like AutoKey3D, on which it is based: non-commercial, attribution, share-alike. See `LICENSE`.
Profile and definition data in `data/` come from the original project (© Christian Holler).
The BSP-based CSG code is a port of the algorithm from csg.js (MIT, Evan Wallace).
Use only for keys you are entitled to copy.
