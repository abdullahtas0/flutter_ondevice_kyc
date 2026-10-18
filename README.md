# flutter_ondevice_kyc

On-device KYC for an identity-card MRZ and a payment-card number. The scan path does not open a socket and does not write the frame.

A frame is published only when ICAO 9303 or Luhn accepts it. A miss is a rejected frame, not an exception. The name line has no check digit. The green lock waits on the document number, dates, and composite digit.

The code is [MIT](LICENSE). The detector is YOLOX-Nano and the recognizer is the official `en_PP-OCRv4_mobile_rec`. Both weights are Apache-2.0. This version has no CVV, NFC, or face match.

Turkish process notes: [doc/on-device-kyc.tr.md](doc/on-device-kyc.tr.md).

## What it reads

| Document | Shape | Gate |
| --- | --- | --- |
| Identity card back, including the Turkish card | TD1, 3×30 | ICAO check digits. An 11-digit run in the optional data must also pass the TCKN test |
| Passport | TD3, 2×44 | ICAO check digits |
| Older booklet | TD2, 2×36 | ICAO check digits |
| Payment card | 13–19 digits | Luhn. The CVV is not read |

Names come out in MRZ Latin. Turkish dotted letters are not in those lines.

The detector was fine-tuned on synthetic rectangles. A real card is still read when the MRZ lines sit in the frame. This repository does not contain photographs of real identity documents.

## Pipeline

```mermaid
flowchart TD
  camera[Camera frame]
  focus[Focus the MRZ band, then lock]
  throttle[At most 5 fps]
  orient[Rotate upright and crop the guide]
  detect[YOLOX-Nano ONNX]
  warp[Homography]
  lines[Split MRZ lines]
  ocr[PP-OCRv4 per line]
  gate[ICAO 9303, TCKN, or Luhn]
  emit[KycCapture]
  camera --> focus --> throttle --> orient --> detect --> warp --> lines --> ocr --> gate
  gate -->|accepts| emit
  gate -->|rejects| throttle
```

Runtime is `flutter_onnxruntime` 1.9. The default provider is CPU. XNNPACK and CoreML are opt-in through `KycExecutionProvider`. NNAPI is not a default: it is slow on these small graphs and it is deprecated on Android 15.

## Run

Flutter 3.24 or newer. The example ships its models in `example/assets/models/`.

```bash
flutter pub get
flutter test
cd example
flutter pub get
flutter test
flutter run
```

The scan tab opens the back camera, focuses the three marks at the bottom of the guide, and locks focus. Tap the image to focus again. The validation tab locks pasted text. That lock did not come from a document.

Android release builds use R8. `example/android/app/proguard-rules.pro` keeps the ONNX Runtime classes. Without that keep rule, `OrtSession.run` aborts the process in a minified build.

## API

```dart
final scanner = await KycScanner.onnx();
final decision = await scanner.scanStill(image);
if (decision is ScanLocked) {
  final capture = decision.capture;
}
await scanner.dispose();
```

`KycScanner.fixture()` locks the ICAO specimen when the weight files are absent. `ScanRejected` is not an exception. `checkManual` is for pasted text. `redactPan` is for logs. The full number lives on `KycCapture.cardNumber`, and the host should not store it.

## Models

Weights live in `example/assets/models/`. Digests are in [assets/models/README.md](assets/models/README.md).

| File | Source | Size |
| --- | --- | --- |
| `card_detector.onnx` | YOLOX-Nano, 3 classes, 416, FP32 | 8.6 MB |
| `text_rec.onnx` | `en_PP-OCRv4_mobile_rec`, opset 11, FP32 | 7.3 MB |
| `en_dict.txt` | PaddleOCR English dictionary, including `<` | 190 B |

Training scripts are in `training/`. Checkpoints and generated images stay out of git. Detector INT8 is only worth doing with a calibration set that keeps detection quality. The recognizer stayed FP32.

## Privacy

`lib/` does not import `dart:io` or an HTTP client. A frame stays in memory. Logs do not contain a PAN, an MRZ line, or a TCKN. The example Android manifest has no internet permission. This is not a legal opinion. It states that the scan path does not open a network connection and does not write an image.

## Versions and contributions

Versioning is in [VERSIONING.md](VERSIONING.md). Contributions are in [CONTRIBUTING.md](CONTRIBUTING.md). A pull request must name an open issue that a maintainer has labeled `accepted`. Other pull requests are closed.
