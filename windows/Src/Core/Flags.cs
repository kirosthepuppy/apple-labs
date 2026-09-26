using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;

namespace AppleLabs
{
    /// <summary>A one-click bundle of engine FastFlags.</summary>
    sealed class GraphicsPreset
    {
        public string Id, Name, Glyph, Blurb;
        public string[] Highlights;
        /// <summary>1–5 ratings shown as meters on the preset cards.</summary>
        public int Speed, Looks;
        public Dictionary<string, object> Flags;
    }

    /// <summary>
    /// The user's FastFlags, kept in fflags.json and written into Roblox's
    /// ClientSettings before every launch. Values are bool, long, double or
    /// string, the same types `fflags set` produces on the Mac.
    /// </summary>
    static class FastFlags
    {
        /// <summary>
        /// The flags Roblox still reads from ClientAppSettings.json. Since September
        /// 2025 it ignores every other one:
        /// https://devforum.roblox.com/t/allowlist-for-local-client-configuration-via-fast-flags/3966569
        /// </summary>
        public static readonly HashSet<string> Allowed = new HashSet<string>
        {
            "DFIntCSGLevelOfDetailSwitchingDistance", "DFIntCSGLevelOfDetailSwitchingDistanceL12",
            "DFIntCSGLevelOfDetailSwitchingDistanceL23", "DFIntCSGLevelOfDetailSwitchingDistanceL34",
            "FFlagHandleAltEnterFullscreenManually", "DFFlagTextureQualityOverrideEnabled", "DFIntTextureQualityOverride",
            "FIntDebugForceMSAASamples", "DFFlagDisableDPIScale", "FFlagDebugGraphicsPreferD3D11", "FFlagDebugSkyGray",
            "DFFlagDebugPauseVoxelizer", "DFIntDebugFRMQualityLevelOverride", "FIntFRMMaxGrassDistance",
            "FIntFRMMinGrassDistance", "FFlagDebugGraphicsPreferVulkan", "FFlagDebugGraphicsPreferOpenGL",
            "FIntGrassMovementReducedMotionFactor",
        };

        /// <summary>Flags earlier versions of the launcher set that Roblox now ignores.</summary>
        public static readonly string[] Retired = { "DFIntTaskSchedulerTargetFps", "FFlagDisablePostFx", "FIntRenderGrassDetailStrands" };

        public static readonly HashSet<string> PresetKeys = new HashSet<string>
        {
            "FIntDebugForceMSAASamples", "DFFlagTextureQualityOverrideEnabled", "DFIntTextureQualityOverride",
            "FFlagDebugSkyGray", "FIntFRMMinGrassDistance", "FIntFRMMaxGrassDistance",
        };

        public static readonly GraphicsPreset[] Presets =
        {
            new GraphicsPreset
            {
                Id = "default", Name = "Roblox default", Glyph = "\uE777",
                Blurb = "No engine tweaks. Roblox decides everything.",
                Highlights = new[] { "Stock settings" }, Speed = 3, Looks = 3,
                Flags = new Dictionary<string, object>(),
            },
            new GraphicsPreset
            {
                Id = "balanced", Name = "Balanced", Glyph = "\uE8AB",
                Blurb = "Smoother edges without costing much speed.",
                Highlights = new[] { "2× anti-aliasing", "Medium textures" }, Speed = 4, Looks = 3,
                Flags = new Dictionary<string, object>
                {
                    ["FIntDebugForceMSAASamples"] = 2L,
                    ["DFFlagTextureQualityOverrideEnabled"] = true,
                    ["DFIntTextureQualityOverride"] = 2L,
                },
            },
            new GraphicsPreset
            {
                Id = "performance", Name = "Performance", Glyph = "\uE945",
                Blurb = "Less to draw, for steadier frame rates.",
                Highlights = new[] { "No anti-aliasing", "Low textures", "No grass" },
                Speed = 5, Looks = 2,
                Flags = new Dictionary<string, object>
                {
                    ["FIntDebugForceMSAASamples"] = 1L,
                    ["DFFlagTextureQualityOverrideEnabled"] = true,
                    ["DFIntTextureQualityOverride"] = 1L,
                    ["FIntFRMMinGrassDistance"] = 0L,
                    ["FIntFRMMaxGrassDistance"] = 0L,
                },
            },
            new GraphicsPreset
            {
                Id = "quality", Name = "Quality", Glyph = "\uE734",
                Blurb = "Crisp edges and full textures on a strong PC.",
                Highlights = new[] { "4× anti-aliasing", "High textures" }, Speed = 3, Looks = 5,
                Flags = new Dictionary<string, object>
                {
                    ["FIntDebugForceMSAASamples"] = 4L,
                    ["DFFlagTextureQualityOverrideEnabled"] = true,
                    ["DFIntTextureQualityOverride"] = 3L,
                },
            },
            new GraphicsPreset
            {
                Id = "potato", Name = "Potato", Glyph = "\uE7E8",
                Blurb = "Everything turned down for older PCs.",
                Highlights = new[] { "No anti-aliasing", "Lowest textures", "No grass", "Gray sky" },
                Speed = 5, Looks = 1,
                Flags = new Dictionary<string, object>
                {
                    ["FIntDebugForceMSAASamples"] = 1L,
                    ["DFFlagTextureQualityOverrideEnabled"] = true,
                    ["DFIntTextureQualityOverride"] = 0L,
                    ["FFlagDebugSkyGray"] = true,
                    ["FIntFRMMinGrassDistance"] = 0L,
                    ["FIntFRMMaxGrassDistance"] = 0L,
                },
            },
        };

        /// <summary>Turns typed text into a flag value: true/false and whole numbers stay typed.</summary>
        public static object Parse(string text)
        {
            var trimmed = (text ?? "").Trim();
            if (trimmed == "true") return true;
            if (trimmed == "false") return false;
            if (long.TryParse(trimmed, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var n)) return n;
            return text ?? "";
        }

        public static string Text(object value)
        {
            switch (value)
            {
                case bool b: return b ? "true" : "false";
                case long l: return l.ToString(CultureInfo.InvariantCulture);
                case double d: return d.ToString("R", CultureInfo.InvariantCulture);
                case null: return "";
                default: return Convert.ToString(value, CultureInfo.InvariantCulture);
            }
        }

        public static bool Same(object a, object b)
        {
            if (a is long la && b is long lb) return la == lb;
            if (a is bool ba && b is bool bb) return ba == bb;
            if (a is double da && b is double db) return da == db;
            if (a is string sa && b is string sb) return sa == sb;
            return a == null && b == null;
        }

        /// <summary>Keeps only values Roblox understands: bool, number or text.</summary>
        public static Dictionary<string, object> Clean(Dictionary<string, object> raw)
        {
            var result = new Dictionary<string, object>();
            foreach (var pair in raw)
            {
                switch (pair.Value)
                {
                    case bool _:
                    case long _:
                    case double _:
                    case string _:
                        result[pair.Key] = pair.Value;
                        break;
                }
            }
            return result;
        }

        /// <summary>Reads fflags.json. Throws FormatException when the file isn't valid JSON.</summary>
        public static Dictionary<string, object> Load()
        {
            var text = Paths.ReadText(Paths.FFlags);
            if (string.IsNullOrWhiteSpace(text)) return new Dictionary<string, object>();
            return Clean(Json.ParseObject(text));
        }

        public static void Save(Dictionary<string, object> flags)
        {
            var sorted = new SortedDictionary<string, object>(flags, StringComparer.Ordinal);
            Paths.WriteAtomic(Paths.FFlags, Json.Write(sorted) + "\n");
        }

        /// <summary>The preset whose flags exactly match the current engine flags.</summary>
        public static GraphicsPreset ActivePreset(Dictionary<string, object> flags)
        {
            var current = flags.Where(p => PresetKeys.Contains(p.Key)).ToDictionary(p => p.Key, p => p.Value);
            return Presets.FirstOrDefault(preset =>
                preset.Flags.Count == current.Count &&
                preset.Flags.All(p => current.TryGetValue(p.Key, out var v) && Same(v, p.Value)));
        }

        public static string ExportJson(Dictionary<string, object> flags) =>
            Json.Write(new SortedDictionary<string, object>(flags, StringComparer.Ordinal));

        /// <summary>Reads a Bloxstrap/Fishstrap-style export. Returns null and an error message on failure.</summary>
        public static Dictionary<string, object> ParseImport(string json, out string error)
        {
            error = null;
            try
            {
                var parsed = Json.Parse(json);
                if (!(parsed is Dictionary<string, object> obj))
                {
                    error = "That isn't a JSON object of flags.";
                    return null;
                }
                return Clean(obj);
            }
            catch (FormatException e)
            {
                error = e.Message;
                return null;
            }
        }

        public static string Describe(Dictionary<string, object> flags)
        {
            var names = new[]
            {
                ("FIntDebugForceMSAASamples", "anti-aliasing"),
                ("DFIntTextureQualityOverride", "textures"),
                ("FIntFRMMaxGrassDistance", "grass"),
                ("FFlagDebugSkyGray", "sky"),
            };
            var parts = names.Where(n => flags.ContainsKey(n.Item1)).Select(n => n.Item2).ToList();
            var others = flags.Keys.Count(k => !PresetKeys.Contains(k));
            if (others > 0) parts.Add($"{others} custom flag{(others == 1 ? "" : "s")}");
            if (parts.Count == 0) return "Using Roblox's defaults";
            var text = string.Join(", ", parts);
            return char.ToUpper(text[0]) + text.Substring(1);
        }

        public static void EnsureFile()
        {
            if (!File.Exists(Paths.FFlags)) Paths.WriteAtomic(Paths.FFlags, "{}\n");
        }
    }
}
