using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;

namespace AppleLabs
{
    enum CursorStyle { Standard, Classic, Custom }
    enum DeathSound { Standard, Classic, Custom }

    /// <summary>What's in the mods folder, read once per change rather than on every redraw.</summary>
    sealed class ModsSnapshot
    {
        public CursorStyle Cursor;
        public DeathSound Sound;
        public string FontFile;
        public string FontName;
        public int FileCount;
        public int ExtraCount;

        public int ActiveCount =>
            ExtraCount + (Cursor != CursorStyle.Standard ? 1 : 0) + (Sound != DeathSound.Standard ? 1 : 0) + (FontFile != null ? 1 : 0);

        public string CursorLabel => Cursor == CursorStyle.Classic ? "Classic arrow" : Cursor == CursorStyle.Custom ? "Custom image" : "Default";
        public string SoundLabel => Sound == DeathSound.Classic ? "Classic “oof”" : Sound == DeathSound.Custom ? "Custom sound" : "Default";
    }

    /// <summary>The Style page's mods: cursor, death sound and game font.</summary>
    static class Mods
    {
        public static ModsSnapshot Read(string customFontName)
        {
            var s = new ModsSnapshot();
            var sound = Roblox.ModFile(Roblox.DeathSoundPath);
            if (File.Exists(sound))
                s.Sound = SameFile(sound, Roblox.Resource(Roblox.OofPath)) ? DeathSound.Classic : DeathSound.Custom;

            var cursor = Roblox.ModFile(Roblox.CursorPaths[0]);
            if (File.Exists(cursor))
                // The top-level textures are never modded, so Roblox's copy is the reference.
                s.Cursor = SameFile(cursor, Roblox.Resource(Roblox.ClassicCursorSources[0])) ? CursorStyle.Classic : CursorStyle.Custom;

            s.FontFile = Roblox.FontPaths.Select(Roblox.ModFile).FirstOrDefault(File.Exists);
            if (s.FontFile != null) s.FontName = string.IsNullOrEmpty(customFontName) ? "Custom font" : customFontName;

            var known = new[] { Roblox.DeathSoundPath }.Concat(Roblox.CursorPaths).Concat(Roblox.FontPaths)
                .ToDictionary(p => p, p => true, StringComparer.OrdinalIgnoreCase);
            if (Directory.Exists(Paths.Mods))
            {
                foreach (var file in Directory.EnumerateFiles(Paths.Mods, "*", SearchOption.AllDirectories))
                {
                    var name = Path.GetFileName(file);
                    if (name.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase) || name.Equals("Thumbs.db", StringComparison.OrdinalIgnoreCase)) continue;
                    s.FileCount++;
                    var rel = Paths.Relative(Paths.Mods, file);
                    if (rel != null && !known.ContainsKey(rel)) s.ExtraCount++;
                }
            }
            return s;
        }

        static bool SameFile(string a, string b)
        {
            if (b == null || !File.Exists(a) || !File.Exists(b)) return false;
            var fa = new FileInfo(a);
            var fb = new FileInfo(b);
            if (fa.Length != fb.Length) return false;
            return File.ReadAllBytes(a).SequenceEqual(File.ReadAllBytes(b));
        }

        static void Install(string source, string relative)
        {
            var dest = Roblox.ModFile(relative);
            Directory.CreateDirectory(Path.GetDirectoryName(dest));
            File.Copy(source, dest, true);
        }

        static void Remove(string relative)
        {
            var file = Roblox.ModFile(relative);
            if (File.Exists(file)) File.Delete(file);
        }

        public static void SetDeathSound(DeathSound choice, string file = null)
        {
            switch (choice)
            {
                case DeathSound.Standard: Remove(Roblox.DeathSoundPath); break;
                case DeathSound.Classic:
                    var oof = Roblox.Resource(Roblox.OofPath);
                    if (oof == null || !File.Exists(oof)) throw new InvalidOperationException("Install Roblox first; the classic sound comes from its files.");
                    Install(oof, Roblox.DeathSoundPath);
                    break;
                case DeathSound.Custom:
                    if (file != null) Install(file, Roblox.DeathSoundPath);
                    break;
            }
        }

        public static void SetCursor(CursorStyle choice, string image = null)
        {
            switch (choice)
            {
                case CursorStyle.Standard:
                    foreach (var p in Roblox.CursorPaths) Remove(p);
                    break;
                case CursorStyle.Classic:
                    for (var i = 0; i < Roblox.CursorPaths.Length; i++)
                    {
                        var source = Roblox.Resource(Roblox.ClassicCursorSources[i]);
                        if (source == null || !File.Exists(source)) throw new InvalidOperationException("Install Roblox first; the classic cursor comes from its files.");
                        Install(source, Roblox.CursorPaths[i]);
                    }
                    break;
                case CursorStyle.Custom:
                    var png = CursorPng(image);
                    foreach (var p in Roblox.CursorPaths)
                    {
                        var dest = Roblox.ModFile(p);
                        Directory.CreateDirectory(Path.GetDirectoryName(dest));
                        File.WriteAllBytes(dest, png);
                    }
                    break;
            }
        }

        /// <summary>Scales any picture to Roblox's 64×64 cursor size.</summary>
        static byte[] CursorPng(string image)
        {
            try
            {
                using (var source = Image.FromFile(image))
                using (var bitmap = new Bitmap(64, 64, PixelFormat.Format32bppArgb))
                using (var g = Graphics.FromImage(bitmap))
                using (var output = new MemoryStream())
                {
                    g.Clear(Color.Transparent);
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(source, new Rectangle(0, 0, 64, 64));
                    bitmap.Save(output, ImageFormat.Png);
                    return output.ToArray();
                }
            }
            catch (Exception e) when (e is OutOfMemoryException || e is ArgumentException || e is IOException)
            {
                throw new InvalidOperationException("Could not read that image.");
            }
        }

        public static void SetFont(string file)
        {
            foreach (var p in Roblox.FontPaths) Remove(p);
            if (file == null) return;
            var ext = Path.GetExtension(file).Equals(".otf", StringComparison.OrdinalIgnoreCase) ? "otf" : "ttf";
            Install(file, "content/fonts/CustomFont." + ext);
        }

        public static void Clear()
        {
            Paths.TryDeleteDirectory(Paths.Mods);
            Directory.CreateDirectory(Paths.Mods);
        }
    }
}
