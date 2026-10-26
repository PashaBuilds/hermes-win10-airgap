# Hermes Media Tools Airgap Pack v1

Bu paket, Hermes için offline medya/diyagram/teknik animasyon araçlarını ayrı bir air-gapped pack olarak hazırlar.

Oluşturulma tarihi: 2026-06-17 14:32:12

## Kapsam

Aşama 1:
- FFmpeg + ffprobe
- Graphviz
- Mermaid CLI
- Basic Hermes media skills
- Demo diyagram dosyaları

Aşama 2:
- Manim
- Python media wheelhouse
- Manim demo scene

HyperFrames, PlantUML/JRE ve ComfyUI dahil değildir; onları ayrı aşama olarak ele almak daha temiz.

## Internetli bilgisayarda build

```cmd
cd /d C:\HermesMediaToolsAirgapPack_v1
BuildHermesMediaToolsAirgapPack.bat
```

Çıktı:

```text
C:\HermesMediaToolsFactory\output\HermesMediaToolsAirgapPack_v1.zip
```

NPM sertifika/proxy problemi olursa:

```powershell
powershell -ExecutionPolicy Bypass -File .\BuildHermesMediaToolsAirgapPack.ps1 -UseNpmInsecure
```

veya CA dosyasıyla:

```powershell
powershell -ExecutionPolicy Bypass -File .\BuildHermesMediaToolsAirgapPack.ps1 -NpmCafile C:\path\to\internet_proxy_chain.pem
```

## Intranet bilgisayarda kurulum

ZIP'i aç:

```text
C:\HermesMediaToolsDeploy\HermesMediaToolsAirgapPack_v1
```

Çalıştır:

```cmd
cd /d C:\HermesMediaToolsDeploy\HermesMediaToolsAirgapPack_v1
InstallHermesMediaToolsAirgapped.bat
```

Temiz Manim venv için:

```cmd
InstallHermesMediaToolsAirgapped.bat CleanVenv
```

## Kurulum sonrası test

Yeni CMD/PowerShell aç:

```cmd
ffmpeg -version
ffprobe -version
dot -V
mmdc --version
python -m manim --version
```


## v1-intranet-npm Notu

Bu sürümde Mermaid CLI internetli bilgisayarda `npm install` yapmaz. Sadece `npm\mermaid-cli\package.json` hazırlar. Mermaid kurulumu intranet bilgisayardaki `InstallHermesMediaToolsAirgapped.bat` sırasında, şirketin desteklediği npm ortamı ile yapılır.

Böylece internet tarafında kurumsal proxy / npm sertifika sorunları yüzünden build kesilmez. Intranet tarafında npm erişimi destekleniyorsa Mermaid CLI orada tamamlanır.

Ayrıca `package.json` ASCII yazılır; Windows PowerShell 5.1'in UTF-8 BOM eklemesi nedeniyle oluşan `Unexpected token '﻿'` JSON hatası önlenir.
