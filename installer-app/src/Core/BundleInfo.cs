using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace HermesKurulum.Core
{
    /// <summary>A factory v4.7+ Windows 10 Desktop bundle: either the ZIP (HermesAirgapBundle_vX_Win10_Desktop.zip)
    /// or its extracted folder (the one that contains BUNDLE.json).</summary>
    public sealed class BundleInfo
    {
        public const string InstallContract = "legacy-auto-cleanvenv-win10-desktop";
        public const string InstallerScript = "InstallOrUpdateHermesAirgapped.ps1";

        public string SourcePath { get; private set; }
        public bool IsZip { get; private set; }
        public string TopFolder { get; private set; }         // folder name inside the ZIP ("" when BUNDLE.json is at the root)
        public string Release { get; private set; }           // "v0.23.4"
        public string Factory { get; private set; }
        public long AppBytes { get; private set; }
        public int AppFiles { get; private set; }
        public long ZipBytes { get; private set; }
        public long UncompressedBytes { get; private set; }
        public int EntryCount { get; private set; }
        public int LongestEntryPath { get; private set; }
        public string ExpectedSha256 { get; private set; }    // from <zip>.sha256 when present
        public string ExtractedRoot { get; set; }             // folder with BUNDLE.json (after extraction)

        public static BundleInfo Open(string path)
        {
            if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("Yol boş.");
            if (Directory.Exists(path)) return OpenFolder(path);
            if (File.Exists(path)) return OpenZip(path);
            throw new FileNotFoundException("Paket bulunamadı: " + path);
        }

        static BundleInfo OpenFolder(string dir)
        {
            dir = Path.GetFullPath(dir);
            string meta = Path.Combine(dir, "BUNDLE.json");
            if (!File.Exists(meta))
            {
                // The user may have picked the parent folder (C:\Tools\HermesAirgapBundle): look one level down.
                var sub = Directory.GetDirectories(dir).Where(d => File.Exists(Path.Combine(d, "BUNDLE.json")))
                                   .OrderByDescending(d => d, StringComparer.OrdinalIgnoreCase).FirstOrDefault();
                if (sub == null) throw new InvalidDataException("Bu klasörde BUNDLE.json yok. Hermes paketinin (ZIP'ten çıkan) klasörünü seçin.");
                dir = sub; meta = Path.Combine(dir, "BUNDLE.json");
            }
            var b = new BundleInfo { SourcePath = dir, IsZip = false, ExtractedRoot = dir, TopFolder = Path.GetFileName(dir) };
            b.ReadMeta(File.ReadAllText(meta, Encoding.UTF8));
            if (!File.Exists(Path.Combine(dir, InstallerScript)))
                throw new InvalidDataException(InstallerScript + " paket klasöründe yok; ZIP'in tamamını çıkarın.");
            return b;
        }

        static BundleInfo OpenZip(string zipPath)
        {
            zipPath = Path.GetFullPath(zipPath);
            var b = new BundleInfo { SourcePath = zipPath, IsZip = true, ZipBytes = new FileInfo(zipPath).Length };
            using (var z = ZipFile.OpenRead(zipPath))
            {
                ZipArchiveEntry meta = null;
                foreach (var e in z.Entries)
                {
                    b.EntryCount++;
                    b.UncompressedBytes += e.Length;
                    var name = e.FullName.Replace('\\', '/');
                    b.LongestEntryPath = Math.Max(b.LongestEntryPath, name.Length);
                    var parts = name.Split('/');
                    if (parts[parts.Length - 1] == "BUNDLE.json" && parts.Length <= 2 && (meta == null || parts.Length < meta.FullName.Split('/').Length))
                        meta = e;
                }
                if (meta == null) throw new InvalidDataException("ZIP içinde BUNDLE.json yok; bu bir Hermes airgap paketi değil.");
                var mparts = meta.FullName.Replace('\\', '/').Split('/');
                b.TopFolder = mparts.Length == 2 ? mparts[0] : "";
                using (var r = new StreamReader(meta.Open(), Encoding.UTF8)) b.ReadMeta(r.ReadToEnd());
                string prefix = b.TopFolder.Length > 0 ? b.TopFolder + "/" : "";
                if (z.GetEntry(prefix + InstallerScript) == null)
                    throw new InvalidDataException("ZIP içinde " + InstallerScript + " yok.");
            }
            var shaFile = zipPath + ".sha256";
            if (File.Exists(shaFile)) b.ExpectedSha256 = ParseShaFile(File.ReadAllText(shaFile));
            return b;
        }

        void ReadMeta(string json)
        {
            var j = MiniJson.ParseObject(json);
            if ((int)j.Num("schema") != 5 || j.Str("installContract") != InstallContract)
                throw new InvalidDataException("Bu paket factory v4.7+ Windows 10 Desktop paketi değil (schema/installContract uyuşmuyor).");
            Release = HermesPaths.NormalizeVersion(j.Str("release"));
            Factory = j.Str("factory");
            AppBytes = (long)j.Num("appBytes");
            AppFiles = (int)j.Num("appFiles");
            if (string.IsNullOrEmpty(Release)) throw new InvalidDataException("BUNDLE.json içinde release yok.");
        }

        public static string ParseShaFile(string text)
        {
            foreach (var tok in (text ?? "").Split(new[] { ' ', '\t', '\r', '\n', '*' }, StringSplitOptions.RemoveEmptyEntries))
                if (tok.Length == 64 && tok.All(Uri.IsHexDigit)) return tok.ToLowerInvariant();
            return null;
        }

        /// <summary>Longest absolute path the extraction would create (Windows MAX_PATH is 260).</summary>
        public int LongestExtractedPath(string targetBase)
        {
            var t = (targetBase ?? "").Trim();
            bool windowsAbsolute = t.Length >= 3 && char.IsLetter(t[0]) && t[1] == ':' && (t[2] == '\\' || t[2] == '/');
            if (!windowsAbsolute) t = Path.GetFullPath(t);
            return t.TrimEnd('\\', '/').Length + 1 + LongestEntryPath;
        }

        public static string ComputeSha256(string file, Action<double> progress, CancellationToken ct)
        {
            using (var sha = SHA256.Create())
            using (var s = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20))
            {
                var buf = new byte[1 << 20];
                long total = s.Length, done = 0; int n; int lastPct = -1;
                while ((n = s.Read(buf, 0, buf.Length)) > 0)
                {
                    ct.ThrowIfCancellationRequested();
                    sha.TransformBlock(buf, 0, n, null, 0);
                    done += n;
                    int pct = total == 0 ? 100 : (int)(done * 100 / total);
                    if (pct != lastPct) { lastPct = pct; progress?.Invoke(pct / 100.0); }
                }
                sha.TransformFinalBlock(buf, 0, 0);
                return BitConverter.ToString(sha.Hash).Replace("-", "").ToLowerInvariant();
            }
        }

        /// <summary>Extract into targetBase (e.g. C:\Tools\HermesAirgapBundle). Returns the folder that holds BUNDLE.json.
        /// A previous extraction of a bundle in the same place is removed first (the installer refuses stray files).</summary>
        public string Extract(string targetBase, Action<double, string> progress, Action<string> log, CancellationToken ct)
        {
            if (!IsZip) return ExtractedRoot;
            targetBase = Path.GetFullPath(targetBase);
            Directory.CreateDirectory(targetBase);
            string root = TopFolder.Length > 0 ? Path.Combine(targetBase, TopFolder) : targetBase;
            if (TopFolder.Length == 0 && Directory.EnumerateFileSystemEntries(targetBase).Any())
                throw new IOException("Hedef klasör boş değil: " + targetBase + ". Boş bir klasör seçin.");
            if (Directory.Exists(root))
            {
                if (!File.Exists(Path.Combine(root, "BUNDLE.json")))
                    throw new IOException("Hedefte paket olmayan bir klasör var: " + root + ". Başka bir klasör seçin ya da onu kaldırın.");
                log?.Invoke("Önceki açılmış paket kaldırılıyor: " + root);
                ForceDeleteDirectory(root);
            }
            string baseWithSep = targetBase.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            using (var z = ZipFile.OpenRead(SourcePath))
            {
                long total = Math.Max(1, z.Entries.Sum(e => e.Length)), done = 0; int count = 0, all = z.Entries.Count;
                var buf = new byte[1 << 16];
                foreach (var e in z.Entries)
                {
                    ct.ThrowIfCancellationRequested();
                    string dest = Path.GetFullPath(Path.Combine(targetBase, e.FullName.Replace('/', Path.DirectorySeparatorChar)));
                    if (!dest.StartsWith(baseWithSep, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidDataException("ZIP içinde hedef dışına çıkan yol var: " + e.FullName);
                    if (e.FullName.EndsWith("/") || e.FullName.EndsWith("\\")) { Directory.CreateDirectory(dest); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(dest));
                    using (var src = e.Open())
                    using (var dst = new FileStream(dest, FileMode.CreateNew, FileAccess.Write, FileShare.None, 1 << 16))
                    {
                        int n;
                        while ((n = src.Read(buf, 0, buf.Length)) > 0) { dst.Write(buf, 0, n); done += n; }
                    }
                    try { File.SetLastWriteTime(dest, e.LastWriteTime.DateTime); } catch { }
                    count++;
                    if (count % 200 == 0 || count == all) progress?.Invoke((double)done / total, count + " / " + all + " dosya");
                }
            }
            ExtractedRoot = root;
            if (!File.Exists(Path.Combine(root, "BUNDLE.json"))) throw new InvalidDataException("Çıkarma sonrası BUNDLE.json bulunamadı.");
            return root;
        }

        public static void ForceDeleteDirectory(string dir)
        {
            foreach (var f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
            {
                try { File.SetAttributes(f, FileAttributes.Normal); } catch { }
            }
            Directory.Delete(dir, true);
        }
    }
}
