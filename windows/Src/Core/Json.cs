using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace AppleLabs
{
    /// <summary>
    /// A small JSON reader and writer. Objects become Dictionary&lt;string, object&gt;
    /// (keeping their order), arrays List&lt;object&gt;, whole numbers long, other
    /// numbers double, plus string, bool and null.
    /// </summary>
    static class Json
    {
        public static object Parse(string text)
        {
            var reader = new Reader(text ?? "");
            reader.SkipSpace();
            var value = reader.ReadValue();
            reader.SkipSpace();
            if (!reader.AtEnd) throw reader.Error("unexpected text after the JSON value");
            return value;
        }

        public static Dictionary<string, object> ParseObject(string text) =>
            Parse(text) as Dictionary<string, object> ?? throw new FormatException("expected a JSON object");

        /// <summary>Parses, or returns null for anything that isn't a JSON object.</summary>
        public static Dictionary<string, object> TryParseObject(string text)
        {
            try { return Parse(text) as Dictionary<string, object>; }
            catch (FormatException) { return null; }
        }

        public static string Write(object value, bool indent = true)
        {
            var sb = new StringBuilder();
            WriteValue(sb, value, indent, 0);
            return sb.ToString();
        }

        // Convenience accessors for parsed objects.

        public static string Str(this Dictionary<string, object> o, string key) =>
            o != null && o.TryGetValue(key, out var v) && v != null ? Convert.ToString(v, CultureInfo.InvariantCulture) : null;

        public static long? Long(this Dictionary<string, object> o, string key)
        {
            if (o == null || !o.TryGetValue(key, out var v) || v == null) return null;
            switch (v)
            {
                case long l: return l;
                case double d: return (long)d;
                case string s when long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var p): return p;
                default: return null;
            }
        }

        public static double? Double(this Dictionary<string, object> o, string key)
        {
            if (o == null || !o.TryGetValue(key, out var v) || v == null) return null;
            switch (v)
            {
                case long l: return l;
                case double d: return d;
                default: return null;
            }
        }

        public static bool? Bool(this Dictionary<string, object> o, string key) =>
            o != null && o.TryGetValue(key, out var v) && v is bool b ? b : (bool?)null;

        public static Dictionary<string, object> Obj(this Dictionary<string, object> o, string key) =>
            o != null && o.TryGetValue(key, out var v) ? v as Dictionary<string, object> : null;

        public static List<object> Arr(this Dictionary<string, object> o, string key) =>
            o != null && o.TryGetValue(key, out var v) ? v as List<object> : null;

        // Writing

        static void WriteValue(StringBuilder sb, object value, bool indent, int depth)
        {
            switch (value)
            {
                case null: sb.Append("null"); break;
                case bool b: sb.Append(b ? "true" : "false"); break;
                case string s: WriteString(sb, s); break;
                case int i: sb.Append(i.ToString(CultureInfo.InvariantCulture)); break;
                case long l: sb.Append(l.ToString(CultureInfo.InvariantCulture)); break;
                case double d: sb.Append(FormatDouble(d)); break;
                case float f: sb.Append(FormatDouble(f)); break;
                case IDictionary dict: WriteObject(sb, dict, indent, depth); break;
                case IEnumerable list: WriteArray(sb, list, indent, depth); break;
                default: WriteString(sb, Convert.ToString(value, CultureInfo.InvariantCulture)); break;
            }
        }

        static string FormatDouble(double d)
        {
            if (double.IsNaN(d) || double.IsInfinity(d)) return "null";
            var s = d.ToString("R", CultureInfo.InvariantCulture);
            return s.Contains("E") || s.Contains(".") ? s : s + ".0";
        }

        static void WriteObject(StringBuilder sb, IDictionary dict, bool indent, int depth)
        {
            if (dict.Count == 0) { sb.Append("{}"); return; }
            sb.Append('{');
            var first = true;
            foreach (DictionaryEntry entry in dict)
            {
                if (!first) sb.Append(',');
                first = false;
                NewLine(sb, indent, depth + 1);
                WriteString(sb, Convert.ToString(entry.Key, CultureInfo.InvariantCulture));
                sb.Append(indent ? ": " : ":");
                WriteValue(sb, entry.Value, indent, depth + 1);
            }
            NewLine(sb, indent, depth);
            sb.Append('}');
        }

        static void WriteArray(StringBuilder sb, IEnumerable list, bool indent, int depth)
        {
            var items = new List<object>();
            foreach (var item in list) items.Add(item);
            if (items.Count == 0) { sb.Append("[]"); return; }
            sb.Append('[');
            for (var i = 0; i < items.Count; i++)
            {
                if (i > 0) sb.Append(',');
                NewLine(sb, indent, depth + 1);
                WriteValue(sb, items[i], indent, depth + 1);
            }
            NewLine(sb, indent, depth);
            sb.Append(']');
        }

        static void NewLine(StringBuilder sb, bool indent, int depth)
        {
            if (!indent) return;
            sb.Append('\n');
            sb.Append(' ', depth * 2);
        }

        static void WriteString(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (var c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    case '\b': sb.Append("\\b"); break;
                    case '\f': sb.Append("\\f"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }

        // Reading

        sealed class Reader
        {
            readonly string text;
            int pos;

            public Reader(string text) { this.text = text; }

            public bool AtEnd => pos >= text.Length;

            public FormatException Error(string message)
            {
                var line = 1;
                for (var i = 0; i < Math.Min(pos, text.Length); i++) if (text[i] == '\n') line++;
                return new FormatException($"Invalid JSON on line {line}: {message}");
            }

            public void SkipSpace()
            {
                while (pos < text.Length)
                {
                    var c = text[pos];
                    if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\uFEFF') { pos++; continue; }
                    // Tolerate // and /* */ comments, which hand-edited flag files sometimes have.
                    if (c == '/' && pos + 1 < text.Length && text[pos + 1] == '/')
                    {
                        while (pos < text.Length && text[pos] != '\n') pos++;
                        continue;
                    }
                    if (c == '/' && pos + 1 < text.Length && text[pos + 1] == '*')
                    {
                        var end = text.IndexOf("*/", pos + 2, StringComparison.Ordinal);
                        pos = end < 0 ? text.Length : end + 2;
                        continue;
                    }
                    break;
                }
            }

            public object ReadValue()
            {
                if (AtEnd) throw Error("unexpected end");
                var c = text[pos];
                switch (c)
                {
                    case '{': return ReadObject();
                    case '[': return ReadArray();
                    case '"': return ReadString();
                    case 't': Expect("true"); return true;
                    case 'f': Expect("false"); return false;
                    case 'n': Expect("null"); return null;
                    default:
                        if (c == '-' || (c >= '0' && c <= '9')) return ReadNumber();
                        throw Error($"unexpected '{c}'");
                }
            }

            void Expect(string word)
            {
                if (string.CompareOrdinal(text, pos, word, 0, word.Length) != 0) throw Error($"expected {word}");
                pos += word.Length;
            }

            Dictionary<string, object> ReadObject()
            {
                var result = new Dictionary<string, object>();
                pos++;
                SkipSpace();
                if (!AtEnd && text[pos] == '}') { pos++; return result; }
                while (true)
                {
                    SkipSpace();
                    if (AtEnd || text[pos] != '"') throw Error("expected a quoted name");
                    var key = ReadString();
                    SkipSpace();
                    if (AtEnd || text[pos] != ':') throw Error("expected ':'");
                    pos++;
                    SkipSpace();
                    result[key] = ReadValue();
                    SkipSpace();
                    if (AtEnd) throw Error("unexpected end");
                    if (text[pos] == ',')
                    {
                        pos++;
                        SkipSpace();
                        // Allow a trailing comma.
                        if (!AtEnd && text[pos] == '}') { pos++; return result; }
                        continue;
                    }
                    if (text[pos] == '}') { pos++; return result; }
                    throw Error("expected ',' or '}'");
                }
            }

            List<object> ReadArray()
            {
                var result = new List<object>();
                pos++;
                SkipSpace();
                if (!AtEnd && text[pos] == ']') { pos++; return result; }
                while (true)
                {
                    SkipSpace();
                    result.Add(ReadValue());
                    SkipSpace();
                    if (AtEnd) throw Error("unexpected end");
                    if (text[pos] == ',')
                    {
                        pos++;
                        SkipSpace();
                        if (!AtEnd && text[pos] == ']') { pos++; return result; }
                        continue;
                    }
                    if (text[pos] == ']') { pos++; return result; }
                    throw Error("expected ',' or ']'");
                }
            }

            string ReadString()
            {
                pos++;
                var sb = new StringBuilder();
                while (true)
                {
                    if (AtEnd) throw Error("unterminated string");
                    var c = text[pos++];
                    if (c == '"') return sb.ToString();
                    if (c != '\\') { sb.Append(c); continue; }
                    if (AtEnd) throw Error("unterminated string");
                    var e = text[pos++];
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
                            if (pos + 4 > text.Length) throw Error("bad \\u escape");
                            sb.Append((char)Convert.ToInt32(text.Substring(pos, 4), 16));
                            pos += 4;
                            break;
                        default: throw Error($"bad escape \\{e}");
                    }
                }
            }

            object ReadNumber()
            {
                var start = pos;
                if (text[pos] == '-') pos++;
                while (pos < text.Length && "0123456789.eE+-".IndexOf(text[pos]) >= 0) pos++;
                var s = text.Substring(start, pos - start);
                if (s.IndexOfAny(new[] { '.', 'e', 'E' }) < 0 &&
                    long.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var l))
                    return l;
                if (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var d)) return d;
                throw Error($"bad number {s}");
            }
        }
    }
}
