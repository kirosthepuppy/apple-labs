using System;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Threading;

namespace AppleLabs
{
    public partial class App : Application
    {
        public static string Version
        {
            get
            {
                var v = typeof(App).Assembly.GetName().Version;
                return $"{v.Major}.{v.Minor}.{v.Build}";
            }
        }

        public static string ExePath { get; } = Process.GetCurrentProcess().MainModule?.FileName ?? typeof(App).Assembly.Location;

        static Mutex mainInstance;
        static EventWaitHandle showSignal;

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            var args = e.Args;
            DispatcherUnhandledException += OnCrash;

            if (args.FirstOrDefault() == "--cli")
            {
                Cli.AttachOutput();
                var rest = args.Skip(1).ToArray();
                if (rest.FirstOrDefault() == "selftest") RunSelfTest(rest.Skip(1).FirstOrDefault() ?? "selftest");
                else Shutdown(Cli.Run(rest));
                return;
            }

            var settings = Settings.Load();
            var portable = Environment.GetEnvironmentVariable("APPLELABS_PORTABLE") == "1";

            if (args.Contains("--uninstall"))
            {
                ThemeManager.Apply(new LauncherModel(settings).Theme);
                Setup.UninstallWithQuestions(null);
                Shutdown();
                return;
            }

            if (!portable && Setup.InstallSelf(settings, args))
            {
                Shutdown();
                return;
            }

            var link = args.FirstOrDefault(Roblox.IsRobloxLink);
            var model = new LauncherModel(settings);
            ThemeManager.Apply(model.Theme);

            if (link != null)
            {
                // Launched by a website Play button: a small window that joins and closes.
                var window = new LinkWindow(model);
                MainWindow = window;
                window.Closed += (s, a) => Shutdown();
                window.Show();
                model.LookUpLinkGame(link);
                model.Launch(link, quitAfter: true);
                return;
            }

            // One main window: a second start just brings the first one forward.
            mainInstance = new Mutex(true, @"Local\AppleLabs.Main", out var first);
            showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\AppleLabs.Show");
            if (!first)
            {
                showSignal.Set();
                Shutdown();
                return;
            }
            ShowMain(model);
            var thread = new Thread(() =>
            {
                while (showSignal.WaitOne())
                    Dispatcher.BeginInvoke(new Action(() => ShowMain(model)));
            }) { IsBackground = true };
            thread.Start();
        }

        void ShowMain(LauncherModel model)
        {
            if (MainWindow is MainWindow existing && existing.IsLoaded)
            {
                if (existing.WindowState == WindowState.Minimized) existing.WindowState = WindowState.Normal;
                existing.Activate();
                return;
            }
            var window = new MainWindow(model);
            MainWindow = window;
            window.Closed += (s, a) => Shutdown();
            window.Show();
            model.RefreshStatus();
            model.RefreshGames();
            model.RefreshAccounts();
            model.RobloxExited += () =>
            {
                model.RefreshGames();
                // Keep saved sign-ins fresh, and finish adding a new account.
                model.AutoSaveAccounts();
            };
            if (model.RobloxRunning) model.RefreshAccounts(); else model.AutoSaveAccounts();
        }

        async void RunSelfTest(string folder)
        {
            int code;
            try { code = await SelfTest.Run(folder); }
            catch (Exception ex)
            {
                Console.WriteLine("FAIL selftest: " + ex);
                code = 1;
            }
            Shutdown(code);
        }

        void OnCrash(object sender, DispatcherUnhandledExceptionEventArgs e)
        {
            Log.Error("unhandled: " + e.Exception);
            e.Handled = true;
            if (Environment.GetCommandLineArgs().Contains("--cli"))
            {
                SelfTest.Failures.Add("unhandled: " + e.Exception.Message);
                Console.WriteLine("FAIL unhandled: " + e.Exception);
                return;
            }
            MessageBox.Show("Something went wrong: " + e.Exception.Message + "\n\nDetails are in " + Paths.LogFile,
                "Apple Labs", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
