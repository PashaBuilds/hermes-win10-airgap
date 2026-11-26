using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.RegularExpressions;

namespace HermesKurulum.Core
{
    public enum CertState
    {
        /// <summary>No company certificate anywhere: a .crt file is needed.</summary>
        NotInstalled,
        /// <summary>Everything in place. Nothing to do (at most a silent bundle refresh, see NeedsBundleRefresh).</summary>
        Installed,
        /// <summary>Company certificate known, but a file or variable is missing/wrong: repair silently from it.</summary>
        Partial,
        /// <summary>All known company certificates have expired: a new .crt file is needed.</summary>
        Expired,
    }

    /// <summary>Result of <see cref="CertificateStatus.Detect"/>: is the company CA already set up for Hermes?</summary>
    public sealed class CertStatusInfo
    {
        public CertState State { get; set; } = CertState.NotInstalled;
        public List<CertInfo> Certificates { get; } = new List<CertInfo>();
        /// <summary>Where the company certificate(s) were found (company-ca.pem or a legacy bundle).</summary>
        public string Source { get; set; }
        /// <summary>Found only through the old cert script's setup (no company-ca.pem yet).</summary>
        public bool Legacy { get; set; }
        /// <summary>Things a silent repair (no .crt, no Windows prompt) fixes. Turkish, user-facing.</summary>
        public List<string> Missing { get; } = new List<string>();
        /// <summary>The certifi part of the bundle differs from the installed Hermes' certifi (typically after an update).</summary>
        public bool NeedsBundleRefresh { get; set; }
        /// <summary>CA certificates not in the CurrentUser store (informational; adding it is optional and shows a prompt).</summary>
        public List<CertInfo> NotInStore { get; } = new List<CertInfo>();
        public bool StoreChecked { get; set; }
        public DateTime? EarliestExpiry => Certificates.Count == 0 ? (DateTime?)null : Certificates.Min(c => c.Cert.NotAfter);
        public bool ExpiresSoon { get; set; }
        public bool AnyExpired { get; set; }
        public bool NeedsAction => State == CertState.Partial || NeedsBundleRefresh;

        public string Describe()
        {
            if (Certificates.Count == 0) return "Kurulu şirket sertifikası bulunamadı.";
            return string.Join(", ", Certificates.Select(c => c.Subject + " (son geçerlilik " + c.Cert.NotAfter.ToString("dd.MM.yyyy") + ")"));
        }
    }

    /// <summary>Detects an existing company CA setup so the certificate step is done only once.
    /// Checks, without changing anything:
    ///   - HERMES_HOME\company-ca.pem parses to ≥1 certificate;
    ///   - HERMES_HOME\company-ca-bundle.pem exists and contains all of them;
    ///   - User SSL_CERT_FILE / REQUESTS_CA_BUNDLE / CURL_CA_BUNDLE point to the bundle, NODE_EXTRA_CA_CERTS to company-ca.pem;
    ///   - optionally whether the CA certificates are in CurrentUser Root/CA;
    ///   - legacy (old install_hermes_company_cert.py): the env vars point to an existing bundle whose trailing
    ///     certificates are not part of certifi -> those are the company certificates.</summary>
    public static class CertificateStatus
    {
        public const int ExpiryWarningDays = 30;
        static readonly Regex PemCert = new Regex("-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", RegexOptions.Singleline);

        public static List<X509Certificate2> ParsePem(string text)
        {
            var list = new List<X509Certificate2>();
            foreach (Match m in PemCert.Matches(text ?? ""))
            {
                try { list.Add(new X509Certificate2(Convert.FromBase64String(Regex.Replace(m.Groups[1].Value, "\\s", "")))); }
                catch { /* skip a broken block */ }
            }
            return list;
        }

        static string ReadText(string path)
        {
            try { return File.Exists(path) ? File.ReadAllText(path, Encoding.UTF8) : null; } catch { return null; }
        }

        static bool SamePath(string a, string b) =>
            !string.IsNullOrEmpty(a) && !string.IsNullOrEmpty(b) &&
            string.Equals(a.Trim().Trim('"').TrimEnd('\\', '/'), b.Trim().Trim('"').TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase);

        static string Normalize(string s) => (s ?? "").Replace("\r\n", "\n").Trim('\n', ' ', '\uFEFF');

        /// <summary>certifi part of a bundle = everything before our marker.</summary>
        public static string CertifiPart(string bundleText)
        {
            if (bundleText == null) return null;
            int cut = bundleText.IndexOf(CertificateTools.BundleMarker, StringComparison.Ordinal);
            return cut >= 0 ? bundleText.Substring(0, cut) : null;
        }

        /// <param name="inStore">thumbprint lookup in CurrentUser Root/CA; null = do not check the store.</param>
        public static CertStatusInfo Detect(HermesPaths paths, IEnvironmentStore env, string certifiPath,
                                            Func<CertInfo, bool> inStore, DateTime now)
        {
            var st = new CertStatusInfo();
            var certifiText = ReadText(certifiPath);
            var certifiThumbs = new HashSet<string>(ParsePem(certifiText).Select(c => c.Thumbprint), StringComparer.OrdinalIgnoreCase);

            // 1) company certificates: company-ca.pem first, else a legacy bundle the env vars point to
            var pemText = ReadText(paths.CompanyCaPem);
            var fromPem = ParsePem(pemText);
            if (fromPem.Count > 0) { st.Source = paths.CompanyCaPem; foreach (var c in fromPem) st.Certificates.Add(new CertInfo { Cert = c }); }
            else
            {
                foreach (var candidate in new[] { env.GetUser("SSL_CERT_FILE"), env.GetUser("REQUESTS_CA_BUNDLE"), env.GetUser("CURL_CA_BUNDLE"), paths.CompanyCaBundle }
                                          .Where(p => !string.IsNullOrWhiteSpace(p)).Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    var found = LegacyCompanyCerts(ReadText(candidate), certifiThumbs);
                    if (found.Count == 0) continue;
                    st.Source = candidate; st.Legacy = true;
                    foreach (var c in found) st.Certificates.Add(new CertInfo { Cert = c });
                    break;
                }
            }
            if (st.Certificates.Count == 0) { st.State = CertState.NotInstalled; return st; }

            // 2) expiry
            st.AnyExpired = st.Certificates.Any(c => c.Cert.NotAfter < now);
            st.ExpiresSoon = st.Certificates.Any(c => c.Cert.NotAfter >= now && c.Cert.NotAfter < now.AddDays(ExpiryWarningDays));
            if (st.Certificates.All(c => c.Cert.NotAfter < now)) { st.State = CertState.Expired; return st; }

            // 3) files
            if (fromPem.Count == 0) st.Missing.Add("company-ca.pem yok (eski sertifika betiğiyle kurulmuş; bundan oluşturulacak)");
            var bundleText = ReadText(paths.CompanyCaBundle);
            if (bundleText == null) st.Missing.Add("company-ca-bundle.pem yok");
            else
            {
                var inBundle = new HashSet<string>(ParsePem(bundleText).Select(c => c.Thumbprint), StringComparer.OrdinalIgnoreCase);
                if (!st.Certificates.All(c => inBundle.Contains(c.Cert.Thumbprint))) st.Missing.Add("company-ca-bundle.pem şirket sertifikasını içermiyor");
                else if (certifiText != null)
                {
                    // Hermes update brought a different certifi: refresh silently (see README "Sertifika bir kez kurulur").
                    var part = CertifiPart(bundleText);
                    if (part == null || Normalize(part) != Normalize(certifiText)) st.NeedsBundleRefresh = true;
                }
            }

            // 4) user environment variables
            foreach (var v in CertificateInstaller.BundleVars)
                if (!SamePath(env.GetUser(v), paths.CompanyCaBundle)) st.Missing.Add(v + " ayarlı değil ya da başka bir dosyayı gösteriyor");
            if (!SamePath(env.GetUser(CertificateInstaller.NodeVar), paths.CompanyCaPem))
                st.Missing.Add(CertificateInstaller.NodeVar + " ayarlı değil ya da başka bir dosyayı gösteriyor");

            // 5) Windows store: informational only (adding is optional and needs a Windows prompt)
            if (inStore != null)
            {
                st.StoreChecked = true;
                foreach (var c in st.Certificates.Where(c => c.IsCa != false))
                    if (!inStore(c)) st.NotInStore.Add(c);
            }

            st.State = st.Missing.Count == 0 ? CertState.Installed : CertState.Partial;
            return st;
        }

        /// <summary>Old script: certifi + company cert(s) appended at the end. Company certs = the trailing
        /// certificates not in the current certifi (stop at the first certifi one, so roots that certifi
        /// later removed are never mistaken for company certificates). Our own bundles: after the marker.</summary>
        public static List<X509Certificate2> LegacyCompanyCerts(string bundleText, HashSet<string> certifiThumbs)
        {
            var result = new List<X509Certificate2>();
            if (string.IsNullOrEmpty(bundleText)) return result;
            int cut = bundleText.IndexOf(CertificateTools.BundleMarker, StringComparison.Ordinal);
            if (cut >= 0) return ParsePem(bundleText.Substring(cut));
            if (certifiThumbs == null || certifiThumbs.Count == 0) return result;   // cannot tell company from public roots
            var all = ParsePem(bundleText);
            for (int i = all.Count - 1; i >= 0; i--)
            {
                if (certifiThumbs.Contains(all[i].Thumbprint)) break;
                result.Insert(0, all[i]);
            }
            if (result.Count == all.Count) result.Clear();   // nothing from certifi at all: not a certifi-based bundle
            return result;
        }

        /// <summary>CurrentUser Root or CA contains the certificate (no prompt, read-only).</summary>
        public static bool InCurrentUserStore(CertInfo c)
        {
            foreach (var name in new[] { StoreName.Root, StoreName.CertificateAuthority })
            {
                try
                {
                    using (var s = new X509Store(name, StoreLocation.CurrentUser))
                    {
                        s.Open(OpenFlags.ReadOnly | OpenFlags.OpenExistingOnly);
                        if (s.Certificates.Find(X509FindType.FindByThumbprint, c.Cert.Thumbprint, false).Count > 0) return true;
                    }
                }
                catch { }
            }
            return false;
        }
    }
}
