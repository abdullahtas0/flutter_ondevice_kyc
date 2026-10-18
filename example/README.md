# kyc_example

`flutter_ondevice_kyc` için kamera ve doğrulama demosu.

```bash
flutter pub get
flutter run
```

Modeller `assets/models/` altındadır. Üstteki etiket **Cihaz modeli** ise her iki oturum da açılmıştır. Tara sekmesi arka kamerayı MRZ bandına odaklar. Doğrulama sekmesi yapıştırılan metni kilitler.

Android yayın paketi `android/app/proguard-rules.pro` ile derlenir. Kural, R8'in ONNX Runtime sınıflarını silmesini engeller.
