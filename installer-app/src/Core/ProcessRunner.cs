using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace HermesKurulum.Core
{
    public sealed class ProcessResult
    {
        public int ExitCode { get; set; }
        public bool TimedOut { get; set; }
        public string StdOut { get; set; } = "";
        public string StdErr { get; set; } = "";
    }

    public static class ProcessRunner
    {
        /// <summary>Runs a process without a window, streams every output line to onLine, optionally writes stdin
        /// (used for the API key: never on the command line) and kills the whole tree on timeout.</summary>
        public static Task<ProcessResult> RunAsync(string exe, string arguments, IDictionary<string, string> env,
            string stdin, Action<string> onLine, TimeSpan timeout, CancellationToken ct, string workingDir = null)
        {
            return Task.Run(() =>
            {
                var psi = new ProcessStartInfo(exe, arguments)
                {
                    UseShellExecute = false, CreateNoWindow = true,
                    RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
                    StandardOutputEncoding = new UTF8Encoding(false), StandardErrorEncoding = new UTF8Encoding(false),
                };
                if (!string.IsNullOrEmpty(workingDir)) psi.WorkingDirectory = workingDir;
                if (env != null)
                    foreach (var kv in env)
                    {
                        if (kv.Value == null) psi.EnvironmentVariables.Remove(kv.Key);
                        else psi.EnvironmentVariables[kv.Key] = kv.Value;
                    }
                var outSb = new StringBuilder(); var errSb = new StringBuilder();
                using (var p = new Process { StartInfo = psi })
                {
                    var outDone = new ManualResetEventSlim(); var errDone = new ManualResetEventSlim();
                    p.OutputDataReceived += (s, e) => { if (e.Data == null) { outDone.Set(); return; } lock (outSb) outSb.AppendLine(e.Data); onLine?.Invoke(e.Data); };
                    p.ErrorDataReceived += (s, e) => { if (e.Data == null) { errDone.Set(); return; } lock (errSb) errSb.AppendLine(e.Data); onLine?.Invoke(e.Data); };
                    p.Start();
                    p.BeginOutputReadLine(); p.BeginErrorReadLine();
                    try
                    {
                        if (stdin != null)
                        {
                            var bytes = new UTF8Encoding(false).GetBytes(stdin);
                            p.StandardInput.BaseStream.Write(bytes, 0, bytes.Length);
                            p.StandardInput.BaseStream.Flush();
                        }
                        p.StandardInput.Close();
                    }
                    catch { }
                    var deadline = DateTime.UtcNow + timeout;
                    bool timedOut = false;
                    while (!p.WaitForExit(250))
                    {
                        if (ct.IsCancellationRequested || DateTime.UtcNow > deadline) { timedOut = !ct.IsCancellationRequested; KillTree(p); break; }
                    }
                    p.WaitForExit(10000);
                    outDone.Wait(5000); errDone.Wait(5000);
                    return new ProcessResult { ExitCode = p.HasExited ? p.ExitCode : -1, TimedOut = timedOut, StdOut = outSb.ToString(), StdErr = errSb.ToString() };
                }
            });
        }

        static void KillTree(Process p)
        {
            try
            {
                var k = Process.Start(new ProcessStartInfo("taskkill.exe", "/PID " + p.Id + " /T /F") { CreateNoWindow = true, UseShellExecute = false });
                k?.WaitForExit(10000);
            }
            catch { try { p.Kill(); } catch { } }
        }

        public static string Quote(string arg)
        {
            if (string.IsNullOrEmpty(arg)) return "\"\"";
            if (arg.IndexOfAny(new[] { ' ', '\t', '"' }) < 0) return arg;
            var sb = new StringBuilder("\"");
            int bs = 0;
            foreach (char c in arg)
            {
                if (c == '\\') { bs++; continue; }
                if (c == '"') { sb.Append('\\', bs * 2 + 1).Append('"'); bs = 0; continue; }
                sb.Append('\\', bs).Append(c); bs = 0;
            }
            return sb.Append('\\', bs * 2).Append('"').ToString();
        }
    }
}
