using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace HermesKurulum.Core
{
    /// <summary>Running the installed Hermes: version check and opening chat/dashboard/desktop with the
    /// freshly written user settings (new User env vars are not yet in this process' environment).</summary>
    public static class HermesCommands
    {
        static readonly string[] UserVars = { "HERMES_HOME", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE", "NODE_EXTRA_CA_CERTS", "PYTHONUTF8", "PYTHONIOENCODING" };

        public static Dictionary<string, string> FreshEnv(HermesPaths paths, IEnvironmentStore env)
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var v in UserVars)
            {
                var val = env.GetUser(v);
                if (!string.IsNullOrEmpty(val)) d[v] = val;
            }
            d["HERMES_HOME"] = paths.HermesHome;
            d["PYTHONUTF8"] = "1";
            d["PYTHONIOENCODING"] = "utf-8";
            d["PYTHONPATH"] = null; d["PYTHONHOME"] = null;
            var bin = Path.GetDirectoryName(paths.HermesExe);
            var path = Environment.GetEnvironmentVariable("PATH") ?? "";
            d["PATH"] = bin + ";" + string.Join(";", path.Split(';').Where(p => !string.Equals(p.Trim(), bin, StringComparison.OrdinalIgnoreCase)));
            return d;
        }

        public static async Task<string> VersionAsync(HermesPaths paths, IEnvironmentStore env, Action<string> log, CancellationToken ct)
        {
            if (!File.Exists(paths.HermesExe)) return null;
            var r = await ProcessRunner.RunAsync(paths.HermesExe, "--version", FreshEnv(paths, env), null, null, TimeSpan.FromSeconds(300), ct, paths.HermesHome).ConfigureAwait(false);
            var text = (r.StdOut ?? "").Trim();
            if (r.ExitCode != 0 || text.Length == 0) { log?.Invoke("hermes --version başarısız (çıkış " + r.ExitCode + "): " + (r.StdErr ?? "").Trim()); return null; }
            return text.Split('\n').Select(l => l.Trim()).FirstOrDefault(l => l.Length > 0);
        }

        /// <summary>Opens a new console window running `hermes <args>` (chat, dashboard ...).</summary>
        public static void OpenConsole(HermesPaths paths, IEnvironmentStore env, string hermesArgs, string title)
        {
            var psi = new ProcessStartInfo("cmd.exe", "/k title " + title + " && " + ProcessRunner.Quote(paths.HermesExe) + " " + hermesArgs)
            {
                UseShellExecute = false, WorkingDirectory = paths.HermesHome,
            };
            foreach (var kv in FreshEnv(paths, env))
            {
                if (kv.Value == null) psi.EnvironmentVariables.Remove(kv.Key); else psi.EnvironmentVariables[kv.Key] = kv.Value;
            }
            Process.Start(psi);
        }

        public static void OpenDesktop(HermesPaths paths, IEnvironmentStore env)
        {
            var bat = paths.StartDesktopBat;
            var psi = File.Exists(bat)
                ? new ProcessStartInfo("cmd.exe", "/c " + ProcessRunner.Quote(bat)) { UseShellExecute = false, CreateNoWindow = true }
                : new ProcessStartInfo(paths.DesktopExe) { UseShellExecute = false };
            foreach (var kv in FreshEnv(paths, env))
            {
                if (kv.Value == null) psi.EnvironmentVariables.Remove(kv.Key); else psi.EnvironmentVariables[kv.Key] = kv.Value;
            }
            psi.EnvironmentVariables["HERMES_STREAM_READ_TIMEOUT"] = "1800";
            Process.Start(psi);
        }

        /// <summary>Hermes processes started from %LOCALAPPDATA%\hermes (the installer refuses to run while any exist).</summary>
        public static List<string> RunningHermes(HermesPaths paths)
        {
            var list = new List<string>();
            foreach (var p in Process.GetProcesses())
            {
                try
                {
                    var f = p.MainModule?.FileName;
                    if (f != null && f.StartsWith(paths.HomeDir + "\\", StringComparison.OrdinalIgnoreCase)) list.Add(p.ProcessName + " [" + p.Id + "]");
                }
                catch { }
                finally { p.Dispose(); }
            }
            return list;
        }
    }
}
