# ManuBrightness v7.0.0 - Windows-native source edition (first migration trial)
# Windows 10/11 + built-in Windows PowerShell 5.1 / .NET Framework.
# No AutoHotkey, Python, third-party DLL, or precompiled binary is required.
# All code is plain text. C# below is compiled in memory at startup by Add-Type.
# Double-click Main.cmd from the same folder to start.
#
# The Daily and Film math, config migration, hotkeys, and Gamma Ramp guard are
# ported from the tested ManuBrightness v6.1.3 AutoHotkey script.
# In active mode: check every 1000 ms (per-item tolerance 255), force every 30
# checks. Paused mode: no checking, no periodic writes.
#
# This software modifies the global desktop Gamma Ramp. It does not control
# the physical backlight. The Windows API has limitations with HDR, ICC and
# some display drivers. Keep the original AHK version available for rollback.

$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace ManuBrightness.Native
{
    // Only the Windows interop surface belongs here. Everything else is ordinary C#.
    internal static class Win32
    {
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint virtualKey);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool UnregisterHotKey(IntPtr window, int id);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern IntPtr GetDC(IntPtr window);

        [DllImport("user32.dll", SetLastError = true)]
        internal static extern int ReleaseDC(IntPtr window, IntPtr dc);

        [DllImport("gdi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetDeviceGammaRamp(IntPtr dc, [In] ushort[] ramp);

        [DllImport("gdi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetDeviceGammaRamp(IntPtr dc, [Out] ushort[] ramp);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern uint GetPrivateProfileString(
            string section, string key, string defaultValue,
            StringBuilder value, uint valueLength, string fileName);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool WritePrivateProfileString(
            string section, string key, string value, string fileName);
    }

    internal static class Ini
    {
        internal static string Read(string path, string section, string key)
        {
            if (!File.Exists(path)) return "";
            StringBuilder value = new StringBuilder(256);
            Win32.GetPrivateProfileString(section, key, "", value, (uint)value.Capacity, path);
            return value.ToString();
        }

        internal static void Write(string path, string section, string key, string value)
        {
            if (!Win32.WritePrivateProfileString(section, key, value, path))
                throw new IOException("Cannot write ManuBrightness configuration: " + path);
        }

        internal static bool ParseLevel(string text, out double number)
        {
            number = 0;
            if (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out number))
                return false;
            return !double.IsNaN(number) && !double.IsInfinity(number);
        }

        internal static string Number(double value)
        {
            return value.ToString("0.############", CultureInfo.InvariantCulture);
        }
    }

    // Exactly one hidden HWND receives the five system-wide hotkeys.
    // MOD_NOREPEAT is intentionally NOT used: holding +/- continues stepping.
    internal sealed class Hotkeys : NativeWindow, IDisposable
    {
        internal const int Increase = 1;
        internal const int Decrease = 2;
        internal const int Refresh = 3;
        internal const int Pause = 4;
        internal const int ChangeMode = 5;

        private const int WM_HOTKEY = 0x0312;
        private const uint MOD_ALT = 0x0001;
        private readonly Action<int> callback;
        private readonly System.Collections.Generic.List<int> registered =
            new System.Collections.Generic.List<int>();

        internal Hotkeys(Action<int> onHotkey)
        {
            callback = onHotkey;
            CreateParams parameters = new CreateParams();
            parameters.Caption = "ManuBrightness hotkey receiver";
            CreateHandle(parameters);

            try
            {
                Bind(Increase, 0x6B, "Alt + NumPad +"); // VK_ADD
                Bind(Decrease, 0x6D, "Alt + NumPad -"); // VK_SUBTRACT
                Bind(Refresh, 0x6A, "Alt + NumPad *");  // VK_MULTIPLY
                Bind(Pause, 0x6F, "Alt + NumPad /");    // VK_DIVIDE
                Bind(ChangeMode, 0xBB, "Alt + =");      // VK_OEM_PLUS (US layout)
            }
            catch
            {
                Dispose();
                throw;
            }
        }

        private void Bind(int id, uint vk, string label)
        {
            if (!Win32.RegisterHotKey(Handle, id, MOD_ALT, vk))
            {
                int code = Marshal.GetLastWin32Error();
                throw new InvalidOperationException(
                    "Cannot register " + label + " (Windows error " + code + ").\r\n" +
                    "Exit the old AutoHotkey script or any other app using this hotkey, then retry.");
            }
            registered.Add(id);
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == WM_HOTKEY)
            {
                callback(message.WParam.ToInt32());
                return;
            }
            base.WndProc(ref message);
        }

        public void Dispose()
        {
            foreach (int id in registered)
                Win32.UnregisterHotKey(Handle, id);
            registered.Clear();
            if (Handle != IntPtr.Zero) DestroyHandle();
        }
    }

    // Lightweight non-activating tooltip near the pointer (700 ms, like AHK).
    internal sealed class TipWindow : Form
    {
        private readonly Label message;

        internal TipWindow()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            BackColor = Color.FromArgb(38, 38, 38);
            Padding = new Padding(1);

            message = new Label();
            message.Dock = DockStyle.Fill;
            message.BackColor = Color.FromArgb(38, 38, 38);
            message.ForeColor = Color.White;
            message.Font = new Font("Segoe UI", 10f);
            message.TextAlign = ContentAlignment.MiddleCenter;
            Controls.Add(message);
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams p = base.CreateParams;
                p.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
                p.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
                return p;
            }
        }

        internal void Display(string text)
        {
            message.Text = text;
            Size measured = TextRenderer.MeasureText(text, message.Font);
            Size = new Size(measured.Width + 24, measured.Height + 14);

            Point cursor = Cursor.Position;
            Rectangle available = Screen.FromPoint(cursor).WorkingArea;
            int x = Math.Min(cursor.X + 14, available.Right - Width);
            int y = Math.Min(cursor.Y + 21, available.Bottom - Height);
            Location = new Point(Math.Max(available.Left, x), Math.Max(available.Top, y));

            if (!Visible) Show();
            else Invalidate();
        }
    }

    // Numeric core. It preserves the AHK v6.1.3 Daily and Film equations.
    internal static class Curves
    {
        internal const int StepSize = 50;
        internal const int MapVersion = 5;
        internal const int DefaultDaily = 280;
        internal const int DefaultFilm = 600;

        internal static double Clamp(double value)
        {
            return Math.Max(0.0, Math.Min(1000.0, value));
        }

        // AHK Round() uses midpoint-away-from-zero; avoid C#'s default banker's rounding.
        internal static double StepRound(double value)
        {
            return Math.Round(value / StepSize, 0, MidpointRounding.AwayFromZero) * StepSize;
        }

        private static double Lerp(double a, double b, double t)
        {
            return a + (b - a) * t;
        }

        private static double Hermite(double x, double x0, double x1,
                                      double y0, double y1, double slope0, double slope1)
        {
            double width = x1 - x0;
            double t = (x - x0) / width;
            double h00 = 2 * Math.Pow(t, 3) - 3 * Math.Pow(t, 2) + 1;
            double h10 = Math.Pow(t, 3) - 2 * Math.Pow(t, 2) + t;
            double h01 = -2 * Math.Pow(t, 3) + 3 * Math.Pow(t, 2);
            double h11 = Math.Pow(t, 3) - Math.Pow(t, 2);
            return h00 * y0 + h10 * width * slope0 + h01 * y1 + h11 * width * slope1;
        }

        internal static double Effective(double control)
        {
            double c = Clamp(control);
            double middleSlope = (840.0 - 350.0) / (800.0 - 200.0);
            if (c <= 200)
                return Hermite(c, 0, 200, 0, 350, 2.5, middleSlope);
            if (c <= 800)
                return Lerp(350, 840, (c - 200) / 600.0);
            double t = (c - 800) / 200.0;
            return 840 + 160 * (1 - Math.Pow(1 - t, 2.0));
        }

        internal static double V2Effective(double level)
        {
            double c = Clamp(level);
            if (c <= 100) return Lerp(0, 200, c / 100.0);
            if (c <= 900) return Lerp(200, 600, (c - 100) / 800.0);
            return Lerp(600, 1000, (c - 900) / 100.0);
        }

        internal static double V3ToV2(double level)
        {
            double c = Clamp(level);
            if (c <= 200) return Lerp(0, 400, c / 200.0);
            if (c <= 800) return Lerp(400, 960, (c - 200) / 600.0);
            return Lerp(960, 1000, (c - 800) / 200.0);
        }

        internal static double V4Effective(double level)
        {
            double c = Clamp(level);
            double slope = (840.0 - 350.0) / 600.0;
            if (c <= 200) return Hermite(c, 0, 200, 0, 350, 2.5, slope);
            if (c <= 800) return Lerp(350, 840, (c - 200) / 600.0);
            return Hermite(c, 800, 1000, 840, 1000, slope, 1.5);
        }

        internal static double EffectiveToControl(double effective)
        {
            double target = Clamp(effective);
            double lo = 0, hi = 1000;
            for (int i = 0; i < 40; i++)
            {
                double mid = (lo + hi) / 2.0;
                if (Effective(mid) < target) lo = mid;
                else hi = mid;
            }
            return (lo + hi) / 2.0;
        }

        internal static ushort[] Identity()
        {
            ushort[] ramp = new ushort[768];
            for (int i = 0; i < 256; i++)
            {
                ushort v = (ushort)(i * 257); // exact i/255 * 65535
                ramp[i] = ramp[256 + i] = ramp[512 + i] = v;
            }
            return ramp;
        }

        internal static ushort[] Daily(double level)
        {
            double effective = Effective(level);
            double dark = Math.Max(500.0 - effective, 0.0) / 500.0;
            double bright = Math.Max(effective - 500.0, 0.0) / 500.0;
            double gamma = 1.0 + dark * 1.20 - bright * 0.50;
            double gain = 1.0 - dark * 0.85 + bright * 0.25;
            double lift = bright * 0.08;

            ushort[] ramp = new ushort[768];
            for (int i = 0; i < 256; i++)
            {
                double x = i / 255.0;
                double y = Math.Pow(x, gamma) * gain + lift;
                y = Math.Max(0.0, Math.Min(1.0, y));
                ushort v = (ushort)Math.Round(y * 65535.0, 0, MidpointRounding.AwayFromZero);
                ramp[i] = ramp[256 + i] = ramp[512 + i] = v;
            }
            return ramp;
        }

        internal static ushort[] Film(double level)
        {
            double gamma = 0.50 * Math.Exp((600.0 - level) * 0.0035);
            gamma = Math.Max(0.12, Math.Min(4.0, gamma));
            const double toeStart = 0.003;
            const double toeEnd = 0.025;

            ushort[] ramp = new ushort[768];
            for (int i = 0; i < 256; i++)
            {
                double x = i / 255.0;
                double boosted = Math.Pow(x, gamma);
                double y;
                if (gamma < 1.0)
                {
                    double t = (x - toeStart) / (toeEnd - toeStart);
                    t = Math.Max(0.0, Math.Min(1.0, t));
                    double weight = t * t * (3.0 - 2.0 * t);
                    y = x + (boosted - x) * weight;
                }
                else y = boosted;
                y = Math.Max(0.0, Math.Min(1.0, y));
                ushort v = (ushort)Math.Round(y * 65535.0, 0, MidpointRounding.AwayFromZero);
                ramp[i] = ramp[256 + i] = ramp[512 + i] = v;
            }
            return ramp;
        }
    }

    internal sealed class BrightnessApp : ApplicationContext
    {
        private readonly string configFile;
        private readonly string oldConfigFile;
        private readonly Hotkeys hotkeys;
        private readonly System.Windows.Forms.Timer checkTimer;
        private readonly System.Windows.Forms.Timer tipTimer;
        private readonly TipWindow tip;
        private readonly NotifyIcon tray;
        private readonly ContextMenuStrip menu;

        private double level;
        private double dailyLevel;
        private double filmLevel;
        private bool filmMode;
        private bool paused;
        private int checkTicks;
        private ushort[] expectedRamp;

        internal BrightnessApp(string directory)
        {
            configFile = Path.Combine(directory, "ManuBrightness.ini");
            oldConfigFile = Path.Combine(directory, "GpuBrightness.ini");

            // AHK v6.1.3 starts in Daily, and only persists mode levels on edits.
            dailyLevel = LoadDaily();
            filmLevel = LoadFilm();
            level = dailyLevel;
            filmMode = false;
            paused = false;
            expectedRamp = new ushort[768];

            // Register before changing the screen, so an old AHK instance cannot
            // leave this program running with missing or conflicting hotkeys.
            hotkeys = new Hotkeys(OnHotkey);

            checkTimer = new System.Windows.Forms.Timer();
            checkTimer.Interval = 1000;
            checkTimer.Tick += delegate(object sender, EventArgs e) { CheckGamma(); };

            tip = new TipWindow();
            tipTimer = new System.Windows.Forms.Timer();
            tipTimer.Interval = 700;
            tipTimer.Tick += delegate(object sender, EventArgs e)
            {
                tipTimer.Stop();
                tip.Hide();
            };

            menu = new ContextMenuStrip();
            ToolStripMenuItem status = new ToolStripMenuItem("ManuBrightness v7.0.0");
            status.Enabled = false;
            menu.Items.Add(status);
            menu.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem refresh = new ToolStripMenuItem("刷新当前亮度");
            refresh.Click += delegate(object sender, EventArgs e) { Refresh(); };
            menu.Items.Add(refresh);
            ToolStripMenuItem pause = new ToolStripMenuItem("临时暂停");
            pause.Click += delegate(object sender, EventArgs e) { Pause(); };
            menu.Items.Add(pause);
            ToolStripMenuItem switchMode = new ToolStripMenuItem("切换日常 / 影视");
            switchMode.Click += delegate(object sender, EventArgs e) { SwitchMode(); };
            menu.Items.Add(switchMode);
            menu.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem exit = new ToolStripMenuItem("退出（保留当前画面映射）");
            exit.Click += delegate(object sender, EventArgs e) { ExitThread(); };
            menu.Items.Add(exit);

            tray = new NotifyIcon();
            tray.Icon = SystemIcons.Application;
            tray.Text = "ManuBrightness v7.0.0";
            tray.ContextMenuStrip = menu;
            tray.Visible = true;
            tray.DoubleClick += delegate(object sender, EventArgs e)
            {
                Tip("ManuBrightness " + (filmMode ? "影视" : "日常") + ": " + Ini.Number(level));
            };

            ApplyLevel();
        }

        private double LoadDaily()
        {
            double value;
            string raw = Ini.Read(configFile, "Modes", "DailyLevel");
            if (raw != "" && Ini.ParseLevel(raw, out value)) return Curves.Clamp(value);

            string source = configFile;
            raw = Ini.Read(source, "Main", "Level");
            if (raw == "")
            {
                source = oldConfigFile;
                raw = Ini.Read(source, "Main", "Level");
            }
            if (raw == "") return Curves.DefaultDaily;
            if (!Ini.ParseLevel(raw, out value)) value = Curves.DefaultDaily;

            string version = Ini.Read(source, "Main", "MapVersion");
            if (version == "") version = "1";

            if (version == "4") value = Curves.EffectiveToControl(Curves.V4Effective(value));
            else if (version == "3") value = Curves.EffectiveToControl(
                Curves.V2Effective(Curves.V3ToV2(value)));
            else if (version == "2") value = Curves.EffectiveToControl(Curves.V2Effective(value));
            else if (version == "1") value = Curves.EffectiveToControl(value);
            else if (version != "5") value = Curves.DefaultDaily;

            if (version != "5") value = Curves.StepRound(value);
            value = Curves.Clamp(value);

            // Keep GpuBrightness.ini untouched so the previous AHK version can be restored.
            Ini.Write(configFile, "Modes", "DailyLevel", Ini.Number(value));
            Ini.Write(configFile, "Main", "Level", Ini.Number(value));
            Ini.Write(configFile, "Main", "MapVersion", "5");
            return value;
        }

        private double LoadFilm()
        {
            double value;
            string raw = Ini.Read(configFile, "Modes", "FilmLevel");
            return raw != "" && Ini.ParseLevel(raw, out value) ? Curves.Clamp(value) : Curves.DefaultFilm;
        }

        private void SaveLevel()
        {
            if (filmMode)
                Ini.Write(configFile, "Modes", "FilmLevel", Ini.Number(level));
            else
            {
                Ini.Write(configFile, "Modes", "DailyLevel", Ini.Number(level));
                Ini.Write(configFile, "Main", "Level", Ini.Number(level));
                Ini.Write(configFile, "Main", "MapVersion", "5");
            }
        }

        private static bool WriteRamp(ushort[] ramp)
        {
            IntPtr dc = Win32.GetDC(IntPtr.Zero);
            if (dc == IntPtr.Zero) return false;
            try { return Win32.SetDeviceGammaRamp(dc, ramp); }
            finally { Win32.ReleaseDC(IntPtr.Zero, dc); }
        }

        private static bool ReadRamp(ushort[] ramp)
        {
            IntPtr dc = Win32.GetDC(IntPtr.Zero);
            if (dc == IntPtr.Zero) return false;
            try { return Win32.GetDeviceGammaRamp(dc, ramp); }
            finally { Win32.ReleaseDC(IntPtr.Zero, dc); }
        }

        private void ApplyLevel()
        {
            // This method is the only way to resume after Pause.
            paused = false;
            checkTicks = 0;
            expectedRamp = filmMode ? Curves.Film(level) : Curves.Daily(level);
            WriteRamp(expectedRamp);
            checkTimer.Start();
        }

        private void CheckGamma()
        {
            if (paused) return;
            checkTicks++;
            if (checkTicks >= 30)
            {
                ApplyLevel(); // keep the v6.1.3 force-write fallback
                return;
            }

            ushort[] observed = new ushort[768];
            if (!ReadRamp(observed)) return;
            for (int i = 0; i < 768; i++)
            {
                if (Math.Abs((int)observed[i] - (int)expectedRamp[i]) > 255)
                {
                    ApplyLevel();
                    return;
                }
            }
        }

        private void Tip(string text)
        {
            tipTimer.Stop();
            tip.Display(text);
            tipTimer.Start();
        }

        private void OnHotkey(int key)
        {
            try
            {
                switch (key)
                {
                    case Hotkeys.Increase: SetLevel(level + Curves.StepSize); break;
                    case Hotkeys.Decrease: SetLevel(level - Curves.StepSize); break;
                    case Hotkeys.Refresh: Refresh(); break;
                    case Hotkeys.Pause: Pause(); break;
                    case Hotkeys.ChangeMode: SwitchMode(); break;
                }
            }
            catch (Exception error)
            {
                MessageBox.Show(error.Message, "ManuBrightness", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void SetLevel(double value)
        {
            level = Curves.Clamp(Curves.StepRound(value));
            if (filmMode) filmLevel = level;
            else dailyLevel = level;
            ApplyLevel();
            SaveLevel();
            Tip((filmMode ? "影视" : "日常") + "亮度: " + Ini.Number(level));
        }

        private void Refresh()
        {
            ApplyLevel();
            Tip("软件亮度刷新: " + Ini.Number(level));
        }

        private void Pause()
        {
            paused = true;
            checkTicks = 0;
            checkTimer.Stop();
            WriteRamp(Curves.Identity());
            Tip("软件亮度暂停");
        }

        private void SwitchMode()
        {
            if (filmMode)
            {
                filmLevel = level;
                filmMode = false;
                level = dailyLevel;
            }
            else
            {
                dailyLevel = level;
                filmMode = true;
                level = filmLevel;
            }
            ApplyLevel();
            Tip("ManuBrightness " + (filmMode ? "影视" : "日常") + ": " + Ini.Number(level));
        }

        protected override void ExitThreadCore()
        {
            checkTimer.Stop();
            tipTimer.Stop();
            tray.Visible = false;
            tray.Dispose();
            menu.Dispose();
            hotkeys.Dispose();
            tip.Dispose();
            checkTimer.Dispose();
            tipTimer.Dispose();
            base.ExitThreadCore();
        }
    }

    public static class Entry
    {
        public static void Run(string directory)
        {
            bool firstInstance;
            using (Mutex instanceLock = new Mutex(true, @"Local\ManuBrightness_Windows_Source", out firstInstance))
            {
                if (!firstInstance) return;
                try
                {
                    Application.EnableVisualStyles();
                    Application.SetCompatibleTextRenderingDefault(false);
                    Application.Run(new BrightnessApp(directory));
                }
                finally
                {
                    instanceLock.ReleaseMutex();
                }
            }
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $source -Language CSharp `
        -ReferencedAssemblies @('System.dll', 'System.Drawing.dll', 'System.Windows.Forms.dll') `
        -ErrorAction Stop
    [ManuBrightness.Native.Entry]::Run($PSScriptRoot)
}
catch {
    # Hidden PowerShell window: display actionable startup/compile errors as a GUI dialog.
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $details = $_.Exception.ToString()
        [System.Windows.Forms.MessageBox]::Show(
            "ManuBrightness v7.0.0 could not start.`r`n`r`n" + $details,
            'ManuBrightness - startup error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch { }
}
