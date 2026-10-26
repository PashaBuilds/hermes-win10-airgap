# HermesAirgapFactory

Bu klasör, internetli Windows bilgisayarda Hermes air-gapped bundle üretimini düzenli tutmak için hazırlanmış şablondur.

Oluşturulma tarihi: 2026-06-15 15:18:48

## Klasör yapısı

```text
HermesAirgapFactory/
├── factory/
│   └── hermes_latest_flexible_airgap_factory/
│       └── internetli makinede bundle hazırlama scriptleri burada tutulur
│
├── output/
│   ├── HermesAirgapBundle_<tag>.zip
│   ├── HermesRunner_latest.zip
│   └── old_bundles/
│
├── cert/
│   ├── HermesSertifika.zip
│   ├── my_company.crt
│   ├── install_hermes_company_cert.py
│   └── run_install_cert.bat
│
├── logs/
│   └── üretim logları
│
└── docs/
    └── kullanım notları
```

## İnternetli bilgisayarda kullanım

1. Bu ZIP'i örneğin şu dizine aç:

```text
C:\HermesAirgapFactory
```

2. CMD aç:

```cmd
cd /d C:\HermesAirgapFactory\factory\hermes_latest_flexible_airgap_factory
PrepareHermesLatestAirgapBundle.bat
```

3. Üretilen `HermesAirgapBundle_<tag>.zip` dosyasını şu klasöre taşı:

```text
C:\HermesAirgapFactory\output
```

## Intranet bilgisayara taşınacak dosyalar

Genelde şu dosyaları taşıman yeterli:

```text
C:\HermesAirgapFactory\output\HermesAirgapBundle_<tag>.zip
C:\HermesAirgapFactory\output\HermesRunner_latest.zip
C:\HermesAirgapFactory\cert\HermesSertifika.zip
```

Intranet tarafı için önerilen hedef yapı:

```text
C:\HermesDeploy\
├── bundles\
├── runner\
├── cert\
└── logs\
```

## Notlar

- Hermes kurulu çalışma alanı `%LOCALAPPDATA%\hermes` olarak kalmalıdır.
- Bundle/runner/sertifika arşivlerini `%LOCALAPPDATA%\hermes` içine koyma.
- Model ayarında `Custom endpoint` seçilecek, `Custom API` seçilmeyecek.
- Base URL `/v1` ile bitmeli.


## Güncel çıktı davranışı

Bu paket, internet tarafında üretilen bundle ZIP dosyasını Desktop yerine varsayılan olarak burada tutacak şekilde güncellendi:

```text
C:\HermesAirgapFactory\output\HermesAirgapBundle_<tag>.zip
```

Geçici çalışma klasörü de burada tutulur:

```text
C:\HermesAirgapFactory\work\HermesAirgapBundle_<tag>
```

Normal kullanım:

```cmd
cd /d C:\HermesAirgapFactory\factory\hermes_latest_flexible_airgap_factory
PrepareHermesLatestAirgapBundle.bat
```

Güncelleme tarihi: 2026-06-15 15:25:26
