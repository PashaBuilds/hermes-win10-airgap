using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace HermesKurulum.Core
{
    /// <summary>Small dependency-free JSON reader/writer (BUNDLE.json, install-stamp.json, helper results).</summary>
    public static class MiniJson
    {
        public static object Parse(string text)
        {
            if (text == null) throw new ArgumentNullException(nameof(text));
            int i = 0;
            if (text.Length > 0 && text[0] == '\uFEFF') i = 1;
            var v = ReadValue(text, ref i);
            SkipWs(text, ref i);
            if (i != text.Length) throw new FormatException("Trailing characters in JSON at " + i);
            return v;
        }

        public static Dictionary<string, object> ParseObject(string text)
        {
            var o = Parse(text) as Dictionary<string, object>;
            if (o == null) throw new FormatException("JSON object expected");
            return o;
        }

        static void SkipWs(string s, ref int i) { while (i < s.Length && char.IsWhiteSpace(s[i])) i++; }

        static object ReadValue(string s, ref int i)
        {
            SkipWs(s, ref i);
            if (i >= s.Length) throw new FormatException("Unexpected end of JSON");
            char c = s[i];
            if (c == '{') return ReadObject(s, ref i);
            if (c == '[') return ReadArray(s, ref i);
            if (c == '"') return ReadString(s, ref i);
            if (c == 't' && string.CompareOrdinal(s, i, "true", 0, 4) == 0) { i += 4; return true; }
            if (c == 'f' && string.CompareOrdinal(s, i, "false", 0, 5) == 0) { i += 5; return false; }
            if (c == 'n' && string.CompareOrdinal(s, i, "null", 0, 4) == 0) { i += 4; return null; }
            return ReadNumber(s, ref i);
        }

        static Dictionary<string, object> ReadObject(string s, ref int i)
        {
            var d = new Dictionary<string, object>(StringComparer.Ordinal);
            i++; SkipWs(s, ref i);
            if (i < s.Length && s[i] == '}') { i++; return d; }
            while (true)
            {
                SkipWs(s, ref i);
                if (i >= s.Length || s[i] != '"') throw new FormatException("Object key expected at " + i);
                string k = ReadString(s, ref i);
                SkipWs(s, ref i);
                if (i >= s.Length || s[i] != ':') throw new FormatException("':' expected at " + i);
                i++;
                d[k] = ReadValue(s, ref i);
                SkipWs(s, ref i);
                if (i < s.Length && s[i] == ',') { i++; continue; }
                if (i < s.Length && s[i] == '}') { i++; return d; }
                throw new FormatException("',' or '}' expected at " + i);
            }
        }

        static List<object> ReadArray(string s, ref int i)
        {
            var l = new List<object>();
            i++; SkipWs(s, ref i);
            if (i < s.Length && s[i] == ']') { i++; return l; }
            while (true)
            {
                l.Add(ReadValue(s, ref i));
                SkipWs(s, ref i);
                if (i < s.Length && s[i] == ',') { i++; continue; }
                if (i < s.Length && s[i] == ']') { i++; return l; }
                throw new FormatException("',' or ']' expected at " + i);
            }
        }

        static string ReadString(string s, ref int i)
        {
            var sb = new StringBuilder();
            i++;
            while (i < s.Length)
            {
                char c = s[i++];
                if (c == '"') return sb.ToString();
                if (c != '\\') { sb.Append(c); continue; }
                if (i >= s.Length) break;
                char e = s[i++];
                switch (e)
                {
                    case '"': sb.Append('"'); break;
                    case '\\': sb.Append('\\'); break;
                    case '/': sb.Append('/'); break;
                    case 'b': sb.Append('\b'); break;
                    case 'f': sb.Append('\f'); break;
                    case 'n': sb.Append('\n'); break;
                    case 'r': sb.Append('\r'); break;
                    case 't': sb.Append('\t'); break;
                    case 'u':
                        if (i + 4 > s.Length) throw new FormatException("Bad \\u escape");
                        sb.Append((char)int.Parse(s.Substring(i, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
                        i += 4; break;
                    default: throw new FormatException("Bad escape \\" + e);
                }
            }
            throw new FormatException("Unterminated string");
        }

        static object ReadNumber(string s, ref int i)
        {
            int start = i;
            while (i < s.Length && "+-0123456789.eE".IndexOf(s[i]) >= 0) i++;
            if (start == i) throw new FormatException("Unexpected character '" + s[i] + "' at " + i);
            return double.Parse(s.Substring(start, i - start), NumberStyles.Float, CultureInfo.InvariantCulture);
        }

        public static string Quote(string v)
        {
            if (v == null) return "null";
            var sb = new StringBuilder("\"");
            foreach (char c in v)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                        else sb.Append(c);
                        break;
                }
            }
            return sb.Append('"').ToString();
        }

        public static string Serialize(object v)
        {
            if (v == null) return "null";
            if (v is string str) return Quote(str);
            if (v is bool b) return b ? "true" : "false";
            if (v is int || v is long || v is double || v is float || v is decimal)
                return Convert.ToString(v, CultureInfo.InvariantCulture);
            if (v is IDictionary<string, object> d)
            {
                var parts = new List<string>();
                foreach (var kv in d) parts.Add(Quote(kv.Key) + ":" + Serialize(kv.Value));
                return "{" + string.Join(",", parts) + "}";
            }
            if (v is System.Collections.IEnumerable e)
            {
                var parts = new List<string>();
                foreach (var x in e) parts.Add(Serialize(x));
                return "[" + string.Join(",", parts) + "]";
            }
            return Quote(Convert.ToString(v, CultureInfo.InvariantCulture));
        }

        public static string Str(this Dictionary<string, object> d, string key, string fallback = "")
        {
            object v;
            if (d != null && d.TryGetValue(key, out v) && v != null) return Convert.ToString(v, CultureInfo.InvariantCulture);
            return fallback;
        }

        public static bool Bool(this Dictionary<string, object> d, string key)
        {
            object v;
            return d != null && d.TryGetValue(key, out v) && v is bool b && b;
        }

        public static double Num(this Dictionary<string, object> d, string key, double fallback = 0)
        {
            object v;
            if (d != null && d.TryGetValue(key, out v) && v is double n) return n;
            return fallback;
        }

        public static Dictionary<string, object> Obj(this Dictionary<string, object> d, string key)
        {
            object v;
            if (d != null && d.TryGetValue(key, out v)) return v as Dictionary<string, object>;
            return null;
        }

        public static List<string> StrList(this Dictionary<string, object> d, string key)
        {
            var r = new List<string>();
            object v;
            if (d != null && d.TryGetValue(key, out v) && v is List<object> l)
                foreach (var x in l) if (x != null) r.Add(Convert.ToString(x, CultureInfo.InvariantCulture));
            return r;
        }
    }
}
