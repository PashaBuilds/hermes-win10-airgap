using System;
using System.Collections.Generic;
using System.Linq;

namespace HermesKurulum.Core
{
    /// <summary>Removes registered secrets (and their 8-char prefixes Hermes likes to echo) from any text
    /// before it reaches the screen or the log file.</summary>
    public sealed class Redactor
    {
        readonly object _lock = new object();
        List<string> _secrets = new List<string>();

        public void Add(string secret)
        {
            if (string.IsNullOrWhiteSpace(secret)) return;
            secret = secret.Trim();
            lock (_lock)
            {
                var next = new List<string>(_secrets);
                foreach (var s in new[] { secret, secret.Length > 8 ? secret.Substring(0, 8) : secret })
                    if (s.Length >= 4 && !next.Contains(s)) next.Add(s);
                _secrets = next.OrderByDescending(s => s.Length).ToList();
            }
        }

        public string Clean(string text)
        {
            if (string.IsNullOrEmpty(text)) return text ?? string.Empty;
            List<string> secrets;
            lock (_lock) secrets = _secrets;
            foreach (var s in secrets) text = text.Replace(s, "****");
            return text;
        }
    }
}
