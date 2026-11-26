using System;
using System.IO;
using System.Text;

namespace HermesKurulum.Core
{
    /// <summary>Thread-safe log file + UI sink. Every line goes through the Redactor first.</summary>
    public sealed class LogWriter
    {
        readonly object _lock = new object();
        public string FilePath { get; }
        public Redactor Redactor { get; }
        public event Action<string, string> Line;   // (level, text)

        public LogWriter(string filePath, Redactor redactor)
        {
            FilePath = filePath;
            Redactor = redactor ?? new Redactor();
            var dir = Path.GetDirectoryName(filePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        }

        public void Info(string text) => Write("INFO", text);
        public void Warn(string text) => Write("UYARI", text);
        public void Error(string text) => Write("HATA", text);
        public void Ok(string text) => Write("TAMAM", text);
        public void Raw(string text) => Write("", text);

        public void Write(string level, string text)
        {
            text = Redactor.Clean(text ?? string.Empty);
            string stamp = DateTime.Now.ToString("HH:mm:ss");
            string line = string.IsNullOrEmpty(level) ? stamp + "   " + text : stamp + " [" + level + "] " + text;
            lock (_lock)
            {
                try { File.AppendAllText(FilePath, line + Environment.NewLine, new UTF8Encoding(false)); } catch { }
            }
            Line?.Invoke(level, line);
        }
    }
}
