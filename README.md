# Minimal Windows OT Test Lab — Uygulama Rehberi

Bu rehber, `Minimal_Windows_OT_Test_Lab_Uygulama_Plani.docx` dokumanindaki
planin calisir hale getirilmis versiyonudur. Adimlar dokumandaki Asama 0-10
numaralandirmasiyla birebir eslesir.

## ÖNCE OKUYUN: Karar Gerekli — OpenPLC imaji

Plan dokumaninda referans verilen "OpenPLC Runtime" adi iki farkli, birbiriyle
**uyumsuz** projeye isaret edebiliyor:

| Secenek | Ne sunuyor | Bu planla uyumlu mu? |
|---|---|---|
| `ghcr.io/autonomy-logic/openplc-runtime` (yeni v3 rewrite) | Sadece :8443 REST API. Web UI yok, Modbus TCP:502 yok. | **Hayir** — FUXA/Telegraf'in Modbus okuyacagi bir port sunmuyor. |
| `thiagoralves/OpenPLC_v3` (klasik OpenPLC, kaynaktan derleniyor) | Web UI :8080 + Modbus TCP :502 | **Evet** — Bolum 6 register haritasi ve tum mimari bu projeye dayanir. |

`openplc/Dockerfile` **klasik projeyi** kaynaktan derleyecek sekilde
hazirlandi (Docker Hub'da guncel resmi imaj artik yok). Ilk build ~5-10 dk
surer (derleme). Bu karari degistirmek isterseniz `openplc/Dockerfile`
icindeki notu okuyup community imaji `jpaffrath/docker-openplc` ile
degistirebilirsiniz.

## Asama 0 — Host Readiness

```powershell
cd minimal-ot-lab
.\tests\validation\asama0-host-readiness.ps1
```

Kabul kriterleri (dokuman Bolum 11.1 ile ayni):
- [ ] Docker Engine erisilebilir
- [ ] Docker Compose mevcut
- [ ] WSL 2 operasyonel
- [ ] hello-world container basarili
- [ ] **Production OT baglantisi yok** — VPN/kurumsal ag KAPALI, IP
      konfigurasyonu incelendi

Bu kriterlerin hepsi gecmeden bir sonraki asamaya gecmeyin.

## Asama 1 — Network Temeli

```powershell
copy .env.example .env
notepad .env    # tum CHANGE_ME degerlerini doldurun
```

`compose.yaml` icinde `plc_net`, `collection_net`, `central_ot_net` ayri
bridge network'ler olarak tanimli. **`internal: true` kasitli olarak
kullanilmiyor** — Docker bu bayrakla isaretli network'lerde host port-publish
(127.0.0.1:xxxx) icin gerekli NAT altyapisini kurmuyor, bu da openplc/fuxa/
influxdb/grafana'nin host'a hic acilamamasina yol acardi (bunu biz de canli
olarak yasadik). Network'ler arasi izolasyon zaten hangi container'in hangi
network'e bagli oldugundan geliyor — bu, internal:true olmadan da gecerli bir
Docker garantisidir. Sadece asagidakiyle olusturun, servisleri henuz baslatmayin:

```powershell
docker compose config    # syntax dogrulama
docker network ls        # bu asamada henuz gorunmeyecek, "up" ile olusur
```

**Kabul kriteri dogrulamasi** servisler ayaga kalktiktan sonra yapilir
(Asama 2-8'i bitirdiginizde asagidaki komutla teyit edin):

```powershell
docker network inspect minimal-ot-lab_central_ot_net --format '{{json .Containers}}'
# openplc/fuxa'nin BURADA GORUNMEMESI gerekir
```

## Asama 2 — OpenPLC

```powershell
docker compose build openplc
docker compose up -d openplc
docker compose logs -f openplc      # webserver basladi mi kontrol edin
```

Tarayicidan **http://127.0.0.1:8080** adresine gidin (yalnizca localhost —
bu, dashboard/login arayuzudur; ayni container ayrica :8443'te OpenPLC
Editor icin ayri bir HTTPS REST API sunar, biz onu kullanmiyoruz):

1. Ilk girişte varsayilan kullanici `openplc` / şifre `openplc` ile giriş
   yapin, **hemen sifreyi degistirin** (Users sayfasi).
2. **Programs** sayfasindan `openplc/project/wind_turbine_sim.st`
   dosyasini yukleyip derleyin (Compile).
3. **Hardware** sayfasinda "Generic Modbus TCP Device" degil — bu
   OpenPLC'nin kendisi Modbus SERVER'dir; bu sayfada plc program
   degiskenlerinizin (%MW0-4, %QX0.0-1) Modbus adreslerine eslendigini
   dogrulayin (varsayilan eslesme genelde otomatiktir, "Modbus Server"
   ayarindan port 502'nin acik oldugunu kontrol edin).
4. **Settings** sayfasinda Modbus Server'in **enabled** oldugunu ve
   port 502 oldugunu teyit edin.

**ONEMLI - Modbus adres offseti (canli dogrulandi):** klasik OpenPLC'de
holding-register adres uzayi SABIT olarak 0-1023 = `%QW`, 1024-2047 = `%MW`
seklinde bolunmustur (`core/modbus.cpp`, `ReadHoldingRegisters`). ST
programindaki "%MW0" ismi Modbus holding register adresi **0 degil,
1024**'tur:

| ST degiskeni | Modbus holding register adresi (0-based) |
|---|---|
| %MW0 WindSpeed | **1024** |
| %MW1 RotorSpeed | **1025** |
| %MW2 ActivePower | **1026** |
| %MW3 GeneratorTemperature | **1027** |
| %MW4 OperatingState | **1028** |

Adres 0-4'ten okumak hep `0` doner (orada tanimli bir `%QW` olmadigi icin) -
bu, ilk denemede "degerler hic guncellenmiyor" seklinde yanlis bir sonuca
yol acabilir; dogrulama icin:

```powershell
docker exec otlab-openplc python3 -c "from pymodbus.client.sync import ModbusTcpClient; c=ModbusTcpClient('127.0.0.1',502); c.connect(); print(c.read_holding_registers(1024,5,unit=1).registers); c.close()"
```

Coil adresleri (`%QX0.0`/`%QX0.1`, function code 1/5/15) bu offsetten
etkilenmez, duz 0/1 adresinde kalir — bu yuzden coil okumalari basindan
beri dogru gorunuyordu.

**Kabul kriterleri:**
```powershell
docker inspect -f '{{.State.Health.Status}}' otlab-openplc   # healthy olmali
docker exec otlab-openplc sh -c "netstat -tlnp 2>/dev/null | grep 502"
docker compose restart openplc   # restart sonrasi program/config korunuyor mu?
```

**Not:** Modbus TCP:502, Flask webserver'dan (8443) AYRI bir "core" runtime
process'idir — sadece Programs sayfasinda bir program compile edip
**Start PLC** dedikten sonra acilir. Program durdurulursa (Stop PLC) 502
de kapanir; bu normaldir, T01/T02 testlerinden once PLC'nin "running"
oldugunu UI'dan teyit edin.

## Asama 3 — FUXA

```powershell
docker compose up -d fuxa
```

Tarayicidan **http://127.0.0.1:1881** — ilk girişte admin hesabi
olusturun (`.env` icindeki `FUXA_ADMIN_PASSWORD` ile ayni sifreyi kullanin).

1. **Devices** → yeni Modbus TCP cihazi ekleyin: host `openplc`, port `502`
   (Slave IP alanina `openplc:502` yazin — `127.0.0.1` DEGIL, FUXA kendi
   container'inin icinden bakar, OpenPLC'ye ancak Docker service adiyla
   ulasir).
2. Tag'leri Bolum 6 haritasina gore tanimlayin (WindSpeed, RotorSpeed,
   ActivePower, GeneratorTemperature, OperatingState, TurbineRunning,
   GeneralAlarm).

   **ONEMLI - FUXA'nin KENDI adresleme kurali (canli capture ile dogrulandi,
   bkz. Asama 2'deki 1024 offset notundan FARKLI bir kural):** FUXA'nin tag
   Address alani, klasik Modicon "4x referans" biçimini kullanıyor ve
   girilen sayidan 1 CIKARARAK gercek 0-based Modbus adresine ceviriyor
   (holding register icin), coil'lerde de ayni sekilde 1-based:

   | Tag | Gercek Modbus adresi (0-based) | FUXA'ya girilecek adres |
   |---|---|---|
   | WindSpeed (holding) | 1024 | **401025** |
   | RotorSpeed (holding) | 1025 | **401026** |
   | ActivePower (holding) | 1026 | **401027** |
   | GeneratorTemperature (holding) | 1027 | **401028** |
   | OperatingState (holding) | 1028 | **401029** |
   | TurbineRunning (coil) | 0 | **1** |
   | GeneralAlarm (coil) | 1 | **2** |

   Bunu +1 yapmadan girerseniz (`401024` gibi) her tag bir onceki tag'in
   degerini gosterir (WindSpeed alaninda hep 0, RotorSpeed alaninda aslinda
   wind_speed degeri vs.) - degerler GELIYOR ama YANLIS/kaymis oluyor, bu da
   ilk bakista "calisiyor" sanilip gozden kacabilir; formul tutarliligini
   (rotor_speed = wind_speed*2, active_power = wind_speed^2/3) kontrol
   ederek yakaladik. Ayrica bir tag'in Address alani BOS birakilirsa (orn.
   TurbineRunning ilk denemede), FUXA TUM batch okumasini
   `RangeError: Received -1` ile cokertip HICBIR tag'in degerini
   guncellemiyor - bos adres alani birakmayin.
3. Bir **View** olusturup canli degerleri ve alarm gostergesini ekleyin.
4. Projeyi kaydedin (appdata volume'a yazilir — restart sonrasi kalici
   olmali).

**Kabul kriterleri:** canli degerler goruluyor (dogrulandi — formul
tutarliligi ile teyit edildi: RotorSpeed=WindSpeed*2, ActivePower=
WindSpeed^2/3), alarm biti degisiyor (GeneralAlarm=1, sicaklik>70C fault
durumunda), `docker compose restart fuxa` sonrasi proje kayboluyor mu diye
kontrol edin.

## Asama 4 — Modbus Capture (Capture A)

Wireshark **host** uzerinde calisir (container degil). Docker Desktop
WSL2 backend kullandigi icin en pratik yontem, Windows tarafinda
`Npcap`/Wireshark ile **WSL (hyper-v virtual switch)** arayuzunu
dinlemektir, veya container ici capture icin:

```powershell
docker exec otlab-openplc sh -c "which tcpdump" 2>$null
# yoksa: docker run --rm --network container:otlab-openplc nicolaka/netshoot tcpdump -i any -w /dev/stdout port 502 > captures\modbus\capture-a-$(Get-Date -Format yyyyMMdd-HHmmss).pcap
```

Wireshark display filter: `modbus` (alternatif: `tcp.port == 502`).

**Kabul kriterleri:** TCP/502 goruluyor, request-response eslesiyor,
function code + register adresi okunabiliyor, **production adresi
gorunmuyor** (lab subnetleri 172.20.x.x disinda bir IP olmamali).

## Asama 5 — Telegraf

`telegraf/telegraf.conf` zaten Bolum 6 register haritasina gore
hazirlandi (scaling dahil — starlark processor ile 85→8.5, 145→14.5,
620→62.0 donusumleri yapiliyor). Adresler **1024-1028** olarak
duzeltildi (bkz. Asama 2'deki Modbus offset notu — %MW0 = holding
register 1024, adres 0 degil — telegraf ham 0-based adres kullanir,
FUXA'nin +1 Modicon kurali burada GECERLI DEGIL).

**ONEMLI - Telegraf 1.31 modbus plugin'inde canli yakalanan 2 zorunlu
alan (dokumantasyonda "opsiyonel" gorunse de bos birakilirsa crash-loop):**
- `name` (cihaz adi) — `name_override`'dan FARKLI bir alan, bos kalirsa
  `device name is empty` hatasi.
- Her `holding_registers` girdisinde `scale` — bos kalirsa `0.0`
  varsayilip `invalid scale '0.000000'` hatasi. Olcekleme zaten asagida
  starlark processor'de yapildigi icin `scale = 1.0` (degistirmeden gecir)
  ile aciliyor.

```powershell
docker compose up -d telegraf
docker compose logs -f telegraf   # "Got N request(s) touching..." satirlarini,
                                   # hic modbus hatasi olmadigini bekleyin
```

**Not:** Bu asamada InfluxDB/firewall henuz kurulu olmadigindan
`[outputs.influxdb_v2] ... context deadline exceeded` hatasi NORMALDIR —
sadece Modbus OKUMA tarafinin hatasiz oldugunu dogrulayin. InfluxDB+firewall
kurulunca bu hata kendiliginden kaybolur.

**Kabul kriterleri:** loglarda modbus okuma hatasi yok, config
`:ro` mount edildigi icin container ici degistirilemez, `.env` icindeki
token secret olarak env_file ile geliyor (compose.yaml icinde acik
metin yok).

## Asama 6 — InfluxDB

```powershell
docker compose up -d influxdb
docker compose logs influxdb
```

**http://127.0.0.1:8086** — `.env` icindeki admin kullanici/sifre ile
giris yapin. Ilk kurulum `DOCKER_INFLUXDB_INIT_*` degiskenleriyle
otomatik yapilir (org: `otlab`, bucket: `turbine`).

Ardindan **least-privilege** icin iki ek token olusturun (InfluxDB UI →
Load Data → API Tokens → Generate Token → Custom API Token):
- Telegraf icin: sadece `turbine` bucket'ina **write**.
- Grafana icin: sadece `turbine` bucket'ina **read**.

Bu degerleri `.env` dosyasindaki `INFLUXDB_TELEGRAF_TOKEN` ve
`INFLUXDB_GRAFANA_TOKEN` alanlarina yazin, sonra:

```powershell
docker compose up -d --force-recreate telegraf grafana
```

**Kabul kriterleri:** `docker compose restart influxdb` sonrasi veri
kayboluyor mu kontrol edin (volume kalici olmali), token'larin
scope'unun admin token'dan farkli/daha kisitli oldugunu teyit edin.

## Asama 7 — Grafana

```powershell
docker compose up -d grafana
```

**http://127.0.0.1:3000** — provisioning ile datasource ve
"OT Lab / Turbine Overview" dashboard'u otomatik gelir
(`grafana/provisioning/`). `.env` icindeki admin sifresi ile giris
yapin — **varsayilan `admin/admin` KULLANILMAMALI**, zaten
`GF_SECURITY_ADMIN_PASSWORD` ile override edildi.

**Kabul kriterleri:** trendler goruluyor, "Last Data Timestamp" paneli
guncel, Telegraf'i durdurup veri kesintisinin fark edildigini
gozlemleyin, UI sadece 127.0.0.1'de.

## Asama 8 — Firewall/Router

```powershell
docker compose up -d --build firewall
docker compose logs firewall
```

`firewall/entrypoint.sh` Bolum 7 politika tablosunu birebir uygular:
default-deny FORWARD, sadece Telegraf→InfluxDB:8086 DNAT+ACCEPT,
established/related donus trafigi, ve central_ot_net'ten baslatilan her
yeni baglanti loglanip dusurulur.

**Kabul kriterleri:**
```powershell
docker exec otlab-firewall iptables -L -n -v      # kural seti gorunur
docker compose stop firewall; # T07 testi: telegraf artik yazamamali
docker compose logs telegraf --tail 20            # hata beklenir
docker compose start firewall
```

## Asama 9 — Firewall Capture (Capture B)

```powershell
docker exec -d otlab-firewall tcpdump -i any -w /captures/capture-b-collector-side.pcap
# birkac dakika bekleyin, sonra:
docker exec otlab-firewall pkill tcpdump
```

Dosyalar `captures/firewall/` altinda host'ta da goruntuulenebilir
(volume mount). Wireshark'ta acip **collector-historian akisinin iki
arayuzde de** gorundugunu, **PLC/FUXA'dan dogrudan historian'a** akis
OLMADIGINI dogrulayin.

## Asama 10 — Hardening

Kontrol listesi (canli dogrulandi):

- [x] `docker compose config` ciktisinda hicbir imaj `:latest` DEGIL —
      `frangoteam/fuxa` digest ile pinlendi (`docker images --digests`
      ile alinip `frangoteam/fuxa@sha256:...` yazildi), digerleri zaten
      versiyon pinliydi.
- [x] `docker ps` ciktisinda sadece 127.0.0.1 portlari var (0.0.0.0 yok)
- [x] `docker inspect otlab-firewall --format '{{.HostConfig.CapAdd}}'`
      → sadece `[NET_ADMIN NET_RAW]`
- [x] Diger tum servislere (`openplc`, `fuxa`, `telegraf`, `influxdb`,
      `grafana`) `cap_drop: [ALL]` eklendi.

      **ISTISNA (canli dogrulandi):** `influxdb` bununla crash-loop'a
      girdi — entrypoint script'i once ROOT olarak
      `/var/lib/influxdb2/engine` dizinini olusturup sahiplendiriyor,
      sonra `su-exec` ile `influxdb` kullanicisina dusuyor
      (`setgroups()` cagirarak). Sirasiyla iki hata cikti:
        1. `mkdir: Permission denied` → `CHOWN`, `DAC_OVERRIDE`, `FOWNER`
           eklenince gecti.
        2. `su-exec: setgroups: Operation not permitted` → `SETUID`,
           `SETGID` eklenince gecti.
      Yani influxdb icin `cap_drop: ALL` + `cap_add: [CHOWN,
      DAC_OVERRIDE, FOWNER, SETUID, SETGID]` — hala "ALL"dan cok daha
      kisitli (NET_ADMIN/SYS_ADMIN/SYS_PTRACE gibi tehlikeli olanlar
      YOK), sadece dosya sahipligi + kullanici dususu icin gereken
      minimum set. Diger 4 servis (openplc/fuxa/telegraf/grafana)
      hicbir ek capability olmadan `cap_drop: ALL` ile sorunsuz calisti.
- [ ] Healthcheck'ler tanimli (openplc, influxdb zaten var — fuxa/grafana
      icin de eklemeyi degerlendirin)
- [x] `logging:` blogu (json-file, max-size 10m, max-file 3) tum
      servislerde var — zaten compose.yaml'da `x-logging` ile uygulanmis
- [x] T01-T06, T09, T10 negatif/pozitif testleri PASS (canli dogrulandi,
      tam cikti asagida)

## Test Matrisini Calistir

```powershell
# Varsayilan PowerShell script-execution politikasi yerel imzasiz .ps1
# dosyalarini engelleyebilir (PSSecurityException: UnauthorizedAccess).
# Sistem genelinde Set-ExecutionPolicy DEGISTIRMEDEN, sadece bu script
# icin tek seferlik bypass:
powershell -ExecutionPolicy Bypass -File .\tests\connectivity\run-test-matrix.ps1
```

Sonuclar `tests/validation/test-matrix-results.csv`'ye yazilir. T01/T02/T03
ve T06 icin PCAP kaniti Wireshark'tan **ayrica** eklenmelidir (Asama 4 ve
Asama 9 capture'lari bu kaniti zaten saglar).

**Script'te canli yakalanan 2 bug (duzeltildi):**
- **T04/T05 yanlis pozitif:** `curl` OpenPLC/FUXA imajlarinda kurulu degil;
  ilk versiyon `command -v curl yoksa NOROUTE yaz` mantigiyla calisiyordu —
  bu, arac yoklugu ile gercek route yoklugu arasindaki farki kaybediyor ve
  test HER ZAMAN PASS veriyordu (gercek baglanti hic denenmemis olsa da).
  Duzeltme: OpenPLC'de zaten var olan `python3` ile ve FUXA'da zaten var
  olan `node` ile gercek TCP `connect()` denemesi yapiliyor.
- **T10 yanlis negatif:** `docker ps` host'taki TUM container'lari
  listeler — lab'a ait olmayan baska projelerin container'lari (bu ortamda
  `fullstack-nginx-1`, `0.0.0.0:80` ile yayinlanan) teste dahil olup FAIL'e
  yol aciyordu. Duzeltme: `docker ps --filter "name=otlab-"` ile sadece
  lab container'lari degerlendiriliyor.
- Ayrica `Test-Case` fonksiyonundaki `$results += ...` satiri `$script:`
  on-eki olmadan fonksiyon-local bir degisken yaratiyor, disaridaki ozet
  tablosu/CSV'yi hep BOS birakiyordu (sessiz basarisizlik) — `$script:results`
  ile duzeltildi.

**Final sonuc (2026-09-28, tum duzeltmeler sonrasi):**

| ID | Test | Sonuc |
|---|---|---|
| T01/T02 | OpenPLC saglikli, Modbus:502 plc_net'te | PASS |
| T03 | InfluxDB saglikli, Telegraf firewall uzerinden yaziyor | PASS |
| T04 | OpenPLC → InfluxDB dogrudan erisim YOK | PASS |
| T05 | FUXA → InfluxDB dogrudan erisim YOK | PASS |
| T06 | Izinsiz port (9999) firewall'da reddediliyor | PASS |
| T09 | Production OT erisim yolu yok (manuel teyit) | PASS |
| T10 | otlab-* portlari yalnizca 127.0.0.1 | PASS |

## Temizleme

```powershell
docker compose down          # container'lari durdur, volume'lar kalir
docker compose down -v       # + tum volume'lari (veri) sil - DIKKAT
```

## Bilinen Sinirlamalar / Sonraki Iyilestirmeler

- `iptables -j LOG` hedefi Docker Desktop'un WSL2 kernel'inde bazi
  surumlerde calismayabilir (xt_LOG modulu). Calismazsa kanit icin
  `conntrack -L` veya tcpdump'a guvenin.
- Zaman senkronu icin ayri bir NTP kontrolu eklenmedi; container'lar
  host saatini kullanir — host saatinin dogru oldugundan emin olun.
- FUXA imaji henuz digest ile pinlenmedi (Asama 10'da yapin).
