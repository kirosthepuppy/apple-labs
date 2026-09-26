using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace AppleLabs
{
    /// <summary>
    /// "Apple Labs.exe --cli &lt;command&gt;": the launcher's work without the window,
    /// for scripts and tests. Mirrors the Mac's roblox-bootstrapper commands.
    /// </summary>
    static class Cli
    {
        [DllImport("kernel32.dll")]
        static extern bool AttachConsole(int processId);

        public const string Usage =
@"Apple Labs for Windows

  --cli status [--json]                  Installed vs. latest version, settings
  --cli install [--force]                Install Roblox, or update it
  --cli launch [roblox-link]             Update if needed, apply flags and mods, start Roblox
  --cli fflags list | clear
  --cli fflags set NAME VALUE | unset NAME | import FILE
  --cli mods list | apply | clear | path
  --cli accounts list [--json] | save | use WHO | add | remove WHO
  --cli register | unregister            Send roblox:// links through this exe, or stop
  --cli uninstall [--purge]              Remove the launcher (and with --purge, all its data)
  --cli selftest [FOLDER]                Open every page and save screenshots
  --cli version";

        public static void AttachOutput()
        {
            // A windowed app has no console; print into the one that started us,
            // unless output is already redirected (pipes, tests).
            if (!Console.IsOutputRedirected) AttachConsole(-1);
            try
            {
                Console.SetOut(new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true });
                Console.SetError(new StreamWriter(Console.OpenStandardError()) { AutoFlush = true });
            }
            catch (IOException) { }
        }

        public static int Run(string[] args)
        {
            try
            {
                return Task.Run(() => RunAsync(args)).GetAwaiter().GetResult();
            }
            catch (Exception e)
            {
                Console.Error.WriteLine("error: " + e.Message);
                Log.Error("cli " + string.Join(" ", args) + ": " + e);
                return 1;
            }
        }

        static async Task<int> RunAsync(string[] args)
        {
            var command = args.FirstOrDefault() ?? "help";
            var rest = args.Skip(1).ToArray();
            var settings = Settings.Load();
            switch (command)
            {
                case "status": return await Status(settings, rest.Contains("--json"));
                case "install": return await Install(settings, rest.Contains("--force") || rest.Contains("-f"));
                case "launch": return await Launch(settings, rest.FirstOrDefault());
                case "fflags": return Flags(rest);
                case "mods": return ModsCommand(rest);
                case "accounts": return AccountsCommand(rest);
                case "register":
                    Roblox.RegisterLinks(App.ExePath);
                    Console.WriteLine("roblox:// links now open through " + App.ExePath);
                    return 0;
                case "unregister":
                    Roblox.UnregisterLinks(App.ExePath);
                    Console.WriteLine("roblox:// links open Roblox directly again");
                    return 0;
                case "uninstall":
                    Setup.Uninstall(purge: rest.Contains("--purge"));
                    Console.WriteLine("Apple Labs is uninstalled" + (rest.Contains("--purge") ? " and its data removed" : ""));
                    return 0;
                case "version":
                    Console.WriteLine(App.Version);
                    return 0;
                default:
                    Console.WriteLine(Usage);
                    return command == "help" || command == "--help" ? 0 : 1;
            }
        }

        static async Task<int> Status(Settings settings, bool json)
        {
            VersionInfo latest = null;
            try { latest = await Roblox.FetchLatest(settings.Channel); }
            catch (Exception e) { Log.Warn("status: " + e.Message); }
            var status = Roblox.StatusJson(latest);
            if (json)
            {
                Console.WriteLine(Json.Write(status));
                return 0;
            }
            Console.WriteLine($"Apple Labs {App.Version}\n");
            Console.WriteLine($"  Installed      {status["installed"] ?? "no"}");
            Console.WriteLine($"  Latest         {status["latest"] ?? "(offline)"}");
            Console.WriteLine($"  Status         {(status["upToDate"] is bool b ? (b ? "up to date" : "update available") : "-")}");
            Console.WriteLine($"  Install path   {status["installPath"] ?? "-"}");
            Console.WriteLine($"  Channel        {settings.Channel}");
            Console.WriteLine($"  FastFlags      {status["fflags"]} set");
            Console.WriteLine($"  Mods           {status["modFiles"]} files");
            Console.WriteLine($"  Link handler   {((bool)status["linkHandler"] ? "registered" : "not registered")}");
            return 0;
        }

        static ProgressHandler Printer()
        {
            string last = null;
            var lastTenth = -1;
            return (stage, fraction) =>
            {
                if (stage != last) { Console.WriteLine("==> " + stage); last = stage; lastTenth = -1; }
                if (fraction is double f && (int)(f * 10) != lastTenth)
                {
                    lastTenth = (int)(f * 10);
                    Console.WriteLine($"    {(int)(f * 100)}%");
                }
            };
        }

        static async Task<int> Install(Settings settings, bool force)
        {
            var latest = await Roblox.FetchLatest(settings.Channel);
            var before = Roblox.Installed;
            await Roblox.Install(latest, Printer(), CancellationToken.None, force);
            Console.WriteLine(before?.Guid == latest.Guid && !force
                ? $"Roblox is up to date ({latest.Display})"
                : $"Roblox {latest.Display} installed at {Roblox.VersionDir(latest.Guid)}");
            return 0;
        }

        static async Task<int> Launch(Settings settings, string link)
        {
            if (link != null && !Roblox.IsRobloxLink(link)) throw new ArgumentException("Not a Roblox link: " + link);
            try
            {
                var latest = await Roblox.FetchLatest(settings.Channel);
                await Roblox.Install(latest, Printer(), CancellationToken.None);
            }
            catch (Exception e) when (Roblox.Installed != null)
            {
                Console.Error.WriteLine("warning: couldn't check for updates (" + e.Message + "); starting what's installed");
                Roblox.ApplyCustomizations();
            }
            using (var process = Roblox.StartProcess(link))
            {
                // Catch a Roblox that quits straight away, which otherwise looks like success.
                if (process != null && process.WaitForExit(8000))
                {
                    Console.Error.WriteLine($"error: Roblox exited right away with code {process.ExitCode} (0x{process.ExitCode:X8})");
                    return 1;
                }
            }
            Console.WriteLine(link == null ? "Roblox started" : "Joining game");
            return 0;
        }

        static int Flags(string[] args)
        {
            var sub = args.FirstOrDefault() ?? "list";
            var flags = FastFlags.Load();
            switch (sub)
            {
                case "list":
                    if (flags.Count == 0) Console.WriteLine("(no FastFlags set)");
                    foreach (var pair in flags.OrderBy(p => p.Key, StringComparer.Ordinal))
                        Console.WriteLine($"{pair.Key} = {Json.Write(pair.Value, false)}");
                    return 0;
                case "set":
                    if (args.Length < 3) throw new ArgumentException("usage: fflags set NAME VALUE");
                    flags[args[1]] = FastFlags.Parse(args[2]);
                    break;
                case "unset":
                    if (args.Length < 2) throw new ArgumentException("usage: fflags unset NAME");
                    flags.Remove(args[1]);
                    break;
                case "clear":
                    flags.Clear();
                    break;
                case "import":
                    if (args.Length < 2) throw new ArgumentException("usage: fflags import FILE");
                    var imported = FastFlags.ParseImport(File.ReadAllText(args[1]), out var error) ?? throw new FormatException(error);
                    foreach (var pair in imported) flags[pair.Key] = pair.Value;
                    break;
                default: throw new ArgumentException($"unknown fflags command '{sub}' (list, set, unset, clear, import)");
            }
            FastFlags.Save(flags);
            var dir = Roblox.InstalledDir;
            if (dir != null) Roblox.ApplyFlags(dir);
            Console.WriteLine($"{flags.Count} FastFlag{(flags.Count == 1 ? "" : "s")} set");
            return 0;
        }

        static int ModsCommand(string[] args)
        {
            var sub = args.FirstOrDefault() ?? "list";
            Directory.CreateDirectory(Paths.Mods);
            switch (sub)
            {
                case "list":
                    var files = Directory.EnumerateFiles(Paths.Mods, "*", SearchOption.AllDirectories).Select(f => Paths.Relative(Paths.Mods, f)).OrderBy(f => f).ToList();
                    if (files.Count == 0) Console.WriteLine("(no mods)");
                    foreach (var f in files) Console.WriteLine(f);
                    return 0;
                case "path":
                    Console.WriteLine(Paths.Mods);
                    return 0;
                case "clear":
                    Mods.Clear();
                    Console.WriteLine("removed all mods");
                    break;
                case "apply": break;
                default: throw new ArgumentException($"unknown mods command '{sub}' (list, apply, clear, path)");
            }
            var dir = Roblox.InstalledDir;
            if (dir != null)
            {
                Roblox.ApplyMods(dir);
                Console.WriteLine("mods applied to Roblox");
            }
            return 0;
        }

        static int AccountsCommand(string[] args)
        {
            var sub = args.FirstOrDefault() ?? "list";
            switch (sub)
            {
                case "list":
                    var list = Accounts.List();
                    var current = Accounts.Current;
                    if (args.Contains("--json"))
                    {
                        Console.WriteLine(Json.Write(new Dictionary<string, object>
                        {
                            ["current"] = current == null ? null : new Dictionary<string, object>
                            {
                                ["userId"] = current.UserId, ["username"] = current.Username, ["displayName"] = current.DisplayName,
                            },
                            ["signedIn"] = Accounts.RobloxSignedIn,
                            ["accounts"] = list.Select(a => new Dictionary<string, object>
                            {
                                ["userId"] = a.UserId, ["username"] = a.Username, ["displayName"] = a.DisplayName,
                                ["savedAt"] = a.SavedAt, ["active"] = a.Active,
                            }).ToList(),
                        }));
                        return 0;
                    }
                    if (list.Count == 0) Console.WriteLine("No saved accounts yet. Run `accounts save` to save the one signed in now.");
                    foreach (var a in list) Console.WriteLine($"  {(a.Active ? "*" : " ")} {a.DisplayName} (@{a.Username})  {a.UserId}");
                    Console.WriteLine(current != null ? $"\nSigned in to Roblox: {current.DisplayName} (@{current.Username})" : "\nRoblox is signed out on this PC.");
                    return 0;
                case "save":
                    var saved = Accounts.Save(auto: args.Contains("--auto"));
                    if (saved != null) Console.WriteLine("saved " + saved);
                    return 0;
                case "use":
                case "switch":
                    if (args.Length < 2) throw new ArgumentException("usage: accounts use WHO");
                    Console.WriteLine("switched to " + Accounts.Use(args[1]));
                    return 0;
                case "add":
                    Accounts.Add();
                    Console.WriteLine("Roblox is signed out on this PC; open Roblox and sign in with the other account");
                    return 0;
                case "remove":
                    if (args.Length < 2) throw new ArgumentException("usage: accounts remove WHO");
                    Accounts.Remove(args[1]);
                    Console.WriteLine("removed " + args[1]);
                    return 0;
                default: throw new ArgumentException($"unknown accounts command '{sub}' (list, save, use, add, remove)");
            }
        }
    }
}
