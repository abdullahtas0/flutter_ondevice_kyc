# Measurement ledger

The ledger scores still frames that stay on the machine that runs it. This repository does not store those frames, and it does not download a document set.

A case marked `lock` counts only when the manifest names the gated fields: document number, birth date, and expiry date, or a PAN. The scanner's green lock is a checksum. Here a correct lock is a checksum that also matches those fields. The name line has no check digit, so a name miss is counted and does not change either rate.

| Number | Definition |
| --- | --- |
| Lock rate | Correct locks / cases that expected a lock and named a gate |
| False-lock rate | False locks / processed cases |
| p95 | 95% point on the sorted elapsed times of processed cases, linearly interpolated and rounded to the nearest millisecond |

A false lock is a locked frame whose gated fields differ, or a lock on a case marked `reject`. A reject on a case marked `lock` is a miss. It lowers the lock rate and is not a false lock. Skipped frames and unscored rows stay out of both rates and out of the percentile. An expected lock that names neither gate is unscored, so a thin manifest cannot print a perfect lock rate.

On a handful of frames, p95 sits near the slowest one. That is the small sample, not a device baseline.

The written report lists the model (`onnx` or `fixture`), case ids, outcomes, mismatched field names, and milliseconds. It does not list field values, MRZ lines, or file names. `model: fixture` is the arithmetic check. It is not a measurement of the weights.

## Private folder

```
private/
  manifest.json
  frames/
```

`eval/private/` is gitignored. Any other directory works if it stays out of git.

```json
{
  "cases": [
    {
      "id": "td3-01",
      "file": "frames/td3-01.jpg",
      "expect": "lock",
      "documentNumber": "A12345678",
      "birthDate": "1990-01-02",
      "expiryDate": "2030-01-02"
    },
    {
      "id": "glare-01",
      "file": "frames/glare-01.jpg",
      "expect": "reject"
    }
  ]
}
```

Optional fields: `tckn`, `cardNumber`, `cardExpiry`, `surname`, `givenNames`. `cardNumber` with no MRZ fields scores a payment-card frame. `surname` and `givenNames` only feed the name count.

A case id contains a hyphen and fewer than nine digits, for example `td3-01`. A file path may not leave the folder.

## Run

From `example/`:

```bash
KYC_EVAL_DIR=/absolute/path/to/private flutter test test/eval_private_test.dart
```

The test loads the ONNX models, writes `ledger.txt` in that folder, and prints the same text. It does not fall back to the fixture scanner.

`example/test/eval_folder_test.dart` runs the same scorer on a generated card and the fixture recognizer. That proves the arithmetic. It does not prove a photographed document.

Until `ledger.txt` is produced by the ONNX models on a private folder, detector work and INT8 stay parked.
