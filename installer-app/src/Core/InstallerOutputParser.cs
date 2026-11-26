using System;
using System.Text.RegularExpressions;

namespace HermesKurulum.Core
{
    public sealed class InstallerProgress
    {
        public string Phase { get; set; }      // Turkish phase label, null = unchanged
        public double? Fraction { get; set; }  // 0..1 of the installer step, null = unchanged
        public string Detail { get; set; }
        public string BackupPath { get; set; }
        public string ErrorText { get; set; }
        public bool Restoring { get; set; }
    }

    /// <summary>Turns the bundle installer's console output (InstallOrUpdateHermesAirgapped.ps1, factory 4.8.x)
    /// into Turkish phases and a progress fraction. Unknown lines are simply logged.</summary>
    public sealed class InstallerOutputParser
    {
        static readonly Regex Verify = new Regex(@"^\[INFO\]\s+(\d+)\s*/\s*(\d+)\s*$");
        static readonly Regex Backup = new Regex(@"^\[INFO\] Backup: (.+)$");
        bool _nextIsStepTitle;
        public int TotalFiles { get; set; }
        public string LastPhase { get; private set; }

        static readonly (string prefix, string label, double at)[] Steps =
        {
            ("Hermes air-gapped install/update", "Paket kontrol ediliyor", 0.02),
            ("Backup of settings", "Ayarlar yedekleniyor (config, .env, oturumlar)", 0.05),
            ("Preparing the new Desktop app", "Yeni sürüm kopyalanıyor (birkaç dakika)", 0.10),
            ("Switching to the new version", "Yeni sürüme geçiliyor (eski sürüm saklanıyor)", 0.88),
            ("Commands, launchers and user settings", "Kısayollar, PATH ve kullanıcı ayarları", 0.92),
            ("Config migration", "Ayar dosyası yeni sürüme taşınıyor (config migrate)", 0.96),
            ("Done", "Kurulum tamamlandı", 1.0),
            ("Hermes rollback", "Geri alma: önceki kurulum geri yükleniyor", 0.10),
        };

        public InstallerProgress Feed(string line)
        {
            if (line == null) return null;
            string t = line.Trim();
            if (t.StartsWith("=====", StringComparison.Ordinal)) { _nextIsStepTitle = !_nextIsStepTitle; return null; }
            if (_nextIsStepTitle && t.Length > 0)
            {
                foreach (var s in Steps)
                    if (t.StartsWith(s.prefix, StringComparison.OrdinalIgnoreCase))
                    {
                        LastPhase = s.label;
                        return new InstallerProgress { Phase = s.label, Fraction = s.at };
                    }
                return new InstallerProgress { Phase = t };
            }
            if (t.StartsWith("[INFO] Verifying every file", StringComparison.Ordinal))
                return new InstallerProgress { Phase = "Dosyalar SHA256 ile doğrulanıyor", Fraction = 0.45 };
            if (t.StartsWith("[INFO] Copying Desktop app", StringComparison.Ordinal))
                return new InstallerProgress { Detail = "Uygulama dosyaları kopyalanıyor", Fraction = 0.12 };
            var m = Verify.Match(t);
            if (m.Success)
            {
                double n = double.Parse(m.Groups[1].Value), tot = double.Parse(m.Groups[2].Value);
                if (tot <= 0) tot = Math.Max(1, TotalFiles);
                return new InstallerProgress { Fraction = 0.45 + 0.40 * Math.Min(1, n / tot), Detail = m.Groups[1].Value + " / " + m.Groups[2].Value + " dosya doğrulandı" };
            }
            if (t.StartsWith("[INFO] All ", StringComparison.Ordinal) && t.EndsWith("files verified.", StringComparison.Ordinal))
                return new InstallerProgress { Fraction = 0.85, Detail = "Tüm dosyalar doğrulandı" };
            if (t.StartsWith("[INFO] CLI:", StringComparison.Ordinal))
                return new InstallerProgress { Detail = "Yeni CLI test edildi: " + t.Substring(11).Trim() };
            var b = Backup.Match(t);
            if (b.Success) return new InstallerProgress { BackupPath = b.Groups[1].Value.Trim(), Detail = "Yedek: " + b.Groups[1].Value.Trim() };
            if (t.StartsWith("[ERROR]", StringComparison.Ordinal)) return new InstallerProgress { ErrorText = t.Substring(7).Trim() };
            if (t.IndexOf("Restoring the previous installation", StringComparison.OrdinalIgnoreCase) >= 0)
                return new InstallerProgress { Restoring = true, Phase = "Hata: önceki kurulum geri yükleniyor" };
            return null;
        }
    }
}
