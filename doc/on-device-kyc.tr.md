# Kimlik karesini sunucuya koymadan MRZ okumak

KYC, bankanın müşteriyi tanıma işinin adıdır. Bu paket o işin tamamını yapmaz. Kameradaki kareden makine okunur bölgeyi ya da kart numarasını çıkarır. ICAO 9303 veya Luhn tutarsa sonucu verir. Tutmazsa kareyi reddeder. Canlılık, NFC çip, yüz karşılaştırması ve CVV yoktur. Yeşil kilit, kişinin onaylandığı anlamına gelmez. Okunan karakterlerin check digit'inin tuttuğu anlamına gelir.

## Check digit modelden önce kondu

ICAO Doc 9303, pasaport ve kimlik kartındaki MRZ satırlarını tanımlar. Bazı alanların sonunda bir check digit vardır. Buradaki uygulama ağırlıkları 7, 3, 1 diye tekrarlar. Rakam kendi değeridir. A–Z, 10'dan 35'e kadar sayılır. `<` sıfırdır. T.C. kimlik kartının arkası TD1'dir: üç satır, her satır 30 karakter. İsteğe bağlı alanda 11 hanelik bir koşu varsa TCKN de ayrıca tutulur. İsim satırında check digit yoktur. Kilit onu beklemez.

OCR bir karakteri kaydırır. Tek bir `O`/`0` veya `B`/`8` karışıklığı, basılı check digit bütün alanlarla birlikte tutuyorsa düzeltilir. İki ayrı düzeltme de haneyi tutuyorsa hiçbiri alınmaz. Yanlış belge numarasını kilitlemek, o kareyi boş geçmekten kötüdür. `ScanRejected` bu yüzden exception değildir. Sonraki kare okunur.

## YOLO11 kapalı uygulamaya uymaz

Küçük bir detector olarak YOLO11n açıktı. Ultralytics kodu AGPL-3.0 ile dağıtılır. AGPL ağırlığı kapalı kaynak bir banka uygulamasına gömmek, o uygulamanın lisans yükümlülüğünü değiştirir. Paket MIT kalsın diye detector Megvii YOLOX-Nano oldu. O depo Apache-2.0. Üç sınıf var: `id_card`, `mrz_zone`, `credit_card_numbers`. Giriş 416, BGR, 0–255. NMS ağın içinde değil. Dart tarafında yapılıyor.

## Colab dikdörtgen eğitti

Gerçek kimlik fotoğrafı repoya girmedi. `training/finetune_yolox_nano.py` açık renk kartlar çizer ve YOLO etiketlerini yazar. Colab'da Megvii YOLOX klonlandı. `requirements.txt` içindeki `onnx-simplifier`, o sanal makinenin Python sürümünde kaynak paket olarak derlenemedi. Torch, torchvision ve onnx satırları kuruluma alınmadı. `pip install -e .` aynı bağımlılığı çektiği için o da kullanılmadı. Eğitim şöyle koştu:

```bash
PYTHONPATH=/content/YOLOX python tools/train.py \
  -f /content/flutter_ondevice_kyc/training/yolox_nano_kyc.py \
  -d 1 -b 8 --fp16 -c yolox_nano.pth
```

Ön eğitim ağırlığı YOLOX 0.1.1rc0 sürümündeki `yolox_nano.pth`. Nano derinlik 0.33, genişlik 0.25, 50 epoch, giriş 416. GPU o oturumda Tesla T4 idi.

Dışa aktarma da Colab'da yapıldı. PyTorch 2.6 ve sonrası `torch.load` varsayılan olarak `weights_only=True` kullanır. Eski checkpoint bu ayarla açılmaz. `torch.onnx._export` da kalkmıştı. Çalışan çağrı `torch.onnx.export(..., dynamo=False)` ve `--no-onnxsim` oldu. Çıkan dosya `card_detector.onnx`, yaklaşık 8.6 MB.

Doğrulama kümesi de aynı sentetik dikdörtgenlerdi. O skor, fotoğraflanmış kimlikte kutu çıkacağını ölçmez. Telefonda asıl okuma, çerçevenin altındaki satırların tanınmasıdır. Detector kutusu işe yararsa homografi onu kullanır. Yaramazsa ve karede kontrast varsa çerçevenin kendisi dörtgen olur.

## Tanıyıcı Colab'da bitmedi

Satır okuyucu, PaddleOCR'ın resmi `en_PP-OCRv4_mobile_rec` çıkarım paketidir. Apache-2.0. Colab'da `paddle2onnx`, Paddle 3 ile kalkan `paddle.fluid` yoluna düştü. Python 3.13 üzerinde onnx tekeri de kurulamadı. Dönüşüm yerel makinede bitti: Python 3.12, PaddlePaddle 3.1.1, paddle2onnx 2.0.2rc3. Model dosyası `inference.json` ve `inference.pdiparams`. Sözlük resmi `en_dict.txt`. 95 karakter var, `<` dahil. CTC blank indeksi 0 ve dosyada yok.

Bu ağ tek satır bekler. Yükseklik 48'e çekilir. Genişlik eğitildiği 320'de kesilirse 30 karakterlik bir TD1 satırı yatayda ezilir. Satırlar ayrılıp her biri kendi en-boy oranıyla veriliyor. Genişlik 8'in katına yuvarlanır ve 960'ı geçmez. Modelin genişlik ekseni dinamik olduğu için bu şekil oturuma gider.

## Yayın derlemesi sınıfın adını sildi

Huawei ELS-NX9, Android 10. Debug paket açıldı, tarama sürdü. Yayın paketinde `OrtSession.run` süreci düşürdü. JNI mesajı `java_class == null` ve `GetMethodID` idi. Debug dex içinde `Lai/onnxruntime/TensorInfo;` duruyordu. Yayın eşleme dosyasında aynı sınıf `t80` olmuştu. R8, yerel kodun adıyla aradığı sınıfı yeniden adlandırmıştı.

`example/android/app/proguard-rules.pro` şunu tutar:

```
-keep class ai.onnxruntime.** { *; }
```

Aynı kuralı flutter_onnxruntime sorun notu ve ONNX Runtime'ın Android derleme sayfası da yazar. Kural eklenmeden yayın paketi bu telefonda tarama anında kapanıyordu. Kuraldan sonra aynı cihazda, kart sabitken kilitlenen kareler o akşamki logda yaklaşık 800–900 ms sürdü. Bu süre o telefonun o derlemesine aittir.

Odak ayrı bozuldu. Sürekli otomatik netlik MRZ'yi oynatıyordu. Kamera açılınca odak ve pozlama, çerçevenin alt bandına alınıp kilitleniyor. Dokununca aynı bant yeniden netlenip yine kilitleniyor. Kart birkaç derece eğikse alt bant düzeltiliyor. Satır projeksiyonu ayıramazsa alt bant üçe bölünüp yine okunuyor.

## Kilit sahteciliği ölçmez

Kilit, karakterlerin check digit'ini ölçer. Kartın sahte olduğunu, çipin eşleştiğini veya kişinin kadrajda canlı durduğunu ölçmez. Detector gerçek kimlik fotoğrafıyla eğitilmedi. Tanıyıcı, `L898902C3<` gibi basılı bir örnek dizgede denendi. Fotoğraflanmış bir MRZ ile birim test edilmedi. İki karakter birden kayarsa tamir aday seçemez ve kare reddedilir. O kare haneyi tutmamıştır.

## Kaynaklar

- ICAO Doc 9303, makine okunur seyahat belgeleri: https://www.icao.int/publications/pages/publication.aspx?docnum=9303
- Ultralytics deposu: https://github.com/ultralytics/ultralytics
- YOLOX, Apache-2.0: https://github.com/Megvii-BaseDetection/YOLOX
- PaddleOCR: https://github.com/PaddlePaddle/PaddleOCR
- flutter_onnxruntime, Android R8 notu: https://github.com/masicai/flutter_onnxruntime/blob/main/doc/troubleshooting.md
- ONNX Runtime Android derlemesi: https://onnxruntime.ai/docs/build/android.html
- Paket: https://github.com/abdullahtas0/flutter_ondevice_kyc
