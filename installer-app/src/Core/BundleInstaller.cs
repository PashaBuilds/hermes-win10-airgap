using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace HermesKurulum.Core
{
    /// <summary>Runs the bundle's OWN installer (InstallOrUpdateHermesAirgapped.ps1, the same one the .bat runs)
    /// in Windows PowerShell 5.1, i.e. exactly `InstallOrUpdateHermesAirgapped.bat Auto CleanVenv`, and reports
    /// its progress. Backups, SHA256 verification of every file, automatic restore on failure and
    /// RollbackHermesAirgapped.bat all stay the installer's job.</summary>
    public static class BundleInstaller
    {
        public static string PowerShellExe()
        {
            // Test hook only (Linux simulation with pwsh); never set on a real machine.
            var overrideExe = Environment.GetEnvironmentVariable("HERMES_KURULUM_TEST_POWERSHELL");
            if (!string.IsNullOrEmpty(overrideExe)) return overrideExe;
            var win = Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows";
            var sysnative = Path.Combine(win, "Sysnative", "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!Environment.Is64BitProcess && File.Exists(sysnative)) return sysnative;
            return Path.Combine(win, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        }

        /// <summary>-Command text: UTF-8 console output, then the installer, then its exit code.</summary>
        public static string BuildCommand(string bundleRoot, string mode, bool cleanVenv)
        {
            string script = Path.Combine(bundleRoot, BundleInfo.InstallerScript).Replace("'", "''");
            return "[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false; " +
                   "& '" + script + "' -Mode " + mode + (cleanVenv ? " -CleanVenv" : "") + "; exit $LASTEXITCODE";
        }

        public static string BuildArguments(string bundleRoot, string mode, bool cleanVenv)
        {
            return "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command " + ProcessRunner.Quote(BuildCommand(bundleRoot, mode, cleanVenv));
        }

        public static Task<ProcessResult> RunAsync(string bundleRoot, string mode, Action<string> onLine, CancellationToken ct)
        {
            var env = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["HERMES_BUNDLE_ROOT"] = bundleRoot.TrimEnd('\\') + "\\",
                ["PYTHONPATH"] = null, ["PYTHONHOME"] = null,
            };
            return ProcessRunner.RunAsync(PowerShellExe(), BuildArguments(bundleRoot, mode, mode != "Rollback"), env, null, onLine,
                                          TimeSpan.FromMinutes(90), ct, bundleRoot);
        }
    }
}
