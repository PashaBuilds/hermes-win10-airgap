// Core logic tests for Hermes Kurulum Asistani. No test framework needed:
//   dotnet run --project installer-app/tests/CoreTests -- [--bundle-zip <real bundle zip>] [--sim-zip <run-sim bundle zip>]
//                                                         [--hermes-src <dir> --hermes-python <python>]
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using HermesKurulum.Core;

static class Program
{
    static int pass, fail;
    static readonly List<string> failures = new List<string>();
    static void Check(string name, bool ok, string extra = "")
    {
        if (ok) { pass++; Console.WriteLine("  PASS  " + name); }
        else { fail++; failures.Add(name); Console.WriteLine("  FAIL  " + name + (extra.Length > 0 ? "   -> " + extra : "")); }
    }

    static string Arg(string[] a, string name) { int i = Array.IndexOf(a, name); return i >= 0 && i + 1 < a.Length ? a[i + 1] : null; }

    static int Main(string[] args)
    {
        var tmp = Path.Combine(Path.GetTempPath(), "hk-tests-" + Guid.NewGuid().ToString("N").Substring(0, 8));
        Directory.CreateDirectory(tmp);
        try
        {
            Json(); Versions(); RedactorTests(); ParserTests(); CommandTests();
            Certs(tmp);
            CertInstall(tmp, Arg(args, "--certifi"));
            SyntheticZip(tmp);
            HelperResultParsing();
            var real = Arg(args, "--bundle-zip"); if (real != null) RealBundle(real, tmp);
            var sim = Arg(args, "--sim-zip"); if (sim != null) InstallerE2E(sim, tmp, Arg(args, "--pwsh") ?? "pwsh");
            var src = Arg(args, "--hermes-src"); var py = Arg(args, "--hermes-python");
            if (src != null && py != null) ModelHelperE2E(tmp, src, py, Arg(args, "--site-packages"));
        }
        catch (Exception ex) { fail++; Console.WriteLine("  FAIL  unhandled: " + ex); }
        finally { try { Directory.Delete(tmp, true); } catch { } }
        Console.WriteLine($"\nRESULT: {pass} passed, {fail} failed" + (fail > 0 ? "  (" + string.Join("; ", failures) + ")" : ""));
        return fail == 0 ? 0 : 1;
    }

    // ------------------------------------------------------------------ JSON / versions / redaction
    static void Json()
    {
        Console.WriteLine("== MiniJson");
        var o = MiniJson.ParseObject("\uFEFF{\"a\": \"x\\\"y\\u00e7\", \"n\": 5, \"b\": true, \"l\": [1, \"s\", null], \"o\": {\"k\": \"v\"}}");
        Check("parse string/escape/unicode", o.Str("a") == "x\"yç");
        Check("parse number/bool/list/object", o.Num("n") == 5 && o.Bool("b") && o.StrList("l").Count == 2 && o.Obj("o").Str("k") == "v");
        var s = MiniJson.Serialize(new Dictionary<string, object> { ["key"] = "a\"b\\c\nd", ["n"] = 10, ["t"] = true });
        var back = MiniJson.ParseObject(s);
        Check("serialize round-trip", back.Str("key") == "a\"b\\c\nd" && back.Num("n") == 10 && back.Bool("t"));
        bool threw = false; try { MiniJson.Parse("{\"a\":1,}"); } catch (FormatException) { threw = true; }
        Check("rejects malformed JSON", threw);
    }

    static void Versions()
    {
        Console.WriteLine("== versions");
        Check("v0.23.0 < v0.23.4", HermesPaths.CompareVersions("v0.23.0", "v0.23.4") < 0);
        Check("0.23.10 > 0.23.4", HermesPaths.CompareVersions("0.23.10", "v0.23.4") > 0);
        Check("equal", HermesPaths.CompareVersions("v0.23.4", "0.23.4") == 0);
        Check("normalize", HermesPaths.NormalizeVersion("0.23.4") == "v0.23.4" && HermesPaths.NormalizeVersion("V0.23.4") == "v0.23.4");
    }

    static void RedactorTests()
    {
        Console.WriteLine("== Redactor");
        var r = new Redactor(); r.Add("sk-ABCDEFGHIJKLMNOP"); r.Add("ab"); r.Add(null);
        Check("full key masked", r.Clean("key=sk-ABCDEFGHIJKLMNOP!") == "key=****!");
        Check("8-char prefix masked (Hermes echoes it)", r.Clean("Current key: sk-ABCDE...") == "Current key: ****...");
        Check("too-short secrets ignored", r.Clean("ab cd") == "ab cd");
        var dir = Path.Combine(Path.GetTempPath(), "hk-log-" + Guid.NewGuid().ToString("N"));
        var log = new LogWriter(Path.Combine(dir, "x.log"), r);
        string seen = null; log.Line += (l, t) => seen = t;
        log.Info("api key sk-ABCDEFGHIJKLMNOP used");
        var file = File.ReadAllText(log.FilePath);
        Check("log file + UI never contain the key", !file.Contains("sk-ABCDE") && !seen.Contains("sk-ABCDE") && file.Contains("****"));
        Directory.Delete(dir, true);
    }

    // ------------------------------------------------------------------ installer output parser
    static void ParserTests()
    {
        Console.WriteLine("== InstallerOutputParser (factory 4.8.x installer output)");
        var lines = new[]
        {
            "", "============================================================", "Hermes air-gapped install/update - Windows 10 Desktop (installer 4.8)", "============================================================",
            "[INFO] Bundle      : C:\\Tools\\HermesAirgapBundle\\HermesAirgapBundle_v0.23.4_Win10_Desktop",
            "", "============================================================", "Backup of settings (originals stay in place)", "============================================================",
            "[INFO] Backup: C:\\Users\\u\\AppData\\Local\\hermes_backup_before_airgap_20261127_090000",
            "", "============================================================", "Preparing the new Desktop app beside the current installation", "============================================================",
            "[INFO] Copying Desktop app to C:\\x (several minutes)", "[INFO] Verifying every file with SHA256 (a few minutes)", "[INFO]   10000 / 49963", "[INFO]   40000 / 49963",
            "[INFO] All 49963 files verified.", "[INFO] CLI: Hermes Agent v0.23.4",
            "", "============================================================", "Switching to the new version (previous one is kept)", "============================================================",
            "", "============================================================", "Config migration (backup copy taken before)", "============================================================",
            "", "============================================================", "Done", "============================================================",
            "[ERROR] boom", "[WARN] Restoring the previous installation...",
        };
        var p = new InstallerOutputParser { TotalFiles = 49963 };
        var phases = new List<string>(); double last = 0; bool mono = true; string backup = null, err = null; bool restoring = false;
        foreach (var l in lines)
        {
            var r = p.Feed(l); if (r == null) continue;
            if (r.Phase != null) phases.Add(r.Phase);
            if (r.Fraction.HasValue) { if (r.Fraction.Value + 1e-9 < last) mono = false; last = r.Fraction.Value; }
            backup = r.BackupPath ?? backup; err = r.ErrorText ?? err; restoring |= r.Restoring;
        }
        Check("all phases recognised in Turkish", phases.Contains("Ayarlar yedekleniyor (config, .env, oturumlar)") && phases.Contains("Yeni sürüme geçiliyor (eski sürüm saklanıyor)")
              && phases.Contains("Kurulum tamamlandı") && phases.Contains("Dosyalar SHA256 ile doğrulanıyor"), string.Join(" | ", phases));
        Check("progress is monotonic and ends at 1.0", mono && Math.Abs(last - 1.0) < 1e-9, "last=" + last);
        Check("backup folder captured", backup != null && backup.EndsWith("hermes_backup_before_airgap_20261127_090000"));
        Check("error + auto-restore detected", err == "boom" && restoring);
    }

    static void CommandTests()
    {
        Console.WriteLine("== powershell command line");
        var dir = @"C:\Tools\Çalışma'nın Paketi\HermesAirgapBundle_v0.23.4_Win10_Desktop";
        var cmd = BundleInstaller.BuildCommand(dir, "Auto", true);
        var expected = "& '" + Path.Combine(dir, "InstallOrUpdateHermesAirgapped.ps1").Replace("'", "''") + "'";
        Check("apostrophe in path escaped for PowerShell", cmd.Contains(expected) && cmd.Contains("Çalışma''nın"), cmd);
        Check("same as legacy command: -Mode Auto -CleanVenv", cmd.Contains("-Mode Auto -CleanVenv; exit $LASTEXITCODE"));
        Check("rollback has no -CleanVenv", !BundleInstaller.BuildCommand(@"C:\b", "Rollback", false).Contains("CleanVenv"));
        Check("Win32 arg quoting", ProcessRunner.Quote("a b\\") == "\"a b\\\\\"" && ProcessRunner.Quote("plain") == "plain" && ProcessRunner.Quote("x\"y z") == "\"x\\\"y z\"");
    }

    // ------------------------------------------------------------------ certificates
    static X509Certificate2 MakeCa(string cn, DateTimeOffset from, DateTimeOffset to, out RSA key)
    {
        key = RSA.Create(2048);
        var req = new CertificateRequest("CN=" + cn + ", O=Example Corp", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        req.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        req.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
        return req.CreateSelfSigned(from, to);
    }

    static string Pem(X509Certificate2 c) => CertificateTools.ToPem(c);

    static void Certs(string tmp)
    {
        Console.WriteLine("== certificate validation");
        var now = DateTimeOffset.Now;
        var root = MakeCa("Example Root CA", now.AddYears(-1), now.AddYears(10), out var rootKey);
        // Intermediate signed by root
        var ikey = RSA.Create(2048);
        var ireq = new CertificateRequest("CN=Example Issuing CA", ikey, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        ireq.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        var inter = ireq.Create(root, now.AddDays(-1), now.AddYears(5), new byte[] { 1, 2, 3, 4 });
        // Leaf (not a CA)
        var lkey = RSA.Create(2048);
        var lreq = new CertificateRequest("CN=llm.example.internal", lkey, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        lreq.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        var leaf = lreq.Create(root, now.AddDays(-1), now.AddYears(1), new byte[] { 5, 6, 7, 8 });
        var expired = MakeCa("Old CA", now.AddYears(-5), now.AddYears(-1), out _);

        string W(string name, byte[] data) { var p = Path.Combine(tmp, name); File.WriteAllBytes(p, data); return p; }
        string WT(string name, string text) => W(name, Encoding.ASCII.GetBytes(text));

        var r = CertificateTools.Inspect(WT("company_root.crt", Pem(root)), DateTime.Now);
        Check("PEM root (.crt, any name) accepted", r.Ok && r.Certificates.Count == 1 && r.Certificates[0].IsCa == true && r.Certificates[0].SelfSigned, string.Join(";", r.Errors));
        Check("root kind label", r.Certificates[0].Kind.StartsWith("Kök sertifika"));
        r = CertificateTools.Inspect(W("root.cer", root.RawData), DateTime.Now);
        Check("DER (.cer) accepted", r.Ok && r.Certificates.Count == 1);
        r = CertificateTools.Inspect(WT("root_crlf.pem", Pem(root).Replace("\n", "\r\n")), DateTime.Now);
        Check("CRLF PEM accepted", r.Ok);
        r = CertificateTools.Inspect(WT("bare.crt", Convert.ToBase64String(root.RawData)), DateTime.Now);
        Check("bare base64 (no BEGIN/END) accepted", r.Ok);
        r = CertificateTools.Inspect(WT("chain.pem", Pem(root) + Pem(inter) + Pem(root)), DateTime.Now);
        Check("chain: 2 unique certs, duplicate dropped", r.Ok && r.Certificates.Count == 2 && r.Certificates[1].Kind.StartsWith("Ara sertifika"));
        r = CertificateTools.Inspect(WT("leaf.crt", Pem(leaf)), DateTime.Now);
        Check("non-CA leaf: allowed with warning", r.Ok && r.Warnings.Any(w => w.Contains("CA sertifikası değil")));
        r = CertificateTools.Inspect(WT("expired.crt", Pem(expired)), DateTime.Now);
        Check("expired: refused", !r.Ok && r.Errors.Any(e => e.Contains("dolmuş")));
        var keyPem = "-----BEGIN PRIVATE KEY-----\n" + Convert.ToBase64String(rootKey.ExportPkcs8PrivateKey()) + "\n-----END PRIVATE KEY-----\n";
        r = CertificateTools.Inspect(WT("withkey.pem", Pem(root) + keyPem), DateTime.Now);
        Check("PEM with PRIVATE KEY: refused", !r.Ok && r.Errors.Any(e => e.Contains("ÖZEL ANAHTAR")));
        var pfx = (root.HasPrivateKey ? root : root.CopyWithPrivateKey(rootKey)).Export(X509ContentType.Pfx, "x");
        r = CertificateTools.Inspect(W("cert.pfx", pfx), DateTime.Now);
        Check("PFX/P12 refused", !r.Ok);
        var col = new X509Certificate2Collection { root, inter };
        r = CertificateTools.Inspect(W("chain.p7b", col.Export(X509ContentType.Pkcs7)), DateTime.Now);
        Check("PKCS#7 (.p7b) accepted", r.Ok && r.Certificates.Count == 2, string.Join(";", r.Errors));
        r = CertificateTools.Inspect(WT("notes.txt", "hello, this is not a certificate"), DateTime.Now);
        Check("random text refused", !r.Ok);
        r = CertificateTools.Inspect(W("empty.crt", new byte[0]), DateTime.Now);
        Check("empty file refused", !r.Ok);
        r = CertificateTools.Inspect(WT("html.crt", "<html><body>Login required</body></html>"), DateTime.Now);
        Check("HTML login page saved as .crt refused", !r.Ok);
        s_root = root; s_inter = inter;
    }
    static X509Certificate2 s_root, s_inter;

    static void CertInstall(string tmp, string certifi)
    {
        Console.WriteLine("== certificate install (current-user, file + env)");
        var la = Path.Combine(tmp, "LA");
        var paths = new HermesPaths(la, null);
        var env = new FakeEnvironmentStore();
        env.Values["SSL_CERT_FILE"] = @"C:\Tools\HermesSertifika\old.pem";
        var fakeCertifi = certifi ?? Path.Combine(tmp, "cacert.pem");
        if (certifi == null) File.WriteAllText(fakeCertifi, "# Issuer: CN=Public Root Ünicode\n" + Pem(MakeCa("Public Root 1", DateTimeOffset.Now.AddYears(-1), DateTimeOffset.Now.AddYears(5), out _)));
        int publicCount = CertificateTools.CountPemCertificates(File.ReadAllText(fakeCertifi));
        var check = CertificateTools.Inspect(WriteTmp(tmp, "c.crt", Pem(s_root) + Pem(s_inter)), DateTime.Now);
        var logs = new List<string>();
        var inst = new CertificateInstaller(env, logs.Add);
        var res = inst.Install(paths, check.Certificates, fakeCertifi, false, "20261127_090000");
        Check("bundle = certifi + company", res.BundleCertCount == publicCount + 2, res.BundleCertCount + " vs " + (publicCount + 2));
        Check("company-ca.pem has only company certs", CertificateTools.CountPemCertificates(File.ReadAllText(paths.CompanyCaPem)) == 2);
        Check("SSL_CERT_FILE/REQUESTS_CA_BUNDLE/CURL_CA_BUNDLE -> bundle", CertificateInstaller.BundleVars.All(v => env.GetUser(v) == paths.CompanyCaBundle));
        Check("NODE_EXTRA_CA_CERTS -> company-ca.pem", env.GetUser("NODE_EXTRA_CA_CERTS") == paths.CompanyCaPem);
        Check("previous value recorded + logged", res.PreviousEnv["SSL_CERT_FILE"] == @"C:\Tools\HermesSertifika\old.pem" && logs.Any(l => l.Contains("önceki")));
        Check("environment change broadcast", env.Broadcasts == 1);
        Check("bundle under HERMES_HOME (survives updates)", res.BundlePath.StartsWith(Path.Combine(la, "hermes")));
        // Re-run (e.g. after the next Hermes update): no duplication, backup taken.
        var res2 = inst.Install(paths, check.Certificates, fakeCertifi, false, "20261127_100000");
        Check("re-run is idempotent (same count)", res2.BundleCertCount == res.BundleCertCount);
        Check("re-run backs up the previous bundle", res2.BackupPath != null && File.Exists(res2.BackupPath));
        // Built from our own bundle as the 'certifi' source: marker cut keeps it idempotent too.
        var again = CertificateTools.BuildBundle(File.ReadAllText(paths.CompanyCaBundle), check.Certificates);
        Check("BuildBundle on its own output does not duplicate", CertificateTools.CountPemCertificates(again) == res.BundleCertCount);
        // Missing certifi still produces a usable company-only bundle.
        var res3 = inst.Install(paths, check.Certificates, Path.Combine(tmp, "nope.pem"), false, "20261127_110000");
        Check("no certifi -> company-only bundle + warning", res3.BundleCertCount == 2 && !res3.CertifiFound && logs.Any(l => l.Contains("certifi")));
        Check("bundle parses as X.509 collection", ImportCount(paths.CompanyCaBundle) == 2);
    }

    static int ImportCount(string pemPath)
    {
        var c = new X509Certificate2Collection(); c.ImportFromPemFile(pemPath); return c.Count;
    }

    static string WriteTmp(string tmp, string name, string text) { var p = Path.Combine(tmp, name); File.WriteAllText(p, text); return p; }

    // ------------------------------------------------------------------ bundle zip
    static string MakeBundleZip(string tmp, string name, string release, bool withSha, Action<ZipArchive> extra = null)
    {
        var zip = Path.Combine(tmp, name + ".zip");
        using (var z = ZipFile.Open(zip, ZipArchiveMode.Create))
        {
            void Add(string p, string t) { using (var w = new StreamWriter(z.CreateEntry(p).Open())) w.Write(t); }
            Add(name + "/BUNDLE.json", "{\"schema\":5,\"release\":\"" + release + "\",\"installContract\":\"legacy-auto-cleanvenv-win10-desktop\",\"appFiles\":2,\"appBytes\":10,\"factory\":\"4.8.1\"}");
            Add(name + "/InstallOrUpdateHermesAirgapped.ps1", "# installer");
            Add(name + "/app/Hermes Agent.exe", "x");
            Add(name + "/app/resources/agent-payload/bin/hermes.exe", "y");
            extra?.Invoke(z);
        }
        if (withSha)
        {
            using (var s = File.OpenRead(zip)) using (var h = SHA256.Create())
                File.WriteAllText(zip + ".sha256", BitConverter.ToString(h.ComputeHash(s)).Replace("-", "") + "  " + Path.GetFileName(zip) + "\n");
        }
        return zip;
    }

    static void SyntheticZip(string tmp)
    {
        Console.WriteLine("== bundle ZIP handling (synthetic)");
        var zip = MakeBundleZip(tmp, "HermesAirgapBundle_v0.23.4_Win10_Desktop", "v0.23.4", true);
        var b = BundleInfo.Open(zip);
        Check("reads BUNDLE.json inside ZIP", b.IsZip && b.Release == "v0.23.4" && b.TopFolder == "HermesAirgapBundle_v0.23.4_Win10_Desktop" && b.Factory == "4.8.1");
        Check(".sha256 found", b.ExpectedSha256 != null && b.ExpectedSha256.Length == 64);
        var actual = BundleInfo.ComputeSha256(zip, null, CancellationToken.None);
        Check("SHA256 matches .sha256", actual == b.ExpectedSha256);
        var target = Path.Combine(tmp, "Tools", "HermesAirgapBundle");
        double lastF = 0;
        var root = b.Extract(target, (f, d) => lastF = f, null, CancellationToken.None);
        Check("extracts to <target>\\<top folder>", File.Exists(Path.Combine(root, "BUNDLE.json")) && File.Exists(Path.Combine(root, "app", "Hermes Agent.exe")) && Math.Abs(lastF - 1) < 1e-9);
        File.WriteAllText(Path.Combine(root, "stray.txt"), "left from last time");
        var logs = new List<string>();
        root = BundleInfo.Open(zip).Extract(target, null, logs.Add, CancellationToken.None);
        Check("re-extract replaces previous bundle folder (no stray files)", !File.Exists(Path.Combine(root, "stray.txt")) && logs.Count == 1);
        var bf = BundleInfo.Open(target);
        Check("folder pick: parent folder resolves to bundle folder", !bf.IsZip && bf.ExtractedRoot == root && bf.Release == "v0.23.4");
        Check("long-path check", b.LongestExtractedPath(@"C:\Tools\HermesAirgapBundle") < 259 && b.LongestExtractedPath(@"C:\" + new string('x', 250)) >= 259);

        var evil = MakeBundleZip(tmp, "HermesAirgapBundle_v9.9.9_Win10_Desktop", "v9.9.9", false, z => { using (var w = new StreamWriter(z.CreateEntry("../evil.txt").Open())) w.Write("x"); });
        bool threw = false;
        try { BundleInfo.Open(evil).Extract(Path.Combine(tmp, "x"), null, null, CancellationToken.None); } catch (InvalidDataException) { threw = true; }
        Check("zip-slip entry refused", threw && !File.Exists(Path.Combine(tmp, "evil.txt")));

        var bad = Path.Combine(tmp, "other.zip");
        using (var z = ZipFile.Open(bad, ZipArchiveMode.Create)) using (var w = new StreamWriter(z.CreateEntry("readme.txt").Open())) w.Write("x");
        threw = false; try { BundleInfo.Open(bad); } catch (InvalidDataException) { threw = true; }
        Check("non-Hermes ZIP refused", threw);
        var occupied = Path.Combine(tmp, "occ"); Directory.CreateDirectory(Path.Combine(occupied, "HermesAirgapBundle_v0.23.4_Win10_Desktop")); File.WriteAllText(Path.Combine(occupied, "HermesAirgapBundle_v0.23.4_Win10_Desktop", "mine.docx"), "x");
        threw = false; try { BundleInfo.Open(zip).Extract(occupied, null, null, CancellationToken.None); } catch (IOException) { threw = true; }
        Check("never deletes a non-bundle folder of the same name", threw && File.Exists(Path.Combine(occupied, "HermesAirgapBundle_v0.23.4_Win10_Desktop", "mine.docx")));
    }

    static void RealBundle(string zip, string tmp)
    {
        Console.WriteLine("== real release ZIP: " + Path.GetFileName(zip));
        var sw = Stopwatch.StartNew();
        var b = BundleInfo.Open(zip);
        Check("real bundle metadata", b.Release != null && b.TopFolder.StartsWith("HermesAirgapBundle_") && b.AppFiles > 1000, b.Release + " " + b.TopFolder + " files=" + b.AppFiles);
        Check("real bundle .sha256 parsed", b.ExpectedSha256 != null);
        Check("C:\\Tools\\HermesAirgapBundle stays under MAX_PATH", b.LongestExtractedPath(@"C:\Tools\HermesAirgapBundle") < 259, "longest=" + b.LongestExtractedPath(@"C:\Tools\HermesAirgapBundle"));
        Console.WriteLine($"        (entries {b.EntryCount}, longest entry {b.LongestEntryPath} chars, {sw.ElapsedMilliseconds} ms)");
        var sha = BundleInfo.ComputeSha256(zip, null, CancellationToken.None);
        Check("real bundle SHA256 matches its .sha256", sha == b.ExpectedSha256);
    }

    // ------------------------------------------------------------------ installer end-to-end (Linux simulation)
    static void InstallerE2E(string simZip, string tmp, string pwsh)
    {
        Console.WriteLine("== bundle installer driven by the app (pwsh + stub exes, like tests/sim)");
        var la = Path.Combine(tmp, "LA_e2e"); var home = Path.Combine(tmp, "home_e2e");
        var H = Path.Combine(la, "hermes");
        Directory.CreateDirectory(Path.Combine(H, "hermes-agent", "venv", "Scripts")); Directory.CreateDirectory(Path.Combine(H, "sessions")); Directory.CreateDirectory(Path.Combine(home, "Desktop"));
        File.WriteAllText(Path.Combine(H, "config.yaml"), "model: deepseek  # v46\n"); File.WriteAllText(Path.Combine(H, ".env"), "KEY=x\n");
        File.WriteAllText(Path.Combine(H, "sessions", "a.json"), "s");
        Environment.SetEnvironmentVariable("LOCALAPPDATA", la); Environment.SetEnvironmentVariable("HOME", home);
        Environment.SetEnvironmentVariable("APPDATA", Path.Combine(tmp, "AD")); Environment.SetEnvironmentVariable("PROCESSOR_ARCHITECTURE", "AMD64");
        Environment.SetEnvironmentVariable("HERMES_KURULUM_TEST_POWERSHELL", pwsh);

        var b = BundleInfo.Open(simZip);
        var root = b.Extract(Path.Combine(tmp, "Tools", "HermesAirgapBundle"), null, null, CancellationToken.None);
        if (!OperatingSystem.IsWindows())   // the sim's stub "exe"s are bash scripts; ZIP extraction drops the x bit
            foreach (var f in Directory.GetFiles(root, "*.exe", SearchOption.AllDirectories))
                File.SetUnixFileMode(f, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        var before = new HermesPaths(la, null).DetectInstalled();
        Check("legacy (venv) install detected before update", before.Kind == InstallKind.Legacy);

        var parser = new InstallerOutputParser { TotalFiles = b.AppFiles };
        var phases = new List<string>(); string backup = null; double last = 0;
        var r = BundleInstaller.RunAsync(root, "Auto", line =>
        {
            var p = parser.Feed(line); if (p == null) return;
            lock (phases) { if (p.Phase != null) phases.Add(p.Phase); if (p.Fraction.HasValue) last = p.Fraction.Value; backup = p.BackupPath ?? backup; }
        }, CancellationToken.None).GetAwaiter().GetResult();
        Check("installer exit 0 via app command line", r.ExitCode == 0, r.StdOut.Split('\n').LastOrDefault(l => l.Contains("ERROR")) ?? ("exit " + r.ExitCode));
        Check("parser saw backup/switch/migrate/done", phases.Any(p => p.StartsWith("Ayarlar yedekleniyor")) && phases.Any(p => p.StartsWith("Yeni sürüme geçiliyor")) && phases.Any(p => p.StartsWith("Ayar dosyası")) && phases.Contains("Kurulum tamamlandı"), string.Join(" | ", phases));
        Check("progress reached 100%", Math.Abs(last - 1) < 1e-9);
        Check("backup folder reported", backup != null && Directory.Exists(backup));
        Check("sessions + .env kept in HERMES_HOME", File.Exists(Path.Combine(H, "sessions", "a.json")) && File.ReadAllText(Path.Combine(H, ".env")).Contains("KEY=x"));
        Check("app installed", File.Exists(Path.Combine(H, "app", "Hermes Agent.exe")));

        var rb = BundleInstaller.RunAsync(root, "Rollback", null, CancellationToken.None).GetAwaiter().GetResult();
        Check("rollback via app command line: exit 0, old install back", rb.ExitCode == 0 && Directory.Exists(Path.Combine(H, "hermes-agent")) && !Directory.Exists(Path.Combine(H, "app")));
        Environment.SetEnvironmentVariable("HERMES_KURULUM_TEST_POWERSHELL", null);
    }

    // ------------------------------------------------------------------ model helper end-to-end
    static void HelperResultParsing()
    {
        Console.WriteLine("== helper result protocol");
        var red = new Redactor(); red.Add("secret-key-123456");
        var pr = new ProcessResult { ExitCode = 0, StdOut = "noise secret-key-123456\n@@RESULT@@ {\"ok\": true, \"models\": [\"m1\"]}\n" };
        var r = ModelHelperClient.ParseResult(pr, red);
        Check("result line parsed", r.Ok && r.Data.StrList("models")[0] == "m1");
        Check("raw output redacted", !r.Raw.Contains("secret-key"));
        r = ModelHelperClient.ParseResult(new ProcessResult { ExitCode = 1, StdOut = "Traceback..." }, red);
        Check("missing result -> clear error", !r.Ok && r.Error == "no_result");
        r = ModelHelperClient.ParseResult(new ProcessResult { ExitCode = 0, StdOut = "@@RESULT@@ {\"ok\": false, \"error\": \"no_models\", \"diagnosis\": {\"code\": \"tls_untrusted\"}}" }, red);
        Check("TLS diagnosis explained in Turkish", ModelHelperClient.ExplainProbe(r).Contains("sertifika"));
    }

    static void ModelHelperE2E(string tmp, string src, string python, string sitePackages)
    {
        Console.WriteLine("== model helper end-to-end (real Hermes source + fake /v1/models)");
        var port = new Random().Next(30000, 40000);
        var server = Process.Start(new ProcessStartInfo(python, $"\"{Path.Combine(AppContext.BaseDirectory, "fake_openai_server.py")}\" {port} model-a,model-b") { UseShellExecute = false });
        try
        {
            Thread.Sleep(1200);
            var la = Path.Combine(tmp, "LA_model");
            var paths = new HermesPaths(la, null); Directory.CreateDirectory(paths.HermesHome);
            var rt = new RuntimeInfo { Python = python, SitePackages = sitePackages ?? Path.Combine(tmp, "no-site"), RepoDir = src };
            Directory.CreateDirectory(rt.SitePackages);
            var red = new Redactor();
            var client = new ModelHelperClient(paths, rt, null, red);
            client.UseScript(ModelHelperClient.ExtractScript(Path.Combine(tmp, "helper")));
            const string key = "test-key-123456";
            var url = $"http://127.0.0.1:{port}/v1";
            var p = client.ProbeAsync(url, key, CancellationToken.None).GetAwaiter().GetResult();
            Check("probe via ModelHelperClient lists models", p.Ok && p.Data.StrList("models").SequenceEqual(new[] { "model-a", "model-b" }), p.Message + " " + p.Raw);
            var bad = client.ProbeAsync(url, "wrong-key-000000", CancellationToken.None).GetAwaiter().GetResult();
            Check("wrong key -> 'API anahtarını kabul etmedi'", !bad.Ok && ModelHelperClient.ExplainProbe(bad).Contains("anahtar"));
            var a = client.ApplyAsync(url, key, "model-b", "Sirket LLM", "", "", CancellationToken.None).GetAwaiter().GetResult();
            Check("apply via ModelHelperClient", a.Ok && a.Data.Str("model") == "model-b" && a.Data.Str("key_reference").StartsWith("${"), a.Message + " | " + string.Join(" / ", a.Data.StrList("transcript").Take(12)) + " | " + a.Raw);
            var cfg = File.ReadAllText(Path.Combine(paths.HermesHome, "config.yaml"));
            Check("config.yaml: custom provider, no literal key", cfg.Contains("provider: custom") && !cfg.Contains(key));
            Check(".env holds the key (where Hermes stores it)", File.ReadAllText(Path.Combine(paths.HermesHome, ".env")).Contains(key));
            Check("nothing returned to the app contains the key", !(a.Raw ?? "").Contains(key) && !(a.Raw ?? "").Contains(key.Substring(0, 8)) && !(p.Raw ?? "").Contains(key.Substring(0, 8)));
            var s = client.ShowAsync(CancellationToken.None).GetAwaiter().GetResult();
            Check("show returns current model + display name", s.Ok && s.Data.Str("model") == "model-b" && s.Data.Str("display_name") == "Sirket LLM");
        }
        finally { try { server.Kill(); } catch { } }
    }
}
