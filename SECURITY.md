# Güvenlik Modeli ve Mimari Dokümantasyonu (Security Architecture)

Keys, sıfır-ağ (zero-network), sıfır-üçüncü-taraf (zero-third-party) ve tamamen yerel donanım koruması prensibiyle geliştirilmiş bir iOS çevrimdışı şifre yöneticisidir.

---

## 1. Temel Güvenlik İlkeleri

1. **%100 Çevrimdışı Mimari (100% Offline)**:
   Uygulama hiçbir ağ kütüphanesi (`URLSession`, `Network.framework`, `WebKit`, `WebSocket`, `CloudKit`, `Firebase`, `Supabase`) içermez. Cihaz dışı iletişim kanalı kod düzeyinde mevcut değildir.

2. **Otomatik Veri İletimi Yoktur**:
   Kullanıcı verileri, telemetri, analitik veya çökme raporları cihaz dışına otomatik veya manuel olarak gönderilmez.

3. **Donanım ve Cihaz-Bağımlı Keychain Koruması**:
   Tüm şifreler Apple `Security.framework` kullanılarak `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` erişilebilirlik seviyesi ve `SecAccessControl` (`.userPresence`) ile saklanır.
   - Veriler iCloud Keychain veya iCloud Backup'a senkronize edilmez.
   - Şifresiz yerel iTunes/Finder yedeklerine dahil edilmez.
   - Şifreli yerel yedeklerde ise cihazın Secure Enclave donanım UID'sine bağlı kaldığından başka bir cihaza taşınamaz veya çözülemez.
   - Cihaz kilitlendiğinde işletim sistemi düzeyinde şifre çözme anahtarları erişilemez hale gelir.

4. **Kasa Yaşam Döngüsü ve RAM Hijyeni**:
   - Kasa kilitlendiğinde (`lockVault()`) RAM'deki tüm metadata listesi (`entries`), arama terimi, hata mesajları ve oturum nesnesi (`LAContext`) derhal boşaltılır.
   - Uygulama arka plana geçtiğinde (`scenePhase == .background`) kasa otomatik olarak kilitlenir ve bellek temizlenir.

5. **App Switcher ve Snapshot Gizliliği**:
   `UIApplication.willResignActiveNotification` dinlenerek, iOS işletim sistemi çoklu görev snapshot'ı almadan önce sıfır animasyonla %100 opak bir `PrivacyOverlayView` devreye sokulur.

6. **Güvenli Pano (Clipboard)**:
   - `UIPasteboard.OptionsKey.localOnly: true` ile Universal Clipboard (Handoff) üzerinden şifrenin Bluetooth/Wi-Fi ile diğer Apple cihazlarına aktarılması engellenir.
   - `expirationDate: 45 saniye` seçeneğiyle işletim sistemi düzeyinde süreli temizleme sağlanır.
   - Kullanıcı başka bir uygulamadan yeni bir metin kopyaladıysa, Keys kullanıcının yeni panosunu ezmez veya silmez.

7. **Kriptografik Rastgelelik**:
   - Şifre üretimi yalnızca `SecRandomCopyBytes` (CSPRNG), rejection sampling (modulo bias önleyici) ve Fisher-Yates karıştırma algoritması kullanır.
   - `Int.random`, `arc4random` veya öngörülebilir seed/fallback bulunmaz.

---

## 2. XLSX Dışa Aktarma (Export) Modeli ve Sınırları

1. **Bilinçli Kullanıcı Aksiyonu**:
   XLSX dışa aktarma işlemi, kullanıcının kasayı açtıktan sonra açık bir güvenlik uyarısı görmesi ve ek bir biyometrik / cihaz parolası doğrulaması gerçekleştirmesiyle başlar.

2. **Dosya Şifreleme Durumu**:
   Üretilen Open XML (.xlsx) dosyası şifreli değildir; düz metin (plain-text) veri formatındadır.

3. **Keychain Koruma Sınırı**:
   Export dosyası oluşturulduğu ve kullanıcı tarafından Share Sheet aracılığıyla başka bir konuma (dosyalar, e-posta, AirDrop vb.) aktarıldığı andan itibaren, dosya Keys uygulamasının ve iOS Keychain'in koruma sınırının dışındadır.

4. **Geçici Dosya Yaşam Döngüsü**:
   Export dosyası yalnızca `temporaryDirectory` altında üretilir.
   - Share Sheet kapandığında veya iptal edildiğinde,
   - Export sırasında herhangi bir hata oluştuğunda,
   - Kasa kilitlendiğinde veya uygulama arka plana geçtiğinde,
   geçici export dosyası derhal silinir.

5. **Excel Formula Injection Koruması**:
   Kullanıcı girdilerinin Excel veya başka hesap tablosu yazılımlarında çalıştırılabilir komut veya formül haline gelmesini engellemek için, `=`, `+`, `-`, `@`, `\t`, `\r` ile başlayan tüm alanlar güvenli hücre kaçış karakteri (`'`) ile korunur.

6. **XML Escaping**:
   `&`, `<`, `>`, `"`, `'` karakterleri standart XML entity karşılıklarına dönüştürülür ve Türkçe karakterler (`ç Ç ğ Ğ ı İ ö Ö ş Ş ü Ü`) UTF-8 standardında bozulmadan aktarılır.

7. **Kayıt Türü ve Kolon İzolasyonu**:
   - Giriş Bilgileri (Sheet 1): Title, Username, Website, Password, Notes.
   - Banka Bilgileri (Sheet 2): Bank Name, Password. Banka sayfasında kullanıcı adı, web sitesi veya notlar yer almaz.
   - Kategori alanı bulunmaz.

---

## 3. Platform ve Teknik Sınırlamalar (Known Technical Limitations)

1. **Manuel iOS Ekran Görüntüleri (Hardware Screenshots)**:
   iOS işletim sisteminde kullanıcının fiziksel donanım tuşlarına (Güç + Ses Açma) basarak aldığı manuel ekran görüntüleri standart SwiftUI API'leri ile garanti şekilde engellenemez. Privacy Overlay mekanizması App Switcher ve arka plan snapshot koruması için geçerlidir.

2. **Swift String Bellek Sıfırlama (Zeroization)**:
   Swift dilinin çalışma zamanı (runtime) ve String bellek yönetim yapısı (Copy-on-Write, immutable strings, optimizasyonlar) gereği, `String` nesnelerinin RAM'deki her bir baytının işletim sistemi düzeyinde anında üzerine 0 yazılarak sıfırlanması (zeroization) garanti edilemez. Keys, bu riski minimize etmek için şifreleri model düzeyinde bellekte tutmaz, şifreyi yalnızca kullanıcı talep ettiğinde Keychain'den çeker ve kasa kilitlendiğinde referansları bellekten tamamen siler.
