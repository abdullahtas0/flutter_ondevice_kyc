# Model dosyaları

Uygulamanın yüklediği kopyalar `example/assets/models/` altındadır.

- `card_detector.onnx` — YOLOX-Nano, 3 sınıf, giriş `1x3x416x416` BGR, 0–255. NMS grafın dışındadır. Sentetik kartla ince ayar. 8.6 MB.
- `text_rec.onnx` — resmi `en_PP-OCRv4_mobile_rec`, opset 11. Giriş `x` şekli `[N,3,48,W]`, çıkış `[N,T,97]`. 7.3 MB.
- `en_dict.txt` — resmi PaddleOCR İngilizce sözlük, 95 karakter, `<` var. CTC blank indeksi 0'dır ve dosyada yoktur.

SHA-256:

- `545e9353120b155d9faaac6881a371b0c77ddb262bf1dc59f26503a686953d9e` card_detector.onnx
- `75e3265c26f9685818aaf0a41d380c888d3692810d8a15ffd4f1576de809dd58` text_rec.onnx
- `5662df9d2d03f0e8ca0d3b0649d6acbab904b6a14b3d3521463c71c37c668ce3` en_dict.txt

İkisi birden FP32 olduğu için toplam 15.9 MB. Tanıyıcı sıkıştırılmadı; `L898902C3<` okuması bu dosyayla doğrulandı. Dedektör INT8'i yalnızca kalibrasyonla ve mAP korunursa uygulanır.
