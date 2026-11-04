# AutoKey3D for macOS

A native macOS (SwiftUI) port of [AutoKey3D](https://github.com/choller/autokey3d) by Christian Holler (:decoder).
It creates 3D models (STL) of key blanks, bump keys and regular keys for **your own keys**, with an illustrated
step-by-step wizard. No OpenSCAD, Python, Inkscape or pstoedit required: the geometry is computed in Swift.

## Features
- Step-by-step wizard: photo of the key tip → profile, measurements, cut depths, 3D preview, STL export, print tips
- Profile from an iPhone photo (contour detection) or SVG import
- Built-in profiles and lock-system definitions from the original project; add your own
- Saved keys, 3D preview (SceneKit), binary STL export
- "Expert" mode with all options on one screen

## Not (yet) supported
- Embossed branding text on the handle
- Dimple-key systems (e.g. AB-EC)
- Profile isolation from raw photos with GrabCut (`--isolate` in the original)
- Results have not been compared against OpenSCAD output; always test-fit prints.

## Build
Requires macOS 13+ and Xcode / Swift 5.9+.

```bash
./build_app.sh            # builds build/AutoKey3D.app (ad-hoc signed)
./build_app.sh --install  # additionally copies it to /Applications
```

The app is ad-hoc signed, so on first launch use right-click → Open.

## License
Licensed under **CC BY-NC-SA 4.0** like the original: non-commercial, attribution, share-alike. See `LICENSE`.
Profile and definition data in `data/` come from the original project (© Christian Holler).
The BSP-based CSG code is a port of the algorithm from csg.js (MIT, Evan Wallace).
Use only for keys you are entitled to copy.
