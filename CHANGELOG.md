## 0.1.0

- On-device scan path for ICAO TD1, TD2, and TD3, including TCKN when it appears in the MRZ.
- Luhn and expiry checks for card numbers. A checksum miss is a rejected frame, not an exception.
- YOLOX-Nano detector and PP-OCRv4 English recognizer through `flutter_onnxruntime`.
- Camera preview keeps its aspect, focuses the MRZ band, and reads each MRZ line on its own.
- Example Android release build keeps the ONNX Runtime classes for R8.
