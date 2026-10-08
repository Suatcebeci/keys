# Keys - Güvenli Çevrimdışı Şifre Kasası (Offline Password Vault)

Keys, Apple'ın modern güvenlik ve arayüz standartlarına uygun olarak geliştirilmiş, %100 çevrimdışı, sıfır bağımlılıklı bir iOS/iPadOS şifre yöneticisidir.

---

## 🔒 Güvenlik Özellikleri

- **%100 Çevrimdışı**: Ağ bağlantısı, telemetri, analitik, push bildirimi veya harici SDK kesinlikle bulunmaz.
- **Hardware-Backed Keychain**: Tüm gizli anahtarlar `Security.framework` (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) ve `SecAccessControl` (`.userPresence`) ile Secure Enclave donanımına bağlı saklanır.
- **Biyometrik Kimlik Doğrulama**: Face ID / Touch ID ve Cihaz Parolası desteği (`LocalAuthentication.framework`). Doğrulanmış `LAContext` yeniden kullanımı sayesinde ek kilit açma gecikmesi olmadan güvenli erişim.
- **Pano (Clipboard) Güvenliği**: 
  - `localOnly: true`: Universal Clipboard / Handoff aktarımını işletim sistemi düzeyinde engeller.
  - `expirationDate: 45 saniye`: Pano süresi dolduğunda otomatik temizlenir. Harici içerikler korunur.
- **App Switcher & Snapshot Gizliliği**: Uygulama arka plana geçtiğinde veya çoklu görev ekranı açıldığında sıfır animasyonlu %100 opak gizlilik perdesi (`PrivacyOverlayView`).
- **RAM Hijyeni**: Kasa kilitlendiğinde veya arka plana geçildiğinde tüm kayıt listesi, arama durumu ve hassas veriler bellekten silinir.
- **Kriptografik Şifre Üretici**: `SecRandomCopyBytes` (CSPRNG), rejection sampling (modulo-bias önleyici) ve Fisher-Yates algoritmasıyla güçlü şifreler üretir.
- **Hartley Entropi Analizi**: Şifre gücü analizi formül tabanlı sezgisel Hartley bilgi tahmini ve brute-force entropisi ile hesaplanır.

---

## 📊 XLSX Dışa Aktarma (Export)

- **Saf Swift PKZIP & Open XML**: Üçüncü taraf kütüphane olmaksızın gerçek `.xlsx` dosyası üretilir.
- **İki Çalışma Sayfası**:
  - **Giriş Bilgileri**: Title, Username, Website, Password, Notes.
  - **Banka Bilgileri**: Bank Name, Password (Kullanıcı adı, web sitesi veya notlar banka kaydında bulunmaz).
- **Excel Formula Injection Koruması**: `=`, `+`, `-`, `@`, `\t`, `\r` ile başlayan girdiler `'` ile kaçırılarak Excel'de yalnızca düz metin olarak açılır.
- **XML Escaping & UTF-8**: `&`, `<`, `>`, `"`, `'` entity encoding ile korunur; Türkçe karakterler (`ç Ç ğ Ğ ı İ ö Ö ş Ş ü Ü`) bozulmaz.
- **Geçici Dosya Yaşam Döngüsü**: Dosya yalnızca `temporaryDirectory` içinde üretilir; Share Sheet kapandığında, hata oluştuğunda veya kasa kilitlendiğinde derhal silinir.

---

## 📱 Desteklenen Platformlar ve Cihazlar

- **iOS 17.0+** & **iPadOS 17.0+**
- iPhone (Dikey & Yatay, NavigationStack)
- iPad (Dikey & Yatay, NavigationSplitView)
- Dark Mode & Light Mode tam uyumluluk
- Dynamic Type & VoiceOver erişilebilirlik desteği (Minimum 44x44 pt dokunma alanları)

---

## 🛡️ Güvenlik Bildirimi ve Sınırlar

Ayrıntılı güvenlik modeli ve teknik açıklamalar için lütfen [SECURITY.md](SECURITY.md) dosyasını inceleyin.
- Manuel fiziksel donanım ekran görüntüleri standart iOS/SwiftUI kısıtlamaları nedeniyle tamamen engellenemez.
- Swift String bellek sıfırlaması (zeroization) çalışma zamanı mimarisi nedeniyle garanti edilemez.
- XLSX dışa aktarma dosyası şifreli değildir ve aktarım sonrası Keys'in koruma sınırının dışındadır.
