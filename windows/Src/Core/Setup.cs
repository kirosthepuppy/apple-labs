using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using Microsoft.Win32;

namespace AppleLabs
{
    /// <summary>
    /// Puts the launcher in its own folder like a normal app: a copy of the exe
    /// in %LocalAppData%\AppleLabs, Start menu and desktop shortcuts, an entry in
    /// Settings › Apps, and (if wanted) Roblox links. No admin rights needed.
    /// </summary>
    static class Setup
    {
        const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\AppleLabs";

        public static bool RunningInstalled =>
            string.Equals(Path.GetFullPath(App.ExePath), Path.GetFullPath(Paths.InstalledExe), StringComparison.OrdinalIgnoreCase);

        /// <summary>
        /// When run from somewhere else (e.g. Downloads), copies itself into place and
        /// starts that copy. Returns true when the caller should exit.
        /// </summary>
        public static bool InstallSelf(Settings settings, string[] args)
        {
            if (RunningInstalled)
            {
                Register(settings);
                return false;
            }
            try
            {
                Directory.CreateDirectory(Paths.Home);
                var copied = false;
                for (var attempt = 0; attempt < 10 && !copied; attempt++)
                {
                    try
                    {
                        File.Copy(App.ExePath, Paths.InstalledExe, true);
                        copied = true;
                    }
                    catch (IOException) when (attempt < 9)
                    {
                        // The installed copy may still be closing.
                        System.Threading.Thread.Sleep(300);
                    }
                }
                Log.Info("installed the launcher at " + Paths.InstalledExe);
            }
            catch (Exception e)
            {
                Log.Warn("could not install the launcher, running in place: " + e.Message);
                return false;
            }
            Register(settings);
            try
            {
                Process.Start(new ProcessStartInfo(Paths.InstalledExe, string.Join(" ", args.Select(Quote))) { UseShellExecute = false })?.Dispose();
                return true;
            }
            catch (Exception e)
            {
                Log.Warn("could not start the installed launcher: " + e.Message);
                return false;
            }
        }

        static string Quote(string arg) => "\"" + arg.Replace("\"", "") + "\"";

        /// <summary>Shortcuts, the Apps entry and link handling for the installed copy.</summary>
        public static void Register(Settings settings)
        {
            var exe = Paths.InstalledExe;
            try
            {
                if (!File.Exists(Paths.StartMenuShortcut)) Shortcut(Paths.StartMenuShortcut, exe);
                if (!settings.DesktopShortcutOffered)
                {
                    Shortcut(Paths.DesktopShortcut, exe);
                    settings.DesktopShortcutOffered = true;
                    settings.Save();
                }
            }
            catch (Exception e) { Log.Warn("could not make shortcuts: " + e.Message); }
            try
            {
                using (var key = Registry.CurrentUser.CreateSubKey(UninstallKey))
                {
                    key.SetValue("DisplayName", "Apple Labs");
                    key.SetValue("DisplayVersion", App.Version);
                    key.SetValue("Publisher", "Apple Labs");
                    key.SetValue("DisplayIcon", $"\"{exe}\",0");
                    key.SetValue("InstallLocation", Paths.Home);
                    key.SetValue("UninstallString", $"\"{exe}\" --uninstall");
                    key.SetValue("URLInfoAbout", "https://github.com/kirosthepuppy/apple-labs");
                    key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                    key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    key.SetValue("EstimatedSize", 2048, RegistryValueKind.DWord);
                }
            }
            catch (Exception e) { Log.Warn("could not add the Apps entry: " + e.Message); }
            try
            {
                // Roblox's own installer takes the links back when it runs, so claim them each start.
                if (settings.HandleLinks) Roblox.RegisterLinks(exe);
            }
            catch (Exception e) { Log.Warn("could not register links: " + e.Message); }
        }

        /// <summary>Makes a .lnk through the Windows Script Host, which every Windows has.</summary>
        static void Shortcut(string path, string target)
        {
            var type = Type.GetTypeFromProgID("WScript.Shell");
            if (type == null) return;
            object shell = null, link = null;
            try
            {
                shell = Activator.CreateInstance(type);
                link = type.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { path });
                var lt = link.GetType();
                lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, link, new object[] { target });
                lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, link, new object[] { Path.GetDirectoryName(target) });
                lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, link, new object[] { target + ",0" });
                lt.InvokeMember("Description", BindingFlags.SetProperty, null, link, new object[] { "Launch Roblox with your mods and settings" });
                lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
            }
            finally
            {
                if (link != null) Marshal.FinalReleaseComObject(link);
                if (shell != null) Marshal.FinalReleaseComObject(shell);
            }
        }

        /// <summary>The interactive uninstall, from Settings › Apps or the General tab.</summary>
        public static void UninstallWithQuestions(Window owner)
        {
            if (!Ask.Confirm(owner, "Uninstall Apple Labs?",
                    "This removes the launcher and the copy of Roblox it installed, and hands Roblox links back to Roblox.", "Uninstall", destructive: true))
                return;
            if (Roblox.IsRunning)
            {
                if (!Ask.Confirm(owner, "Close Roblox?", "Roblox is running from the launcher's folder and needs to close first.", "Close Roblox")) return;
                Roblox.Quit().Wait();
            }
            var purge = Ask.Confirm(owner, "Remove your settings too?",
                "Your FastFlags, mods, saved accounts and launcher settings can stay, in case you reinstall later.", "Remove Everything", destructive: true);
            Uninstall(purge);
            Ask.Tell(owner, "Apple Labs is uninstalled", purge ? "Everything has been removed." : "Your settings, mods and saved accounts were kept in " + Paths.Home + ".");
            Application.Current.Shutdown();
        }

        public static void Uninstall(bool purge)
        {
            try { Roblox.UnregisterLinks(Paths.InstalledExe); Roblox.UnregisterLinks(App.ExePath); }
            catch (Exception e) { Log.Warn("links: " + e.Message); }
            foreach (var link in new[] { Paths.StartMenuShortcut, Paths.DesktopShortcut })
            {
                try { if (File.Exists(link)) File.Delete(link); } catch (Exception) { }
            }
            try { Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false); } catch (Exception) { }
            Paths.TryDeleteDirectory(Paths.Versions);
            Paths.TryDeleteDirectory(Paths.Downloads);
            Paths.TryDeleteDirectory(Paths.ModState);
            try { if (File.Exists(Paths.State)) File.Delete(Paths.State); } catch (Exception) { }
            Log.Info("uninstalled" + (purge ? " and removed all data" : ""));

            // The running exe can't delete itself; a short-lived helper does it once we've exited.
            var targets = purge ? $"rmdir /s /q \"{Paths.Home}\"" : $"del /f /q \"{Paths.InstalledExe}\"";
            try
            {
                Process.Start(new ProcessStartInfo("cmd.exe", $"/c ping 127.0.0.1 -n 3 > nul & {targets}")
                {
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    WindowStyle = ProcessWindowStyle.Hidden,
                })?.Dispose();
            }
            catch (Exception e) { Log.Warn("cleanup: " + e.Message); }
        }
    }
}
