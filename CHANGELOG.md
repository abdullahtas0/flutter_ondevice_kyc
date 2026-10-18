## 1.0.0

- `KycScanView` is the scan surface a host app embeds. It opens the back camera, keeps the preview aspect, draws the card guide and MRZ lane, and locks focus on that lane.
- Model files are host assets. `KycScanner.onnx` and `KycScanner.detectorOnly` require the detector, recognizer, and dictionary paths. This package does not ship the weights.
- The Android plugin merges `CAMERA` and a consumer R8 keep rule for `ai.onnxruntime.**` into the host release build.
- The public library exports the integration surface. Pipeline helpers stay under `lib/src`.

## 0.1.0

- On-device scan path for ICAO TD1, TD2, and TD3, including TCKN when it appears in the MRZ.
- Luhn and expiry checks for card numbers. A checksum miss is a rejected frame, not an exception.
- YOLOX-Nano detector and PP-OCRv4 English recognizer through `flutter_onnxruntime`.
- Camera preview keeps its aspect, focuses the MRZ band, and reads each MRZ line on its own.
- Example Android release build keeps the ONNX Runtime classes for R8.
