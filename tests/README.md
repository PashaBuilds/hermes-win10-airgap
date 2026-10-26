# Testler

| Dosya | Ne yapar | Nasıl |
|---|---|---|
| `parse.ps1` | Script'leri PowerShell parser'ıyla parse eder; Windows PowerShell 5.1'de çalışmayacak PS 7 sözdizimini (`??`, `?.`, `&&`, `\|\|`, ternary) yakalar | `pwsh -File tests/parse.ps1 <dosya.ps1>...` (Windows'ta: `factory\...\ValidateFactoryScripts.bat`) |
| `check_worker.py` | Factory worker'ını bir Hermes checkout'una karşı çalıştırır; win32-x64 araç seçimini ve bağımlılık zincirini gösterir, upstream hook'ları kaymışsa uyarır | `python3 -I tests/check_worker.py <hermes-src>` |
| `sim/run-sim.sh` | Linux + PowerShell 7 + stub exe'lerle uçtan uca simülasyon: factory `-PackageOnly`, installer'ın 10 senaryosu, CLI pilot v1.2, masaüstü delta kiti | `PWSH=/path/to/pwsh tests/sim/run-sim.sh` (zip, unzip, git gerekli) |
| `sim/stubs/` | `robocopy.exe`, `tar.exe`, `hermes.exe` ve `Hermes Agent.exe` yerine geçen bash script'leri | — |

Son çalıştırma (26.10.2026): `run-sim.sh` **27/27 PASS**. `check_worker.py`, v0.22.2 ve v0.22.4 kaynaklarında **OK** verdi.

**Sınır:** Simülasyon Windows PowerShell 5.1 ve .NET Framework'e özgü davranışları kanıtlayamaz. Ayrıntılar `docs/05-test-ve-dogrulama.md` içinde.
