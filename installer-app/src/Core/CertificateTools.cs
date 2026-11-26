using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.RegularExpressions;

namespace HermesKurulum.Core
{
    public sealed class CertInfo
    {
        public X509Certificate2 Cert { get; set; }
        public string Subject => Cert.GetNameInfo(X509NameType.SimpleName, false) is string s && s.Length > 0 ? s : Cert.Subject;
        public string Issuer => Cert.GetNameInfo(X509NameType.SimpleName, true) is string s && s.Length > 0 ? s : Cert.Issuer;
        public bool SelfSigned => string.Equals(Cert.Subject, Cert.Issuer, StringComparison.Ordinal);
        public bool? IsCa
        {
            get
            {
                foreach (var ext in Cert.Extensions)
                    if (ext is X509BasicConstraintsExtension bc) return bc.CertificateAuthority;
                return null;
            }
        }
        public string Kind => IsCa == true ? (SelfSigned ? "Kök sertifika (Root CA)" : "Ara sertifika (Intermediate CA)")
                            : IsCa == false ? "Sunucu/kullanıcı sertifikası (CA değil)" : (SelfSigned ? "Kendinden imzalı sertifika" : "Sertifika");
        public string Sha256Fingerprint
        {
            get { using (var h = SHA256.Create()) return BitConverter.ToString(h.ComputeHash(Cert.RawData)).Replace("-", ":"); }
        }
        public string Pem => CertificateTools.ToPem(Cert);
    }

    public sealed class CertCheck
    {
        public List<CertInfo> Certificates { get; } = new List<CertInfo>();
        public List<string> Errors { get; } = new List<string>();
        public List<string> Warnings { get; } = new List<string>();
        public bool Ok => Errors.Count == 0 && Certificates.Count > 0;
    }

    /// <summary>Reads the company CA file the user downloaded (any name: .crt/.cer/.pem, PEM or DER, one or more
    /// certificates) and installs it the way Hermes needs it.</summary>
    public static class CertificateTools
    {
        public const string BundleMarker = "# ==== Hermes Kurulum Asistani: sirket sertifikalari (asagisi) ====";
        static readonly Regex PemBlock = new Regex("-----BEGIN ([A-Z0-9 ]+)-----(.*?)-----END \\1-----", RegexOptions.Singleline);

        public static CertCheck Inspect(string path, DateTime now)
        {
            var r = new CertCheck();
            byte[] raw;
            try
            {
                var fi = new FileInfo(path);
                if (!fi.Exists) { r.Errors.Add("Dosya bulunamadı."); return r; }
                if (fi.Length == 0) { r.Errors.Add("Dosya boş."); return r; }
                if (fi.Length > 2 * 1024 * 1024) { r.Errors.Add("Dosya bir sertifika için fazla büyük (>2 MB)."); return r; }
                raw = File.ReadAllBytes(path);
            }
            catch (Exception ex) { r.Errors.Add("Dosya okunamadı: " + ex.Message); return r; }
            Parse(raw, r);
            if (r.Errors.Count > 0) return r;
            if (r.Certificates.Count == 0) { r.Errors.Add("Dosyada sertifika bulunamadı. Şirket sitesinden indirilen .crt / .cer / .pem dosyasını seçin."); return r; }
            foreach (var c in r.Certificates)
            {
                string who = "\"" + c.Subject + "\"";
                if (now > c.Cert.NotAfter) r.Errors.Add(who + " sertifikasının süresi " + c.Cert.NotAfter.ToString("dd.MM.yyyy") + " tarihinde dolmuş.");
                else if (now < c.Cert.NotBefore) r.Warnings.Add(who + " henüz geçerli değil (başlangıç " + c.Cert.NotBefore.ToString("dd.MM.yyyy") + "). Bilgisayarın saatini kontrol edin.");
                else if ((c.Cert.NotAfter - now).TotalDays < 30) r.Warnings.Add(who + " 30 günden kısa sürede doluyor (" + c.Cert.NotAfter.ToString("dd.MM.yyyy") + ").");
                if (c.IsCa == false) r.Warnings.Add(who + " bir CA sertifikası değil. Genellikle şirketin KÖK (root) sertifikası gerekir; yine de devam edebilirsiniz.");
            }
            return r;
        }

        static void Parse(byte[] raw, CertCheck r)
        {
            string text = null;
            try { text = Encoding.UTF8.GetString(raw); } catch { }
            if (text != null && text.Contains("-----BEGIN"))
            {
                foreach (Match m in PemBlock.Matches(text))
                {
                    string label = m.Groups[1].Value.Trim();
                    if (label.Contains("PRIVATE KEY"))
                    {
                        r.Errors.Add("Dosyada ÖZEL ANAHTAR var. Bu bir CA sertifikası dosyası değil; kullanmayın ve kimseyle paylaşmayın.");
                        return;
                    }
                    if (label == "PKCS7") { AddPkcs7(Convert.FromBase64String(Clean(m.Groups[2].Value)), r); continue; }
                    if (label != "CERTIFICATE" && label != "TRUSTED CERTIFICATE" && label != "X509 CERTIFICATE") continue;
                    try { Add(new X509Certificate2(Convert.FromBase64String(Clean(m.Groups[2].Value))), r); }
                    catch (Exception ex) { r.Errors.Add("PEM bloğu okunamadı: " + ex.Message); return; }
                }
                return;
            }
            // DER (binary .cer/.crt), or bare base64 without BEGIN/END lines.
            byte[] der = raw;
            if (text != null && Regex.IsMatch(text.Trim(), "^[A-Za-z0-9+/=\\r\\n]+$"))
            {
                try { der = Convert.FromBase64String(Clean(text)); } catch { der = raw; }
            }
            if (der.Length > 0 && der[0] == 0x30)
            {
                try
                {
                    var c = new X509Certificate2(der);
                    if (c.HasPrivateKey) { r.Errors.Add("Dosyada özel anahtar var (PFX/P12). Şirket CA sertifikasını (.crt/.cer) seçin."); return; }
                    Add(c, r); return;
                }
                catch { /* maybe PKCS#7 (.p7b) */ }
                try { AddPkcs7(der, r); return; } catch { }
            }
            r.Errors.Add("Dosya bir X.509 sertifikası olarak okunamadı (PEM veya DER bekleniyordu).");
        }

        static void AddPkcs7(byte[] data, CertCheck r)
        {
            var col = new X509Certificate2Collection();
            col.Import(data);
            foreach (var c in col) Add(c, r);
        }

        static void Add(X509Certificate2 c, CertCheck r)
        {
            if (r.Certificates.Any(x => x.Cert.Thumbprint == c.Thumbprint)) return;
            r.Certificates.Add(new CertInfo { Cert = c });
        }

        static string Clean(string b64) => Regex.Replace(b64, "[^A-Za-z0-9+/=]", "");

        public static string ToPem(X509Certificate2 c)
        {
            var b64 = Convert.ToBase64String(c.RawData);
            var sb = new StringBuilder("-----BEGIN CERTIFICATE-----\n");
            for (int i = 0; i < b64.Length; i += 64) sb.Append(b64, i, Math.Min(64, b64.Length - i)).Append('\n');
            return sb.Append("-----END CERTIFICATE-----\n").ToString();
        }

        /// <summary>certifi's public CA list + the company certificates. Rebuilt from scratch on every run, so it is
        /// safe to repeat after each Hermes update (a new certifi is picked up, the company block is not duplicated).</summary>
        public static string BuildBundle(string certifiText, IEnumerable<CertInfo> company)
        {
            var sb = new StringBuilder();
            if (!string.IsNullOrEmpty(certifiText))
            {
                // If the source is a bundle we wrote earlier, keep only the part above our marker.
                int cut = certifiText.IndexOf(BundleMarker, StringComparison.Ordinal);
                string pub = (cut >= 0 ? certifiText.Substring(0, cut) : certifiText).Replace("\r\n", "\n").TrimEnd('\n');
                sb.Append(pub).Append("\n\n");
            }
            sb.Append(BundleMarker).Append('\n');
            foreach (var c in company)
            {
                sb.Append("# ").Append(c.Subject).Append('\n');
                sb.Append(c.Pem);
            }
            return sb.ToString();
        }

        public static int CountPemCertificates(string text) =>
            PemBlock.Matches(text ?? "").Cast<Match>().Count(m => m.Groups[1].Value.Trim() == "CERTIFICATE");
    }

    public sealed class CertInstallResult
    {
        public string CompanyPemPath { get; set; }
        public string BundlePath { get; set; }
        public string BackupPath { get; set; }
        public int BundleCertCount { get; set; }
        public bool CertifiFound { get; set; }
        public List<string> StoreAdded { get; } = new List<string>();
        public List<string> StoreWarnings { get; } = new List<string>();
        public Dictionary<string, string> PreviousEnv { get; } = new Dictionary<string, string>();
    }

    /// <summary>Installs the company CA for Hermes, for the CURRENT USER only (no admin rights):
    ///   HERMES_HOME\company-ca.pem          company certificate(s), PEM
    ///   HERMES_HOME\company-ca-bundle.pem   certifi + company (same file name the old cert script and the
    ///                                       bundle installer's backup already use)
    ///   User env SSL_CERT_FILE / REQUESTS_CA_BUNDLE / CURL_CA_BUNDLE -> bundle, NODE_EXTRA_CA_CERTS -> company-ca.pem
    ///   optional: CurrentUser certificate store (Root / Intermediate) for Windows' own verifier.</summary>
    public sealed class CertificateInstaller
    {
        public static readonly string[] BundleVars = { "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE" };
        public const string NodeVar = "NODE_EXTRA_CA_CERTS";

        readonly IEnvironmentStore _env;
        readonly Action<string> _log;
        public CertificateInstaller(IEnvironmentStore env, Action<string> log) { _env = env; _log = log ?? (_ => { }); }

        public CertInstallResult Install(HermesPaths paths, IList<CertInfo> certs, string certifiPath, bool addToWindowsStore, string stamp)
        {
            if (certs == null || certs.Count == 0) throw new ArgumentException("Sertifika yok.");
            var res = new CertInstallResult { CompanyPemPath = paths.CompanyCaPem, BundlePath = paths.CompanyCaBundle };
            Directory.CreateDirectory(paths.HermesHome);

            string certifiText = null;
            if (!string.IsNullOrEmpty(certifiPath) && File.Exists(certifiPath))
            {
                certifiText = File.ReadAllText(certifiPath, Encoding.UTF8);
                res.CertifiFound = true;
                _log("Hermes'in genel CA listesi (certifi): " + certifiPath);
            }
            else
            {
                _log("UYARI: certifi CA listesi bulunamadı; paket yalnızca şirket sertifikasını içerecek. " +
                     "Hermes Windows sertifika deposunu da kullandığı için bu genelde sorun değildir.");
            }

            if (File.Exists(paths.CompanyCaBundle))
            {
                res.BackupPath = Path.Combine(paths.HermesHome, "company-ca-bundle_backup_" + stamp + ".pem");
                File.Copy(paths.CompanyCaBundle, res.BackupPath, true);
                _log("Önceki sertifika paketi yedeklendi: " + res.BackupPath);
            }

            var companyPem = string.Concat(certs.Select(c => "# " + c.Subject + "\n" + c.Pem));
            WriteAtomic(paths.CompanyCaPem, companyPem);
            var bundle = CertificateTools.BuildBundle(certifiText, certs);
            WriteAtomic(paths.CompanyCaBundle, bundle);
            res.BundleCertCount = CertificateTools.CountPemCertificates(File.ReadAllText(paths.CompanyCaBundle, Encoding.UTF8));
            _log("Sertifika paketi yazıldı: " + paths.CompanyCaBundle + " (" + res.BundleCertCount + " sertifika)");

            foreach (var v in BundleVars) SetVar(v, paths.CompanyCaBundle, res);
            SetVar(NodeVar, paths.CompanyCaPem, res);
            _env.Broadcast();

            if (addToWindowsStore) AddToStore(certs, res);
            return res;
        }

        void SetVar(string name, string value, CertInstallResult res)
        {
            var old = _env.GetUser(name);
            res.PreviousEnv[name] = old;
            _env.SetUser(name, value);
            _log(string.Equals(old, value, StringComparison.OrdinalIgnoreCase)
                ? "Kullanıcı değişkeni zaten doğru: " + name
                : "Kullanıcı değişkeni: " + name + " = " + value + (string.IsNullOrEmpty(old) ? "" : "  (önceki: " + old + ")"));
        }

        /// <summary>CurrentUser\Root (self-signed) or CurrentUser\CA (intermediate). Adding to Root shows a
        /// Windows confirmation prompt; call it from an STA thread and keep the prompt visible (NativeDialogs).</summary>
        public void AddToStore(IList<CertInfo> certs, CertInstallResult res)
        {
            foreach (var c in certs)
            {
                if (c.IsCa == false) { res.StoreWarnings.Add(c.Subject + ": CA olmadığı için Windows deposuna eklenmedi."); continue; }
                var storeName = c.SelfSigned ? StoreName.Root : StoreName.CertificateAuthority;
                try
                {
                    using (var store = new X509Store(storeName, StoreLocation.CurrentUser))
                    {
                        store.Open(OpenFlags.ReadWrite);
                        bool exists = store.Certificates.Find(X509FindType.FindByThumbprint, c.Cert.Thumbprint, false).Count > 0;
                        if (!exists)
                        {
                            if (storeName == StoreName.Root) _log("Windows bir güvenlik onayı penceresi açacak: sertifikayı yüklemek için \"Evet\"e basın.");
                            store.Add(c.Cert);
                        }
                        res.StoreAdded.Add(c.Subject + (exists ? " (zaten vardı)" : "") + " -> CurrentUser\\" + (storeName == StoreName.Root ? "Root" : "CA"));
                    }
                }
                catch (Exception ex)
                {
                    res.StoreWarnings.Add(c.Subject + ": Windows deposuna eklenemedi (" + ex.Message.Trim() + "). " +
                                          "Onay penceresinde \"Hayır\" seçildiyse ya da şirket politikası engelliyorsa normaldir; dosya tabanlı ayar yine geçerli.");
                }
            }
        }

        static void WriteAtomic(string path, string text)
        {
            var tmp = path + ".tmp";
            File.WriteAllText(tmp, text, new UTF8Encoding(false));
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }

        /// <summary>What is configured right now (for the "already installed" hint).</summary>
        public static string DescribeCurrent(IEnvironmentStore env)
        {
            var v = env.GetUser("SSL_CERT_FILE");
            if (string.IsNullOrEmpty(v)) return null;
            return File.Exists(v) ? v : v + " (dosya YOK)";
        }
    }
}
