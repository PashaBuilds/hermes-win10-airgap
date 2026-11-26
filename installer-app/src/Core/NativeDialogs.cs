using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace HermesKurulum.Core
{
    /// <summary>The Windows "Security Warning" prompt shown when a root CA is added to CurrentUser\Root
    /// has no owner window, so it can open *behind* the assistant and the user would wait forever.
    /// While the store call runs we bring any new dialog (class #32770) of our own process to the front.</summary>
    public static class NativeDialogs
    {
        delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);

        static readonly IntPtr HWND_TOPMOST = new IntPtr(-1), HWND_NOTOPMOST = new IntPtr(-2);
        const uint SWP_NOMOVE = 0x2, SWP_NOSIZE = 0x1, SWP_SHOWWINDOW = 0x40;

        /// <summary>Visible dialog windows (#32770) of this process, except <paramref name="ignore"/>.</summary>
        public static List<(IntPtr hwnd, string title)> OwnDialogs(ICollection<IntPtr> ignore = null)
        {
            var list = new List<(IntPtr, string)>();
            uint me = (uint)Process.GetCurrentProcess().Id;
            EnumWindows((h, l) =>
            {
                GetWindowThreadProcessId(h, out var pid);
                if (pid != me || !IsWindowVisible(h) || (ignore != null && ignore.Contains(h))) return true;
                var cls = new StringBuilder(64); GetClassName(h, cls, cls.Capacity);
                if (cls.ToString() != "#32770") return true;
                var t = new StringBuilder(256); GetWindowText(h, t, t.Capacity);
                list.Add((h, t.ToString()));
                return true;
            }, IntPtr.Zero);
            return list;
        }

        /// <summary>Brings each new dialog of this process to the front once (no fighting with the user).</summary>
        public static void BringToFront(HashSet<IntPtr> alreadyRaised, Action<string> log)
        {
            foreach (var (h, title) in OwnDialogs(alreadyRaised))
            {
                alreadyRaised.Add(h);
                SetWindowPos(h, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
                SetWindowPos(h, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
                BringWindowToTop(h);
                SetForegroundWindow(h);
                log?.Invoke("Windows onay penceresi öne getirildi: \"" + title + "\"");
            }
        }

        /// <summary>Runs <paramref name="work"/> on its own STA thread (Windows UI prompts expect STA).</summary>
        public static Task<T> RunSta<T>(Func<T> work)
        {
            var tcs = new TaskCompletionSource<T>();
            var t = new Thread(() =>
            {
                try { tcs.SetResult(work()); } catch (Exception ex) { tcs.SetException(ex); }
            }) { IsBackground = true, Name = "cert-store" };
            t.SetApartmentState(ApartmentState.STA);
            t.Start();
            return tcs.Task;
        }
    }
}
