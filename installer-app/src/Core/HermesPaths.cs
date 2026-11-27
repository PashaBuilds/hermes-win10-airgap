using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace HermesKurulum.Core
{
    /// <summary>Where Hermes lives on this machine. Mirrors the bundle installer
    /// (InstallOrUpdateHermesAirgapped.ps1): %LOCALAPPDATA%\hermes is the install folder,
    /// HERMES_HOME (User env) or that folder holds config.yaml/.env/sessions.</summary>
    public sealed class HermesPaths
    {
        public string LocalAppData { get; }
        public string HomeDir { get; }       // %LOCALAPPDATA%\hermes
        public string HermesHome { get; }    // config.yaml, .env, sessions ...
        public string AppDir => Path.Combine(HomeDir, "app");
        public string LegacySourceDir => Path.Combine(HomeDir, "hermes-agent");
        public string PayloadDir => Path.Combine(AppDir, "resources", "agent-payload");
        public string HermesExe => Path.Combine(PayloadDir, "bin", "hermes.exe");
        public string StartDesktopBat => Path.Combine(HomeDir, "StartHermesDesktop.bat");
        public string DesktopExe => Path.Combine(AppDir, "Hermes Agent.exe");
        public string InstallStamp => Path.Combine(AppDir, "resources", "install-stamp.json");
        public string CompanyCaPem => Path.Combine(HermesHome, "company-ca.pem");
        public string CompanyCaBundle => Path.Combine(HermesHome, "company-ca-bundle.pem");

        public HermesPaths(string localAppData, string userHermesHome)
        {
            if (string.IsNullOrWhiteSpace(localAppData)) throw new InvalidOperationException("LOCALAPPDATA tanımlı değil.");
            LocalAppData = localAppData;
            HomeDir = Path.Combine(localAppData, "hermes");
            HermesHome = string.IsNullOrWhiteSpace(userHermesHome) ? HomeDir : userHermesHome.Trim();
        }

        public static HermesPaths ForCurrentUser(IEnvironmentStore env)
        {
            return new HermesPaths(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                                   env.GetUser("HERMES_HOME"));
        }

        /// <summary>"v0.23.0" from app\resources\install-stamp.json, "eski (venv) kurulum" for the
        /// pre-Desktop layout, null when nothing is installed.</summary>
        public InstalledInfo DetectInstalled()
        {
            var info = new InstalledInfo();
            if (File.Exists(InstallStamp))
            {
                try
                {
                    var j = MiniJson.ParseObject(File.ReadAllText(InstallStamp));
                    var v = j.Str("displayVersion");
                    if (string.IsNullOrEmpty(v)) v = j.Str("baseVersion");
                    if (string.IsNullOrEmpty(v)) v = j.Str("tag");
                    info.Version = NormalizeVersion(v);
                    info.Runtime = RuntimeInfo.FromStamp(PayloadDir, j);
                }
                catch (Exception ex) { info.Note = "install-stamp.json okunamadı: " + ex.Message; }
                info.Kind = InstallKind.Desktop;
            }
            else if (Directory.Exists(AppDir))
            {
                info.Kind = InstallKind.Desktop;
                info.Note = "Sürüm bilgisi bulunamadı (install-stamp.json yok).";
            }
            else if (Directory.Exists(LegacySourceDir))
            {
                info.Kind = InstallKind.Legacy;
                info.Note = "Eski (venv) kurulum";
            }
            return info;
        }

        public static string NormalizeVersion(string v)
        {
            if (string.IsNullOrWhiteSpace(v)) return null;
            v = v.Trim();
            return v.StartsWith("v", StringComparison.OrdinalIgnoreCase) ? "v" + v.Substring(1) : "v" + v;
        }

        /// <summary>-1/0/1 comparison of "v0.23.0" style versions (non-numeric parts ignored).</summary>
        /// <summary>"Hermes Agent v0.23.4 · stable" matches "v0.23.4" (whole version token: 0.23.40 or 10.23.4 do not).</summary>
        public static bool VersionMatches(string versionOutput, string release)
        {
            if (string.IsNullOrEmpty(versionOutput) || string.IsNullOrEmpty(release)) return false;
            var want = release.Trim().TrimStart('v', 'V');
            return System.Text.RegularExpressions.Regex.IsMatch(versionOutput, "(?<![0-9.])v?" + System.Text.RegularExpressions.Regex.Escape(want) + "(?![0-9])");
        }

        public static int CompareVersions(string a, string b)
        {
            int[] pa = Parts(a), pb = Parts(b);
            for (int i = 0; i < Math.Max(pa.Length, pb.Length); i++)
            {
                int x = i < pa.Length ? pa[i] : 0, y = i < pb.Length ? pb[i] : 0;
                if (x != y) return x < y ? -1 : 1;
            }
            return 0;
        }

        static int[] Parts(string v)
        {
            if (string.IsNullOrEmpty(v)) return new int[0];
            return v.TrimStart('v', 'V').Split('.', '-', '+')
                    .Select(p => { int n; return int.TryParse(new string(p.TakeWhile(char.IsDigit).ToArray()), out n) ? n : 0; })
                    .ToArray();
        }
    }

    public enum InstallKind { None, Legacy, Desktop }

    public sealed class InstalledInfo
    {
        public InstallKind Kind { get; set; } = InstallKind.None;
        public string Version { get; set; }
        public string Note { get; set; }
        public RuntimeInfo Runtime { get; set; }
        public bool IsInstalled => Kind != InstallKind.None;
        public string Display => Kind == InstallKind.None ? "Kurulu değil" : (Version ?? Note ?? "Kurulu (sürüm bilinmiyor)");
    }

    /// <summary>The Hermes payload runtime, as described in install-stamp.json -> runtime.</summary>
    public sealed class RuntimeInfo
    {
        public string PayloadDir { get; set; }
        public string Python { get; set; }          // tools\python-x.y\python.exe (the store Python)
        public string SitePackages { get; set; }    // venv\Lib\site-packages
        public string RepoDir { get; set; }         // hermes-agent source
        public string HermesExe { get; set; }       // bin\hermes.exe
        public string CertifiBundle => SitePackages == null ? null : Path.Combine(SitePackages, "certifi", "cacert.pem");

        public static RuntimeInfo FromStamp(string payloadDir, Dictionary<string, object> stamp)
        {
            var rt = stamp.Obj("runtime");
            var r = new RuntimeInfo { PayloadDir = payloadDir };
            string Rel(string p) => string.IsNullOrEmpty(p) ? null : Path.Combine(payloadDir, p.Replace('/', Path.DirectorySeparatorChar));
            r.Python = Rel(rt.Str("storePython"));
            r.SitePackages = Rel(rt.Str("sitePackages", "venv/Lib/site-packages"));
            r.RepoDir = Rel(rt.Str("repoDir", "hermes-agent"));
            var cmds = rt.Obj("commands");
            r.HermesExe = Rel(cmds.Str("hermes", "bin/hermes.exe"));
            if (r.Python == null || !File.Exists(r.Python))
            {
                // Fallback: tools\python-*\python.exe
                var tools = Path.Combine(payloadDir, "tools");
                if (Directory.Exists(tools))
                    r.Python = Directory.GetDirectories(tools, "python-*")
                        .Select(d => Path.Combine(d, "python.exe")).FirstOrDefault(File.Exists) ?? r.Python;
            }
            return r;
        }

        public string Problem()
        {
            if (Python == null || !File.Exists(Python)) return "Hermes Python'u bulunamadı: " + (Python ?? "(tanımsız)");
            if (SitePackages == null || !Directory.Exists(SitePackages)) return "site-packages bulunamadı: " + SitePackages;
            if (RepoDir == null || !Directory.Exists(RepoDir)) return "hermes-agent klasörü bulunamadı: " + RepoDir;
            return null;
        }
    }
}
