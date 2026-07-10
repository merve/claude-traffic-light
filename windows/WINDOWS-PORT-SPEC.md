# Claude Traffic Light — Windows Port Spec

Bu dosya, macOS uygulamasının **tam davranış sözleşmesini** içerir. Amaç: Windows
sürümünü yazacak kişinin (veya AI'ın) Mac kaynak kodunu tekrar analiz etmeden,
sadece bu dosyaya bakarak birebir muadilini yazabilmesi.

> **Durum:** Her iki port da tamamlandı ve gönderiliyor — sistem tepsisi uygulaması
> (`ClaudeTrafficLight/`) ve yüzen widget (`ClaudeTrafficWidget/`, bkz. §13). Bu
> dosya artık sadece ilk yazım rehberi değil, davranış sözleşmesinin güncel
> referansı: platformlardan biri değiştiğinde diğerini ve bu dosyayı senkron tutun
> (bkz. [`CONTRIBUTING.md`](../CONTRIBUTING.md)).

Mac kaynağı referans: `../macos/` (Swift + AppKit menü-çubuğu uygulaması + widget).
Windows karşılığı: **system tray (bildirim alanı) uygulaması** + yüzen widget.

---

## 1. Ürün nedir?

Menü çubuğunda / sistem tepsisinde duran küçük bir **trafik ışığı** simgesi. Açık olan
Claude Code oturumlarının durumunu tek bakışta gösterir:

- 🟢 **yeşil** = bitti, sıra sende
- 🟡 **sarı** = çalışıyor
- 🔴 **kırmızı** = seni bekliyor (soru soruyor / izin bekliyor)

Birden çok oturum varsa en yüksek öncelikli renk gösterilir (kırmızı > sarı > yeşil).
Simgeye tıklayınca açılan menüde her oturum listelenir; bir oturuma tıklayınca onun
çalıştığı yere (VS Code / Cursor / terminal / Claude masaüstü) atlar. Kırmızıya yeni
geçen oturumlar için bildirim gönderir.

**Ağ yok, token yok:** sadece yerel dosya okur. Tamamen çevrimdışı.

---

## 2. Veri sözleşmesi — durum dosyaları

Uygulama ile hook arasındaki tek arayüz budur. Windows'ta da **aynen** korunmalı.

- **Konum:** `%USERPROFILE%\.claude\status\` (Mac'te `~/.claude/status/`).
  Claude Code Windows'ta da ev dizinini `~/.claude` = `%USERPROFILE%\.claude` kullanır.
- **Her oturum = bir dosya:** `<session_id>.json` (session_id yalnızca alfanümerik,
  `-`, `_` karakterlerine sanitize edilir; boşsa `unknown`).
- **Atomik yazım:** önce `<dosya>.json.tmp` yazılır, sonra `.json` üzerine taşınır
  (rename). Böylece uygulama hiçbir zaman yarım dosya okumaz.
- **Oturum bitince dosya silinir** (aşağıdaki `end` durumu).

### JSON alanları

```json
{
  "state": "yellow",              // "red" | "yellow" | "green"  (zorunlu)
  "project": "my-app",            // cwd'nin son klasör adı
  "cwd": "C:\\Users\\me\\my-app", // proje kök dizini
  "ts": 1699999999,               // unix saniye (int)
  "session_pid": 12345,           // oturumun claude sürecinin PID'i (bilinmiyorsa 0)
  "platform": "vscode",           // "desktop"|"vscode"|"cursor"|"terminal"|"unknown"
  "app_path": ""                  // (Mac) oturumu barındıran .app yolu; Windows'ta pid daha kullanışlı
}
```

`state` geçersiz/eksikse dosya yok sayılır.

---

## 3. Hook (olay yakalayıcı)

Claude Code, olaylarda `settings.json`'daki komutları çalıştırır ve hook'a **stdin
üzerinden JSON** verir (`session_id`, `cwd`, `tool_name`, ... alanları içerir).
Hook bu JSON'u okuyup ilgili status dosyasını günceller.

### 3.1 Olay → durum eşlemesi (settings.json)

Mac'teki `hooks/settings-snippet.json` birebir (komut yolu Windows'a göre değişir):

| Claude Code olayı   | matcher | hook argümanı | anlamı                          |
|---------------------|---------|---------------|---------------------------------|
| `UserPromptSubmit`  | —       | `yellow`      | kullanıcı mesaj gönderdi → çalışıyor |
| `PreToolUse`        | `*`     | `yellow`      | araç çalışacak → çalışıyor       |
| `PermissionRequest` | —       | `red`         | izin istiyor → seni bekliyor     |
| `PostToolUse`       | `*`     | `yellow`      | araç bitti → çalışıyor           |
| `Notification`      | —       | `red`         | bildirim → seni bekliyor         |
| `Stop`              | —       | `green`       | yanıt bitti → sıra sende         |
| `SessionEnd`        | —       | `end`         | oturum kapandı → dosyayı sil     |

Grup JSON şekli (her olay için):
```json
{ "hooks": [ { "type": "command", "command": "<HOOK KOMUTU> <state>" } ] }
```
`PreToolUse`/`PostToolUse` gruplarında ayrıca `"matcher": "*"` bulunur.

### 3.2 Hook mantığı (state parametresine göre)

1. `STATUS_DIR = %USERPROFILE%\.claude\status`, yoksa oluştur.
2. stdin'deki JSON'u oku ve parse et (parse edilemezse boş obje kabul et).
3. `session_id` al, sanitize et, hedef dosya yolunu kur.
4. **Kırmızı override kuralı (önemli):** `state == "yellow"` VE `tool_name`
   (küçük harfe çevrilmiş) `askuserquestion` veya `exitplanmode` içeriyorsa →
   `state = "red"` yap. (Bu araçlar kullanıcıya soru sorup beklediği için.)
5. `state == "end"` ise: dosyayı sil ve çık.
6. Değilse: `cwd`'den `project = son klasör adı` türet, `ts = şu anki unix saniye`,
   `session_pid`, `platform`, `app_path` doldur ve JSON'u **atomik** yaz.

### 3.3 Platform tespiti (process ağacından)

Mac hook'u, hook'u çalıştıran sürecin (`$PPID` = claude süreci) **ata zincirini**
(`ps` ile ~8 seviye) kurar ve komut satırlarına bakarak platformu belirler:

| Zincirde geçen ipucu | platform |
|---|---|
| `.vscode/extensions/anthropic.claude-code`, `Visual Studio Code`, `Code Helper` | `vscode` |
| `.cursor/extensions/anthropic.claude-code`, `Cursor` | `cursor` |
| `Application Support/Claude/claude-code`, `/Applications/Claude.app/` | `desktop` |
| `iTerm`, `Terminal.app`, `WarpTerminal`/`Warp.app`, `ghostty`, `Alacritty`, `kitty`, `WezTerm`, `Hyper`, `tmux` | `terminal` |
| hiçbiri | `unknown` |

Ayrıca zincirdeki **ilk `.app` yolunu** `app_path` olarak saklar (tıklamada doğru
terminali öne getirmek için).

**Windows karşılığı:** ata zincirini exe adlarından tespit et (aşağıda §12.2):
- `Code.exe` → `vscode`, `Cursor.exe` → `cursor`, `Claude.exe` → `desktop`,
  `WindowsTerminal.exe`/`wt.exe`/`powershell.exe`/`pwsh.exe`/`cmd.exe`/`conhost.exe`/
  `alacritty.exe`/`wezterm.exe` vb. → `terminal`, aksi halde `unknown`.
- `session_pid` = zincirdeki `node.exe` atası (Claude Code CLI node ile çalışır);
  bulunamazsa doğrudan üst süreç veya `0`.

`ts` her yazımda güncellenir; canlılık ve bayatlık kontrolü buna dayanır.

---

## 4. Çekirdek mantık (StatusStore)

Windows'ta bu mantığı **birebir** taşı (test edilebilir tutmak için AppKit/WinForms'tan bağımsız bir sınıf olarak).

### 4.1 State ve öncelik
```
red    → priority 3   emoji 🔴
yellow → priority 2   emoji 🟡
green  → priority 1   emoji 🟢
```

### 4.2 Yükleme (`load()`)
`status/*.json` dosyalarını tara. Her biri için:
1. Oku, parse et; `state` yoksa/geçersizse atla.
2. `ts` sayı veya string olabilir; parse et.
3. **Canlılık:**
   - `session_pid > 0` ise: süreç yaşamıyorsa dosyayı **sil** ve atla.
     (Mac: `kill(pid, 0)`; EPERM dönerse süreç var sayılır.
      **Windows:** `Process.GetProcessById(pid)` — `ArgumentException` = ölü.)
   - `session_pid <= 0` (eski format) ise: `now - ts > 30 dk` ise dosyayı **sil** ve atla.
4. `project` yoksa cwd'nin son bileşeninden türet; `platform` yoksa `unknown`.
5. Listeye ekle.

**Bayatlık eşiği:** `staleAfter = 30 * 60 sn` (30 dakika).

### 4.3 Sıralama
Önce önceliğe göre azalan (kırmızı üstte), eşitlikte `ts` yeni olan üstte.

### 4.4 Agregasyon (bar ikonu için tek renk)
Oturumların en yüksek öncelikli durumu. **Hiç oturum yoksa** → mantıksal olarak
"ışık kapalı" (aşağıya bak). Mac kodu boşsa `.green` döndürür ama UI katmanı
`activeLight = nil` (kapalı) yapar:
- `sessions.isEmpty` → `activeLight = nil` → **hiçbir mercek yanmaz (ışık kapalı)**
- doluysa → `activeLight = aggregate` (yanan mercek)

---

## 5. Tıklama yönlendirme (SessionRouter)

Saf/test edilebilir karar mantığı. Girdi: `platform`, `app_path`, `cwd`, `session_id`.

| platform | eylem (Mac) |
|---|---|
| `vscode` | VS Code'da klasörü aç (`/Applications/Visual Studio Code.app` + cwd) |
| `cursor` | Cursor'da klasörü aç (`/Applications/Cursor.app` + cwd) |
| `desktop` | Claude masaüstü deep link: `claude://resume?session=<id>` |
| `terminal` | `app_path` doluysa o .app'i öne getir; boşsa deep link |
| `unknown` | `app_path` doluysa o .app'i öne getir; boşsa deep link |

Ek davranışlar:
- **⌥ (Option) basılıyken tıklama:** her zaman proje klasörünü editörde aç (override).
  Windows'ta buna karşılık **Ctrl+tıklama** yapılabilir (opsiyonel; ToolStrip'te
  modifier okumak zor, atlanabilir).
- Hedef uygulama makinede yoksa: editör açma → jenerik klasör açıcıya, .app öne
  getirme → deep link'e **fallback** yapar.
- Jenerik klasör açıcı sırası (Mac): VS Code → Cursor → Terminal.

**Windows karşılığı (§12.3):**
- `vscode` → `code "<cwd>"`; `cursor` → `cursor "<cwd>"` (PATH'te `code.cmd`/`cursor.cmd`).
- `desktop` → `claude://resume?session=<id>` (Windows'ta Claude masaüstü bu şemayı
  kaydediyorsa çalışır; yoksa klasör açmaya fallback).
- `terminal`/`unknown` → `session_pid`'in `MainWindowHandle`'ını `SetForegroundWindow`
  ile öne getir (gerekiyorsa `ShowWindow(SW_RESTORE)`); pencere yoksa Explorer'da/editörde klasörü aç.

---

## 6. Bildirimler (RedTransitionTracker)

Bildirim yalnızca bir oturum **yeni kırmızıya geçtiğinde**, oturum başına **bir kez**
atılmalı (her poll'da değil).

Mantık (`RedTransitionTracker`):
- Bir `known: Set<string>?` tutar (başlangıçta `nil`).
- `newlyRed(currentRed)`: ilk çağrı → **seed** (boş döndür, sadece kümeyi kaydet).
  Böylece uygulama açılışında zaten kırmızı olan oturumlar için bildirim yağmuru olmaz.
  Sonraki çağrılarda `currentRed \ previous` (yeni eklenenler) döner.

Bildirim içeriği (Mac):
- **Başlık:** `l10n.notifyTitle` (örn. "Claude is waiting for you" / "Claude seni bekliyor")
- **Gövde:** `"<project> · <PlatformLabel>"` (örn. "my-app · VS Code")
- **Ses:** default
- Bildirime tıklayınca ilgili oturuma yönlendir (§5).
- identifier = `red-<sessionID>` → aynı oturum tekrar kırmızı olursa üst üste
  yığılmaz, mevcut bildirimi değiştirir.

`PlatformLabel`:
```
vscode → "VS Code"   cursor → "Cursor"   desktop → "Claude"
terminal → "Terminal"   diğer → "Claude"
```

Bildirimler menüden açılıp kapatılabilir (aç/kapa durumu kalıcı; Mac `UserDefaults`,
**Windows** registry `HKCU\Software\ClaudeTrafficLight\NotificationsEnabled` veya
`.claude` içinde küçük bir json).

**Windows karşılığı:** `NotifyIcon.ShowBalloonTip(...)` (basit) veya toast bildirimi.
Balloon'da payload taşınmadığı için son bildirilen `sessionID`'yi bir alanda tut ve
`BalloonTipClicked`'te ona yönlendir.

---

## 7. İkon tasarımı (trafik ışığı çizimi)

Mac: **yatay** 3 mercekli trafik ışığı (menü çubuğu yatay olduğu için). Kırmızı sol,
sarı orta, yeşil sağ. Aktif mercek parlar (pulse + halo), diğerleri sönük. Housing
stadyum (pill) şekli, koyu; her mercek soket halkası + üstte içbükey "göz kapağı"
(hood) ile.

**Windows tepsisi kare olduğu için → DİKEY trafik ışığı öner** (kırmızı üstte, sarı
ortada, yeşil altta). Kare yuvaya çok daha iyi oturur ve anında "trafik ışığı" olarak
okunur. Bu bir sapma değil, platforma uygun doğal uyarlama.

### 7.1 Renkler (birebir koru)
```
red    = RGB(242, 51, 41)    // calibrated (0.95, 0.20, 0.16)
yellow = RGB(255, 199, 13)   // (1.00, 0.78, 0.05)
green  = RGB(46, 184, 89)    // (0.18, 0.72, 0.35)
housing        = beyaz 0.17 (koyu gri gövde)
socket (halka) = beyaz 0.09 (çok koyu)
hood/eyelid    = beyaz 0.08 (koyu, opak)
```

### 7.2 Pulse (nabız) animasyonu
- Yalnızca `active == red || active == yellow` iken animasyon çalışır.
- `phase` 0→1 arası döner; ~1.2 sn'lik döngü. Mac: `animationPhase += (1/15)/1.2` her
  frame (~15 fps).
- Parlaklık: `pulse = animate ? (0.75 + 0.25 * (0.5 - 0.5*cos(phase*2π))) : 1.0`
- Aktif mercek: doygun renk + beyazın %6'sı ile hafif karıştırılmış, `pulse` alfa ile;
  halo için (Mac shadow blur) — Windows'ta `PathGradientBrush` ile merkez=renk,
  kenar=şeffaf bir halka çiz. Üç geçişle halo yoğunlaştırılır.
- Sönük mercekler: temel renk %30 alfa.
- Aktif mercekte üstte ince beyaz cam parıltısı (`alpha ≈ 0.42*pulse`).

### 7.3 Yatay yerleşim matematiği (Mac referansı, `image()`)
`H` = hedef yükseklik (menü çubuğu kalınlığı ~22):
```
padY   = H * 0.19
lensD  = H - 2*padY
socket = max(1, lensD * 0.10)
gap    = lensD * 0.34
padX   = H * 0.26
width  = 2*padX + 3*lensD + 2*gap
firstCX = padX + lensD/2 ; step = lensD + gap
housing köşe yarıçapı = (H-1)/2  (stadyum)
```

### 7.4 Dikey yerleşim (Windows önerisi, kare `N`)
```
lensD      = N * 0.26
gap        = N * 0.035
sideMargin = N * 0.055
topMargin  = N * 0.05
housingW = lensD + 2*sideMargin          (~0.37N)
housingH = 3*lensD + 2*gap + 2*topMargin (~0.95N)
ox=(N-housingW)/2 ; oy=(N-housingH)/2 ; cx=ox+housingW/2
firstCy = oy + topMargin + lensD/2 ; step = lensD + gap
housing köşe yarıçapı = housingW/2 (stadyum uçlar)
sıra: i=0 red (üst), i=1 yellow, i=2 green (alt)  [GDI+ y ekseni yukarıdan aşağı]
```
GDI+ ipuçları: `SmoothingMode.AntiAlias`; `Bitmap` → `GetHicon()` → `Icon.FromHandle`.
**Önemli:** eski HICON'u sızıntı olmaması için `DestroyIcon` ile serbest bırak
(yeni ikonu atadıktan SONRA önceki handle'ı yok et). Tepsi için ~32×32 çiz.

### 7.5 Sayı rozeti
- Mac: 1'den fazla kırmızı (bekleyen) varsa bar ikonunun yanına `" N"` başlığı yazar.
- Windows'ta tepsi tek kare olduğundan: `waiting > 1` ise ikonun köşesine küçük bir
  kırmızı daire içine sayı çiz VE her zaman açıklayıcı bir tooltip (`NotifyIcon.Text`)
  ver: örn. "Claude Traffic Light — 2 bekliyor · 1 çalışıyor".

### 7.6 Uygulama ikonu (Finder/Explorer/Dock)
`appIcon(size)`: köşeleri yuvarlatılmış kare arka plan (dikey degrade koyu gri) +
üstünde **her üç mercek de yanan** yatay trafik ışığı (aynı oranlar, halo + gölge +
cam parıltısı). Windows'ta `.ico` üretimi için aynı çizimi kullan.

---

## 8. Menü yapısı ve davranış

**Windows implementasyon notu:** aşağıdaki yapı `ContextMenuStrip` yerine özel
çizilmiş, kenarlıksız bir flyout (`UI/MenuFlyout.cs`) olarak uygulandı —
`ContextMenuStrip`'in kendi `Padding`'i ve genişlik eklemesi piksel-hassas simetrik
boşluk vermeye izin vermediği için (bkz. `--menuprobe` debug modu). Her satır/başlık
kendi `Control`'ü: `HeaderControl` (başlık+özet+✕), `SessionRowControl` (oturum
satırı), `ActionRowControl` (Notifications/Refresh/Quit), `HintControl` (alt ipucu);
ortak palet `MenuTheme.cs`'ten (Windows açık/koyu temasından seçilir).

Mac menüsü (aşağıdan yukarı yeniden kurulur, açılmadan hemen önce en taze veriyle):

1. **Başlık (header):**
   - Oturum yoksa: başlık = `l10n.noSessions` ("No active Claude sessions"), özet boş.
   - Varsa: başlık = `l10n.activeSessions` ("Active sessions") + renkli **özet sayaç**.
2. **Ayraç** (oturum varsa).
3. **Her oturum için bir satır:**
   - Proje adı + detay + durum rengi (nokta) + platform etiketi.
   - Detay:
     - `yellow` → sadece durum etiketi ("Working…").
     - `red`/`green` → `"<etiket> · <göreli zaman>"` (örn. "Done · 58s ago").
   - Tıklama → §5 yönlendirme. Satırda ayrıca "kapat" (oturumu sonlandır) düğmesi:
     `SIGTERM` (Mac). **Windows'ta:** süreci `session_pid` ile sonlandır
     (`Process.Kill()` / `CloseMainWindow()`), sonra kısa gecikmeyle yenile — satır düşer.
4. **Alt ipucu (hint):** `l10n.hint` ("Click a session to jump to it").
5. **Ayraç.**
6. **Notifications** (aç/kapa, işaretli/işaretsiz) — `l10n.notifyMenu`.
7. **Refresh** — `l10n.refresh` (kısayol `r`).
8. **Quit** — `l10n.quit` (kısayol `q`).

### 8.1 Özet sayaç (header)
`waiting`/`working`/`done` sayıları. Yalnızca **bekleyen** vurgulanır (kırmızı + semibold).
Ayraç: `"  ·  "`. "done" sayısı **yalnızca** bekleyen ve çalışan sıfırsa gösterilir
(header kısa kalsın). Örn: "2 bekliyor · 1 çalışıyor" veya (hepsi bittiyse) "3 bitti".

### 8.2 Canlı güncelleme
- **Kapalıyken:** dokunma; açılmadan hemen önce sıfırdan kurulur.
- **Açıkken:** yapı aynıysa (aynı oturum kimlikleri) satırları yerinde güncelle
  (zaman damgaları canlı ilerlesin, highlight kaybolmasın); yapı değiştiyse tam yeniden kur.

### 8.3 Zamanlayıcılar
- **Poll:** her **1 sn** diski oku, ikonu güncelle, kırmızı geçiş bildirimi.
- **Animasyon:** ~15 fps, sadece red/yellow iken pulse.
- (macOS'ta timer'lar `.common` modda — menü açıkken de çalışsın diye. Windows'ta
  `System.Windows.Forms.Timer` bu sorunu yaşamaz.)

---

## 9. Lokalizasyon (tüm diller — birebir)

Sistem diline göre seçilir (ilk 2 harf), bilinmeyen → İngilizce. Alanlar:
`working, asking, done, noSessions, waitingWord, workingWord, doneWord, refresh,
quit, notifyTitle, notifyMenu, activeSessions, hint`.

`label(for state)`: red→asking, yellow→working, green→done.

**Windows'ta:** dili `CultureInfo.CurrentUICulture.TwoLetterISOLanguageName` ile seç.

| key | en | tr |
|---|---|---|
| working | Working… | Çalışıyor… |
| asking | Asking a question | Soru soruyor |
| done | Done | Bitti |
| noSessions | No active Claude sessions | Aktif Claude oturumu yok |
| waitingWord | waiting | bekliyor |
| workingWord | working | çalışıyor |
| doneWord | done | bitti |
| refresh | Refresh | Yenile |
| quit | Quit | Çıkış |
| notifyTitle | Claude is waiting for you | Claude seni bekliyor |
| notifyMenu | Notifications | Bildirimler |
| activeSessions | Active sessions | Aktif oturumlar |
| hint | Click a session to jump to it | Gitmek için bir oturuma tıkla |

Diğer diller (Mac'te mevcut — istenirse taşınır): **es, de, fr, it, pt, ru, ja, zh, ko**.
Tam tablo Mac kaynağında: `../macos/Sources/ClaudeStatusCore/Localization.swift`.
Örnek (es): Trabajando… / Haciendo una pregunta / Terminado / No hay sesiones de Claude
activas / esperando / trabajando / terminado / Actualizar / Salir / Claude te está
esperando / Notificaciones / Sesiones activas / Haz clic en una sesión para abrirla.

---

## 10. Kurulum / kaldırma / autostart / doctor sorumlulukları

Mac'te bunlar shell script + uygulama içi `Bootstrap` ile yapılır. Windows'ta bir
PowerShell installer VEYA uygulamanın kendi ilk-açılış Bootstrap'ı yapabilir.

**install (yapılacaklar):**
1. Uygulamayı derle/yerleştir (Windows: `dotnet publish` ile `.exe`).
2. Hook mekanizmasını kur (Windows'ta ayrı script gerekmiyorsa exe kendisi hook — §12.1).
3. `settings.json`'a hook gruplarını **birleştir** (yedek alarak). Mac Python ile
   yapar: mevcut komutları küme olarak toplar, aynı komut yoksa ekler (idempotent).
   Marker: komut dizesinde bizim exe/hook imzamızın geçip geçmediğine bak.
4. `%USERPROFILE%\.claude\status` dizinini oluştur.
5. **Autostart:** Mac LaunchAgent. **Windows:** `HKCU\Software\Microsoft\Windows\
   CurrentVersion\Run` altına `ClaudeTrafficLight = "<exe yolu>"` yaz.
6. Uygulamayı başlat.

**uninstall:** autostart kaydını sil, süreci sonlandır, uygulamayı/hook'u kaldır,
`settings.json`'dan bizim hook gruplarımızı çıkar (yedek alarak), status dizinini sil.

**doctor:** OS sürümü, toolchain, exe var mı, imza/izinler, hook + settings bağlantısı,
autostart, çalışıyor mu — teşhis eder. (Windows'ta imza/Gatekeeper yerine SmartScreen.)

**settings.json birleştirme kuralı (Mac Python mantığı):** her olay için mevcut
grupların hook `command` kümesini çıkar; ekleyeceğin grubun komutu bu kümede yoksa
ekle. Böylece tekrar tekrar çalıştırınca çift kayıt olmaz.

---

## 11. Mevcut Mac kaynak dosyaları (referans harita)

```
../macos/
├─ Sources/ClaudeStatusCore/         (taşınabilir çekirdek — Windows'a birebir taşı)
│  ├─ StatusStore.swift              §4  (State, SessionStatus, load, aggregate, liveness)
│  ├─ SessionRouter.swift            §5  (yönlendirme kararı)
│  ├─ RedTransitionTracker.swift     §6  (bildirim geçiş takibi + PlatformLabel)
│  ├─ TTYDevice.swift                §3.3'e ek — "ps -o tty=" çıktısını "/dev/ttys000"'a
│  │                                  çevirir; Terminal.app'te doğru sekmeyi bulmak için
│  │                                  kullanılır. Windows karşılığı yok/gerekmiyor: §12.3
│  │                                  zaten MainWindowHandle + SetForegroundWindow ile
│  │                                  pencere bazlı çalışıyor, tty kavramı yok.
│  ├─ Localization.swift             §9  (tüm dil tabloları)
│  ├─ WidgetLayout.swift             §13 (widget genişlet/daralt geometrisi)
│  └─ WidgetResize.swift             §13 (widget en-boy oranı sabit sürükle-boyutlandırma)
├─ Sources/ClaudeStatus/             (AppKit UI — Windows'ta WinForms muadili)
│  ├─ AppDelegate.swift              §6,§8  (tepsi/menü, timer, bildirim, tıklama yönlendirme)
│  ├─ TrafficLightIcon.swift         §7  (ikon çizimi + appIcon)
│  ├─ MenuViews.swift                §8  (özel menü satırı/başlık/ipucu görünümleri)
│  ├─ Bootstrap.swift                §10 (ilk açılışta hook+settings+autostart kurulumu)
│  └─ main.swift                     giriş + --render/--appicon/--preview-menu debug modları
├─ Sources/ClaudeWidget/             §13 (yüzen widget — Windows karşılığı: ClaudeTrafficWidget/)
├─ hooks/
│  ├─ claude-status-hook.sh          §3  (hook mantığı — Windows'ta exe --hook muadili)
│  └─ settings-snippet.json          §3.1 (olay→durum şablonu)
├─ build-app.sh / build-dmg.sh                     tepsi uygulaması paketleme
├─ build-widget-app.sh / build-widget-dmg.sh       widget paketleme
├─ install.sh / install-autostart.sh / uninstall.sh / doctor.sh   §10
└─ README.md / README.tr.md
```

---

## 12. Windows uyarlama notları (özet karar listesi)

### 12.1 Hook mekanizması — TEK EXE önerisi
Ayrı bir PowerShell hook yerine, **tepsi exe'sinin kendisi hook** olsun:
- `settings.json` komutu: `"<tam exe yolu>" --hook <state>`
- `Program.Main`: `args[0] == "--hook"` ise → hook işini yap (stdin JSON oku, status
  dosyası yaz) ve **hemen çık** (pencere/tepsi açma); aksi halde tepsi uygulamasını başlat.
- Avantaj: PowerShell bağımlılığı yok, native hızda başlar, her araç çağrısında **konsol
  penceresi titremesi olmaz** (WinExe alt sistemi konsol açmaz).
- stdin: WinExe olsa da ebeveyn (Claude) stdin'i pipe olarak yönlendirdiği için
  `Console.OpenStandardInput()` okunabilir. Try/catch ile sar; boşsa `{}` kabul et.

### 12.2 Process ağacı (platform + session_pid) — hızlı yöntem
`CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS)` + `Process32First/Next` ile
`pid → (parentPid, exeName)` haritası kur (hızlı, WMI'a gerek yok). Kendi PID'inden
yukarı en fazla ~8 seviye yürü, exe adlarından platformu tespit et (§3.3 Windows satırı),
`session_pid` = ilk `node.exe` atası. Hepsini try/catch ile sar — hook asla patlamasın,
en kötü ihtimalle `platform=unknown, pid=0` yaz.

### 12.3 Pencere öne getirme (terminal/unknown yönlendirme)
`Process.GetProcessById(pid).MainWindowHandle` → `ShowWindow(hWnd, SW_RESTORE)` +
`SetForegroundWindow(hWnd)` (user32.dll P/Invoke). Handle yoksa Explorer'da/editörde
klasörü aç.

### 12.4 Bağımlılıklar / build
- `net8.0-windows`, `<UseWindowsForms>true</UseWindowsForms>`, `OutputType=WinExe`.
- Yüksek DPI: `<ApplicationHighDpiMode>PerMonitorV2</ApplicationHighDpiMode>` +
  `ApplicationConfiguration.Initialize()`.
- Harici NuGet paketi gerekmez (System.Text.Json + System.Drawing + WinForms yeterli;
  process ağacı için P/Invoke).
- Yayınlama (kullanıcı hiçbir şey kurmasın): kendi kendine yeten tek dosya:
  `dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true`
  → tek `ClaudeTrafficLight.exe`.

### 12.5 Kalıcı ayarlar
- Bildirim aç/kapa: `HKCU\Software\ClaudeTrafficLight` (`Microsoft.Win32.Registry`).
- Autostart: `HKCU\...\CurrentVersion\Run`.

### 12.6 Özet: neler DEĞİŞMEZ (sözleşme)
- Status dizini `%USERPROFILE%\.claude\status\`, dosya adı `<session>.json`, JSON alanları,
  atomik yazım, olay→durum eşlemesi, kırmızı override kuralı, 30 dk bayatlık, öncelik
  sıralaması, agregasyon, bildirim-geçiş kuralı, renkler, lokalizasyon dizeleri.
- Bunlar Mac ile birebir aynı kalırsa iki platform aynı `~/.claude` altında sorunsuz
  birlikte çalışır.

### 12.7 Neler DEĞİŞİR (platform uyarlaması)
- Menü çubuğu → sistem tepsisi (NotifyIcon + özel çizilmiş flyout, §8'e bkz — plan
  aşamasında `ContextMenuStrip` düşünülmüştü, piksel-hassas boşluk için özel
  `MenuFlyout` form'a geçildi).
- Yatay ikon → dikey ikon (kare tepsi yuvası).
- bash+python hook → tek exe `--hook`.
- `kill(pid,0)` → `Process.GetProcessById`; `SIGTERM` → `Process.Kill`/`CloseMainWindow`.
- .app öne getirme → `SetForegroundWindow`.
- LaunchAgent → registry Run key.
- UNUserNotification → `NotifyIcon.ShowBalloonTip` / toast.
- Gatekeeper → SmartScreen (imzasız exe ilk çalıştırmada uyarı verebilir).

---

## 13. Widget portu (ClaudeTrafficWidget)

macOS'taki yüzen widget (`Sources/ClaudeWidget/`, bkz. [`macos/README.md`](../macos/README.md#floating-desktop-widget-optional))
Windows'a **birebir davranışça** taşındı: `windows/ClaudeTrafficWidget/`. Sözleşme
tarafı (§2-4, §9) tepsi uygulamasıyla aynı — widget kendi ayrı bir veri kaynağı
icat etmez, aynı `%USERPROFILE%\.claude\status\` sözleşmesini **salt okunur**
tüketir.

**Ürün:** kenarlıksız, sürüklenebilir, her zaman üstte tutulabilen bir masaüstü
paneli. Sol tarafta dikey trafik ışığı (kırmızı üstte/sarı ortada/yeşil altta, §7
ile aynı çizim/renk/pulse mantığı — `TrafficLightPanel.cs`, Mac'te
`VerticalTrafficLightView.swift`), yanında canlı oturum listesi
(`SessionRowControl` — tepsi menüsüyle ortak/paylaşılan control).

**Salt okunur kural (önemli):** widget hiçbir zaman hook kurmaz, `settings.json`'a
dokunmaz. Bu yüzden veri akması için tepsi uygulamasının (`ClaudeTrafficLight.exe`)
en az bir kez çalıştırılmış olması gerekir — bunu kuran o.

**Davranışlar (her iki platformda ortak):**
- Başlık çubuğundan veya ışığın kendisinden tut, sürükle, bırak (herhangi bir
  ekran konumuna).
- Pin (her zaman üstte) aç/kapa — başlık çubuğundaki 📌 / sağ tık menüsü.
- Daralt: sadece trafik ışığından oluşan küçük bir rozete döner, kenar/köşeden
  sürükleyerek yeniden boyutlandırılabilir (**en-boy oranı sabit** — Mac:
  `WidgetLayout.swift`/`WidgetResize.swift`, Windows: `WidgetResize.cs`, aynı
  min/max kelepçeleme ve köşe-sabitleme mantığı, ikisi de birim testli). Tekrar
  tıklayarak genişlet.
- Oturum satırına tıklama → §5 yönlendirmesiyle aynı; ✕ oturumu sonlandırır.
- Sağ tık: Show list, Always on top, Open at Login, Close widget.
- Konum, pin durumu, genişlet/daralt durumu kalıcı ve tepsi uygulamasından
  bağımsız (Mac: ayrı `UserDefaults` anahtarları; Windows: ayrı registry anahtarı
  `HKCU\Software\ClaudeTrafficWidget`, bkz. `WidgetSettings.cs`).

**Windows'a özgü uygulama detayları:**
- Sürükleme/kenar-boyutlandırma: `WidgetNative.cs` (P/Invoke — `WM_NCLBUTTONDOWN`
  ile sürükle, `WM_SIZING` ile kenar/köşe boyutlandırma; Mac'te AppKit'in kendi
  `mouseDown`/`mouseDragged`'i + `NSCursor` kullanılıyor).
- Tek örnek kuralı: `Mutex("ClaudeTrafficWidget_SingleInstance")` — otomatik
  başlatma + elle açma iki widget üst üste yığmasın diye (Mac: `NSApplication`
  `applicationShouldHandleReopen` zaten var olan pencereyi öne getiriyor).
- Debug modu: `ClaudeTrafficWidget.exe --capture <out.png> [dark|light]` — gerçek
  durum dizinine dokunmadan, bellek-içi örnek oturumlarla widget'ı bir PNG'ye çizer
  (Mac karşılığı: `ClaudeStatus --preview-menu` benzeri, ama widget'a özel).
- Paylaşılan kod: `ClaudeTrafficWidget.csproj`, tepsi projesine referans **vermeden**
  `Core/`, `Platform/`, `UI/MenuTheme.cs`, `UI/SessionRowControl.cs`,
  `UI/RelativeTime.cs` dosyalarını doğrudan link'ler (aynı ad alanlarıyla derlenir)
  — iki proje birbirinden bağımsız `.exe` olarak kalsın diye.

Ayrıntılı dosya haritası ve build/publish komutları:
[`windows/README.md`](README.md#floating-desktop-widget-optional).
