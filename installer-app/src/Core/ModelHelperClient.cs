using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;

namespace HermesKurulum.Core
{
    public sealed class HelperResult
    {
        public bool Ok { get; set; }
        public Dictionary<string, object> Data { get; set; } = new Dictionary<string, object>();
        public string Raw { get; set; }
        public string Error => Data.Str("error");
        public string Message => Data.Str("message");
    }

    /// <summary>Runs Resources\hermes_model_setup.py inside the INSTALLED Hermes runtime (its own Python,
    /// its own hermes_cli code), so the model is configured exactly like `hermes model` would do it.</summary>
    public sealed class ModelHelperClient
    {
        readonly HermesPaths _paths;
        readonly RuntimeInfo _rt;
        readonly IDictionary<string, string> _extraEnv;
        readonly Redactor _redactor;
        public string ScriptPath { get; private set; }

        public ModelHelperClient(HermesPaths paths, RuntimeInfo runtime, IDictionary<string, string> extraEnv, Redactor redactor)
        {
            _paths = paths; _rt = runtime; _extraEnv = extraEnv; _redactor = redactor;
        }

        public static string ExtractScript(string targetDir)
        {
            Directory.CreateDirectory(targetDir);
            var path = Path.Combine(targetDir, "hermes_model_setup.py");
            var asm = Assembly.GetExecutingAssembly();
            string res = null;
            foreach (var n in asm.GetManifestResourceNames()) if (n.EndsWith("hermes_model_setup.py", StringComparison.Ordinal)) res = n;
            if (res == null) throw new InvalidOperationException("Gömülü yardımcı betik bulunamadı.");
            using (var s = asm.GetManifestResourceStream(res))
            using (var f = File.Create(path)) s.CopyTo(f);
            return path;
        }

        public void UseScript(string path) { ScriptPath = path; }

        public Task<HelperResult> ProbeAsync(string baseUrl, string apiKey, CancellationToken ct) =>
            RunAsync("probe", new Dictionary<string, object> { ["base_url"] = baseUrl, ["api_key"] = apiKey, ["timeout"] = 10 }, ct);

        public Task<HelperResult> ApplyAsync(string baseUrl, string apiKey, string model, string displayName, string contextLength, string apiMode, CancellationToken ct) =>
            RunAsync("apply", new Dictionary<string, object>
            {
                ["base_url"] = baseUrl, ["api_key"] = apiKey, ["model"] = model, ["display_name"] = displayName ?? "",
                ["context_length"] = contextLength ?? "", ["api_mode"] = apiMode ?? "",
            }, ct);

        public Task<HelperResult> ShowAsync(CancellationToken ct) => RunAsync("show", new Dictionary<string, object>(), ct);

        async Task<HelperResult> RunAsync(string command, Dictionary<string, object> request, CancellationToken ct)
        {
            var problem = _rt?.Problem();
            if (problem != null) return Fail("runtime_missing", problem);
            if (ScriptPath == null || !File.Exists(ScriptPath)) return Fail("script_missing", "Yardımcı betik hazır değil.");
            if (request.TryGetValue("api_key", out var k)) _redactor?.Add(k as string);
            var env = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["HERMES_HOME"] = _paths.HermesHome,
                ["PYTHONUTF8"] = "1",
                ["PYTHONIOENCODING"] = "utf-8",
                ["PYTHONPATH"] = null,
                ["PYTHONHOME"] = null,
                ["PYTHONDONTWRITEBYTECODE"] = "1",
            };
            if (_extraEnv != null) foreach (var kv in _extraEnv) env[kv.Key] = kv.Value;
            string args = "-X utf8 -E -s " + ProcessRunner.Quote(ScriptPath) + " " + command +
                          " --site-packages " + ProcessRunner.Quote(_rt.SitePackages) + " --repo " + ProcessRunner.Quote(_rt.RepoDir);
            var r = await ProcessRunner.RunAsync(_rt.Python, args, env, MiniJson.Serialize(request), null,
                                                 TimeSpan.FromSeconds(command == "apply" ? 240 : 90), ct, _paths.HermesHome).ConfigureAwait(false);
            return ParseResult(r, _redactor);
        }

        public static HelperResult ParseResult(ProcessResult r, Redactor redactor)
        {
            string raw = redactor != null ? redactor.Clean(r.StdOut + r.StdErr) : r.StdOut + r.StdErr;
            if (r.TimedOut) return new HelperResult { Ok = false, Raw = raw, Data = { ["error"] = "timeout", ["message"] = "Hermes yanıt vermedi (zaman aşımı)." } };
            foreach (var line in (r.StdOut ?? "").Split('\n'))
            {
                var t = line.Trim();
                if (!t.StartsWith("@@RESULT@@ ", StringComparison.Ordinal)) continue;
                try
                {
                    var d = MiniJson.ParseObject(t.Substring(11));
                    return new HelperResult { Ok = d.Bool("ok"), Data = d, Raw = raw };
                }
                catch (Exception ex) { return new HelperResult { Ok = false, Raw = raw, Data = { ["error"] = "bad_result", ["message"] = ex.Message } }; }
            }
            return new HelperResult { Ok = false, Raw = raw, Data = { ["error"] = "no_result", ["message"] = "Hermes yardımcı betiği sonuç döndürmedi (çıkış kodu " + r.ExitCode + ")." } };
        }

        static HelperResult Fail(string code, string msg) => new HelperResult { Ok = false, Data = { ["error"] = code, ["message"] = msg } };

        /// <summary>Turkish explanation for a failed probe.</summary>
        public static string ExplainProbe(HelperResult r)
        {
            var diag = r.Data.Obj("diagnosis");
            switch (diag.Str("code"))
            {
                case "unauthorized": return "Sunucu API anahtarını kabul etmedi (HTTP " + diag.Str("status") + "). Anahtarı kontrol edin.";
                case "not_found": return "Bu adreste model listesi yok (HTTP 404). Adresin sonunda /v1 olup olmadığını kontrol edin." + Suggest(r);
                case "tls_untrusted": return "Sunucunun sertifikasına güvenilmedi. Şirket sertifikası adımını tamamladığınızdan emin olun.";
                case "tls_error": return "TLS/SSL hatası: " + diag.Str("detail");
                case "timeout": return "Sunucu zamanında yanıt vermedi. Adres ve ağ bağlantısını kontrol edin.";
                case "connect_failed": return "Sunucuya bağlanılamadı: " + diag.Str("detail");
                case "http_error": return "Sunucu hata döndürdü (HTTP " + diag.Str("status") + ").";
                case "http_ok_unparsed": return "Sunucu yanıt verdi ama model listesi döndürmedi." + Suggest(r);
            }
            if (r.Error == "invalid_url") return "Adres http:// veya https:// ile başlamalı.";
            return string.IsNullOrEmpty(r.Message) ? "Model listesi alınamadı." : r.Message;
        }

        static string Suggest(HelperResult r)
        {
            var s = r.Data.Str("suggested_base_url");
            return string.IsNullOrEmpty(s) ? "" : " Denenebilecek adres: " + s;
        }
    }
}
