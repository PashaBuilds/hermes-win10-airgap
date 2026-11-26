using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace HermesKurulum.Core
{
    public interface IEnvironmentStore
    {
        string GetUser(string name);
        void SetUser(string name, string value);
        void Broadcast();
    }

    /// <summary>HKCU\Environment through the .NET API (no admin rights needed).</summary>
    public sealed class WindowsUserEnvironment : IEnvironmentStore
    {
        public string GetUser(string name) => Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.User);
        public void SetUser(string name, string value) => Environment.SetEnvironmentVariable(name, value, EnvironmentVariableTarget.User);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);

        /// <summary>WM_SETTINGCHANGE "Environment" so new Explorer/terminal windows see the change.</summary>
        public void Broadcast()
        {
            try { UIntPtr r; SendMessageTimeout((IntPtr)0xFFFF, 0x001A, UIntPtr.Zero, "Environment", 0x0002, 5000, out r); } catch { }
        }
    }

    public sealed class FakeEnvironmentStore : IEnvironmentStore
    {
        public readonly Dictionary<string, string> Values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        public int Broadcasts;
        public string GetUser(string name) { string v; return Values.TryGetValue(name, out v) ? v : null; }
        public void SetUser(string name, string value) { if (value == null) Values.Remove(name); else Values[name] = value; }
        public void Broadcast() => Broadcasts++;
    }
}
