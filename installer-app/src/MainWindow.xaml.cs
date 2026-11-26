using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using HermesKurulum.Core;
using Microsoft.Win32;

namespace HermesKurulum
{
    public partial class MainWindow : Window
    {
        enum Page { Package = 0, Cert = 1, Run = 2, Model = 3, Summary = 4 }

        readonly ObservableCollection<StepVm> _steps = new ObservableCollection<StepVm>();
        readonly ObservableCollection<TaskVm> _tasks = new ObservableCollection<TaskVm>();
        readonly ObservableCollection<KeyValue> _summary = new ObservableCollection<KeyValue>();
        readonly IEnvironmentStore _env = new WindowsUserEnvironment();
        readonly Redactor _redactor = new Redactor();
        readonly DispatcherTimer _ticker = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        readonly string _stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        readonly string _workDir;
        readonly LogWriter _log;
        CancellationTokenSource _cts = new CancellationTokenSource();

        HermesPaths _paths;
        InstalledInfo _installedBefore;
        InstalledInfo _installedNow;
        BundleInfo _bundle;
        CertCheck _cert;
        string _certPath;
        Page _page = Page.Package;
        bool _busy;
        bool _runOk;
        bool _installRan;
        bool _afterRollback;
        string _backupPath;
        string _versionAfter;
        string _certSummary = "Değiştirilmedi";
        string _modelSummary = "Değiştirilmedi";
        string _runError;
        ModelHelperClient _helper;

        public static string AppVersion => Assembly.GetExecutingAssembly().GetName().Version.ToString(3);

        public MainWindow()
        {
            InitializeComponent();
            Title = "Hermes Kurulum Asistanı " + AppVersion;
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            _workDir = Path.Combine(local, "HermesKurulumAsistani");
            _log = new LogWriter(Path.Combine(_workDir, "logs", "kurulum_" + _stamp + ".log"), _redactor);
            _log.Line += OnLogLine;
            LogPathText.Text = _log.FilePath;

            StepsList.ItemsSource = _steps;
            TaskList.ItemsSource = _tasks;
            SummaryList.ItemsSource = _summary;
            foreach (var (n, t, s) in new[] { (1, "Paket", "ZIP veya klasör"), (2, "Şirket sertifikası", ".crt dosyası"), (3, "Kurulum / güncelleme", "Canlı ilerleme"),
                                              (4, "Model bağlantısı", "hermes model"), (5, "Özet", "Hermes'i aç") })
                _steps.Add(new StepVm { Number = n, Title = t, Subtitle = s });
            _ticker.Tick += (s, e) => { foreach (var t in _tasks) if (t.State == ItemState.Active) t.Tick(); };
            Loaded += (s, e) => Init();
            Closing += OnClosing;
        }

        // ------------------------------------------------------------------ startup
        void Init()
        {
            _log.Info("Hermes Kurulum Asistanı " + AppVersion + " başladı. Windows " + Environment.OSVersion.Version + ", .NET " + Environment.Version +
                      (Environment.Is64BitOperatingSystem ? ", 64-bit" : ", 32-bit"));
            try
            {
                _paths = HermesPaths.ForCurrentUser(_env);
                _installedBefore = _paths.DetectInstalled();
                _log.Info("Hermes klasörü: " + _paths.HomeDir + " | HERMES_HOME: " + _paths.HermesHome);
                _log.Info("Kurulu sürüm: " + _installedBefore.Display);
            }
            catch (Exception ex) { _log.Error(ex.Message); MessageBox.Show(ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Error); }
            ChipInstalled.Text = _installedBefore?.Display ?? "?";
            SkipInstallCheck.IsEnabled = _installedBefore?.IsInstalled == true;
            if (!Environment.Is64BitOperatingSystem) ShowBundleError("Bu paket yalnızca 64-bit Windows'ta çalışır.");
            var cur = CertificateInstaller.DescribeCurrent(_env);
            CurrentCertText.Text = cur == null ? "Şu an ayarlı bir sertifika paketi yok." : "Şu anki ayar: SSL_CERT_FILE = " + cur;
            AutoFindBundle();
            ShowPage(Page.Package);
        }

        /// <summary>Convenience: a bundle ZIP next to the exe (or in Downloads) is pre-selected.</summary>
        void AutoFindBundle()
        {
            try
            {
                var dirs = new List<string> { AppDomain.CurrentDomain.BaseDirectory };
                var dl = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                if (Directory.Exists(dl)) dirs.Add(dl);
                foreach (var d in dirs)
                {
                    var zip = Directory.GetFiles(d, "HermesAirgapBundle_*_Win10_Desktop.zip").OrderByDescending(f => File.GetLastWriteTime(f)).FirstOrDefault();
                    if (zip != null) { LoadBundle(zip); return; }
                }
            }
            catch { }
        }

        public void LogUnhandled(Exception ex) => _log.Error("Beklenmeyen hata: " + ex);

        void OnLogLine(string level, string line)
        {
            Dispatcher.BeginInvoke(new Action(() =>
            {
                LogBox.AppendText(line + Environment.NewLine);
                if (LogBox.LineCount > 6000) LogBox.Text = LogBox.Text.Substring(LogBox.Text.Length / 3);
                LogBox.ScrollToEnd();
            }));
        }

        void OnClosing(object sender, System.ComponentModel.CancelEventArgs e)
        {
            if (_busy)
            {
                MessageBox.Show("Kurulum sürüyor. Yarıda kesmek Hermes kurulumunu bozabilir; lütfen bitmesini bekleyin.", Title, MessageBoxButton.OK, MessageBoxImage.Warning);
                e.Cancel = true;
                return;
            }
            try { _log.Info("Asistan kapatıldı."); } catch { }
        }

        // ------------------------------------------------------------------ navigation
        void ShowPage(Page p)
        {
            _page = p;
            PagePackage.Visibility = p == Page.Package ? Visibility.Visible : Visibility.Collapsed;
            PageCert.Visibility = p == Page.Cert ? Visibility.Visible : Visibility.Collapsed;
            PageRun.Visibility = p == Page.Run ? Visibility.Visible : Visibility.Collapsed;
            PageModel.Visibility = p == Page.Model ? Visibility.Visible : Visibility.Collapsed;
            PageSummary.Visibility = p == Page.Summary ? Visibility.Visible : Visibility.Collapsed;
            for (int i = 0; i < _steps.Count; i++) _steps[i].SetCurrent(i == (int)p);
            PageScroller.ScrollToTop();
            UpdateButtons();
        }

        void UpdateButtons()
        {
            BackBtn.Visibility = Visibility.Visible;
            FooterHint.Text = "";
            switch (_page)
            {
                case Page.Package:
                    BackBtn.Visibility = Visibility.Collapsed;
                    NextBtn.Content = "İleri  →";
                    NextBtn.IsEnabled = PackageReady(out var why);
                    FooterHint.Text = why;
                    break;
                case Page.Cert:
                    BackBtn.IsEnabled = true;
                    NextBtn.Content = SkipInstallCheck.IsChecked == true ? "Uygula  ▶" : "Kurulumu başlat  ▶";
                    NextBtn.IsEnabled = SkipCertCheck.IsChecked == true || (_cert != null && _cert.Ok);
                    if (!NextBtn.IsEnabled) FooterHint.Text = "Sertifika dosyasını seçin ya da adımı atlayın.";
                    break;
                case Page.Run:
                    BackBtn.Visibility = Visibility.Collapsed;
                    NextBtn.Content = _runOk && !_afterRollback ? "Model ayarına geç  →" : "Özeti göster  →";
                    NextBtn.IsEnabled = !_busy;
                    FooterHint.Text = _busy ? "Çalışıyor… Pencereyi kapatmayın." : "";
                    break;
                case Page.Model:
                    BackBtn.Visibility = Visibility.Collapsed;
                    NextBtn.Content = ModelEnableCheck.IsChecked == true ? "Kaydet ve bitir  ✓" : "Atla ve bitir  →";
                    NextBtn.IsEnabled = !_busy && (ModelEnableCheck.IsChecked != true || ModelInputsReady());
                    if (ModelEnableCheck.IsChecked == true && !ModelInputsReady()) FooterHint.Text = "Adres ve model gerekli.";
                    break;
                case Page.Summary:
                    BackBtn.Visibility = Visibility.Collapsed;
                    NextBtn.Content = "Kapat";
                    NextBtn.IsEnabled = !_busy;
                    break;
            }
        }

        async void Next_Click(object sender, RoutedEventArgs e)
        {
            switch (_page)
            {
                case Page.Package:
                    _steps[0].State = SkipInstallCheck.IsChecked == true ? ItemState.Skipped : ItemState.Done;
                    ShowPage(Page.Cert);
                    break;
                case Page.Cert:
                    if (!ConfirmStart()) return;
                    _steps[1].State = SkipCertCheck.IsChecked == true ? ItemState.Skipped : ItemState.Done;
                    ShowPage(Page.Run);
                    await RunAllAsync();
                    break;
                case Page.Run:
                    if (_afterRollback) { ShowSummary(); }
                    else if (_runOk) { await EnterModelPageAsync(); }
                    else { _steps[3].State = ItemState.Skipped; ShowSummary(); }
                    break;
                case Page.Model:
                    if (ModelEnableCheck.IsChecked == true) { if (await ApplyModelAsync()) ShowSummary(); }
                    else { _steps[3].State = ItemState.Skipped; ShowSummary(); }
                    break;
                case Page.Summary:
                    Close();
                    break;
            }
        }

        void Back_Click(object sender, RoutedEventArgs e)
        {
            if (_page == Page.Cert) ShowPage(Page.Package);
        }

        bool ConfirmStart()
        {
            if (SkipInstallCheck.IsChecked == true) return true;
            var running = HermesCommands.RunningHermes(_paths);
            while (running.Count > 0)
            {
                var r = MessageBox.Show("Hermes şu an açık. Kurulumdan önce masaüstü penceresini ve hermes çalışan komut satırlarını kapatın.\n\nAçık olanlar: " +
                                        string.Join(", ", running) + "\n\nKapattıktan sonra Tamam'a basın (vazgeçmek için İptal).", Title,
                                        MessageBoxButton.OKCancel, MessageBoxImage.Warning, MessageBoxResult.OK);
                if (r != MessageBoxResult.OK) return false;
                running = HermesCommands.RunningHermes(_paths);
            }
            return true;
        }

        // ------------------------------------------------------------------ page 1: package
        void PickBundleZip_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new OpenFileDialog { Title = "Hermes paketini seçin", Filter = "Hermes paketi (*.zip)|*.zip|Tüm dosyalar (*.*)|*.*" };
            if (dlg.ShowDialog(this) == true) LoadBundle(dlg.FileName);
        }

        void PickBundleFolder_Click(object sender, RoutedEventArgs e)
        {
            var p = PickFolder("Açılmış Hermes paket klasörünü seçin (içinde BUNDLE.json olan)", BundlePathBox.Text);
            if (p != null) LoadBundle(p);
        }

        void PickExtractFolder_Click(object sender, RoutedEventArgs e)
        {
            var p = PickFolder("ZIP'in açılacağı klasörü seçin", ExtractPathBox.Text);
            if (p != null) ExtractPathBox.Text = p;
        }

        static string PickFolder(string description, string start)
        {
            using (var dlg = new System.Windows.Forms.FolderBrowserDialog { Description = description, ShowNewFolderButton = true })
            {
                if (!string.IsNullOrEmpty(start) && Directory.Exists(start)) dlg.SelectedPath = start;
                return dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK ? dlg.SelectedPath : null;
            }
        }

        void LoadBundle(string path)
        {
            BundleError.Visibility = Visibility.Collapsed;
            BundlePathBox.Text = path;
            try
            {
                _bundle = BundleInfo.Open(path);
                _log.Info("Paket: " + _bundle.SourcePath + " -> " + _bundle.Release + " (factory " + _bundle.Factory + ")");
                ChipBundle.Text = _bundle.Release;
                InfoBundleVersion.Text = _bundle.Release + (string.IsNullOrEmpty(_bundle.Factory) ? "" : "   ·   factory " + _bundle.Factory);
                InfoInstalled.Text = _installedBefore?.Display ?? "?";
                InfoAction.Text = DescribeAction();
                InfoSize.Text = _bundle.IsZip
                    ? $"ZIP {Gb(_bundle.ZipBytes)} · açılınca {Gb(_bundle.UncompressedBytes)} · kurulunca ~{Gb(_bundle.AppBytes)}"
                    : $"Kurulunca ~{Gb(_bundle.AppBytes)} ({_bundle.AppFiles:N0} dosya)";
                InfoSha.Text = !_bundle.IsZip ? "Klasör seçildi; kurulum betiği her dosyayı manifest ile doğrular."
                             : _bundle.ExpectedSha256 != null ? "Yanındaki .sha256 dosyası bulundu; ZIP açılmadan önce doğrulanacak."
                             : "Yanında .sha256 dosyası yok; ZIP doğrulaması atlanacak (kurulum betiği yine her dosyayı doğrular).";
                BundleInfoPanel.Visibility = Visibility.Visible;
                ExtractCard.Visibility = _bundle.IsZip ? Visibility.Visible : Visibility.Collapsed;
                ValidateExtractPath();
            }
            catch (Exception ex)
            {
                _bundle = null;
                ChipBundle.Text = "geçersiz";
                BundleInfoPanel.Visibility = Visibility.Collapsed;
                ShowBundleError(ex.Message);
                _log.Warn("Paket okunamadı: " + ex.Message);
            }
            UpdateButtons();
        }

        string DescribeAction()
        {
            if (_bundle == null) return "";
            if (_installedBefore == null || !_installedBefore.IsInstalled) return "Yeni kurulum (" + _bundle.Release + ")";
            if (_installedBefore.Kind == InstallKind.Legacy) return "Eski (venv) kurulumdan " + _bundle.Release + " masaüstü sürümüne geçiş";
            if (_installedBefore.Version == null) return "Güncelleme → " + _bundle.Release;
            int c = HermesPaths.CompareVersions(_installedBefore.Version, _bundle.Release);
            if (c < 0) return "Güncelleme: " + _installedBefore.Version + " → " + _bundle.Release;
            if (c == 0) return "Aynı sürümü yeniden kurma (" + _bundle.Release + ") — onarım için";
            return "DİKKAT: Sürüm düşürme " + _installedBefore.Version + " → " + _bundle.Release;
        }

        static string Gb(long bytes) => bytes >= 1L << 30 ? (bytes / (double)(1L << 30)).ToString("0.0") + " GB" : (bytes / (double)(1L << 20)).ToString("0") + " MB";

        void ShowBundleError(string msg) { BundleError.Text = msg; BundleError.Visibility = Visibility.Visible; }

        void ExtractPathBox_TextChanged(object sender, TextChangedEventArgs e) { if (IsLoaded) { ValidateExtractPath(); UpdateButtons(); } }

        string _extractProblem;
        void ValidateExtractPath()
        {
            _extractProblem = null;
            if (_bundle == null || !_bundle.IsZip) return;
            var t = (ExtractPathBox.Text ?? "").Trim().Trim('"');
            try
            {
                if (t.Length == 0) _extractProblem = "Açılacak klasörü yazın.";
                else if (!Path.IsPathRooted(t)) _extractProblem = "Tam bir yol yazın (ör. C:\\Tools\\HermesAirgapBundle).";
                else
                {
                    var full = Path.GetFullPath(t);
                    if (_paths != null && (full + "\\").StartsWith(_paths.HomeDir + "\\", StringComparison.OrdinalIgnoreCase))
                        _extractProblem = "Paketi %LOCALAPPDATA%\\hermes içine açmayın.";
                    else if (_bundle.LongestExtractedPath(full) >= 259)
                        _extractProblem = "Bu yol çok uzun: en uzun dosya yolu " + _bundle.LongestExtractedPath(full) + " karakter olur (sınır 259). Daha kısa bir klasör seçin, ör. C:\\H4.";
                    else
                    {
                        var drive = new DriveInfo(Path.GetPathRoot(full));
                        long need = _bundle.UncompressedBytes + (256L << 20);
                        if (drive.IsReady && drive.AvailableFreeSpace < need) _extractProblem = $"{drive.Name} sürücüsünde yer yetersiz: {Gb(drive.AvailableFreeSpace)} boş, ~{Gb(need)} gerekli.";
                    }
                }
            }
            catch (Exception ex) { _extractProblem = "Geçersiz yol: " + ex.Message; }
            ExtractHint.Text = _extractProblem ?? "Kısa bir yol seçin (Windows 260 karakter yol sınırı). %LOCALAPPDATA%\\hermes içine açmayın.";
            ExtractHint.Foreground = (System.Windows.Media.Brush)FindResource(_extractProblem == null ? "Muted" : "Bad");
        }

        bool PackageReady(out string why)
        {
            why = "";
            if (SkipInstallCheck.IsChecked == true) return true;
            if (_bundle == null) { why = "Hermes paketini seçin."; return false; }
            if (_bundle.IsZip && _extractProblem != null) { why = _extractProblem; return false; }
            return true;
        }

        void SkipInstall_Changed(object sender, RoutedEventArgs e)
        {
            if (!IsLoaded) return;
            InfoAction.Text = SkipInstallCheck.IsChecked == true ? "Kurulum atlanacak (yalnızca ayarlar)" : DescribeAction();
            UpdateButtons();
        }

        // ------------------------------------------------------------------ page 2: certificate
        void PickCert_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new OpenFileDialog
            {
                Title = "Şirket sertifikasını seçin",
                Filter = "Sertifika dosyaları (*.crt;*.cer;*.pem;*.der;*.p7b)|*.crt;*.cer;*.pem;*.der;*.p7b|Tüm dosyalar (*.*)|*.*",
                InitialDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
            };
            if (dlg.ShowDialog(this) != true) return;
            LoadCert(dlg.FileName);
        }

        void LoadCert(string path)
        {
            _certPath = path;
            CertPathBox.Text = path;
            _cert = CertificateTools.Inspect(path, DateTime.Now);
            CertInfoPanel.Visibility = Visibility.Visible;
            CertList.ItemsSource = _cert.Certificates.Select(c => new CertVm(c)).ToList();
            var msgs = new List<string>();
            msgs.AddRange(_cert.Errors.Select(m => "✕ " + m));
            msgs.AddRange(_cert.Warnings.Select(m => "! " + m));
            CertMessages.Text = string.Join("\n", msgs);
            CertMessages.Visibility = msgs.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            if (_cert.Ok)
            {
                CertStatus.Text = _cert.Warnings.Count == 0 ? "✓ Geçerli sertifika (" + _cert.Certificates.Count + ")" : "✓ Kullanılabilir, ancak uyarılara bakın";
                CertStatus.Foreground = (System.Windows.Media.Brush)FindResource(_cert.Warnings.Count == 0 ? "Good" : "Warn");
                CertInfoPanel.Background = (System.Windows.Media.Brush)FindResource(_cert.Warnings.Count == 0 ? "GoodSoft" : "WarnSoft");
                SkipCertCheck.IsChecked = false;
            }
            else
            {
                CertStatus.Text = "✕ Bu dosya kullanılamaz";
                CertStatus.Foreground = (System.Windows.Media.Brush)FindResource("Bad");
                CertInfoPanel.Background = (System.Windows.Media.Brush)FindResource("BadSoft");
            }
            _log.Info("Sertifika dosyası: " + path + " -> " + (_cert.Ok ? "geçerli" : "geçersiz") + ", " + _cert.Certificates.Count + " sertifika" +
                      (_cert.Certificates.Count > 0 ? " (" + string.Join("; ", _cert.Certificates.Select(c => c.Subject + ", " + c.Kind + ", " + c.Cert.NotAfter.ToString("yyyy-MM-dd"))) + ")" : ""));
            foreach (var m in _cert.Errors) _log.Warn(m);
            foreach (var m in _cert.Warnings) _log.Warn(m);
            UpdateButtons();
        }

        void SkipCert_Changed(object sender, RoutedEventArgs e) { if (IsLoaded) UpdateButtons(); }

        // ------------------------------------------------------------------ page 3: run
        TaskVm AddTask(string key, string title, double weight)
        {
            var t = new TaskVm { Key = key, Title = title, Weight = weight };
            _tasks.Add(t); return t;
        }

        void SetProgress(TaskVm t, double fraction, string detail = null)
        {
            Dispatcher.BeginInvoke(new Action(() =>
            {
                t.Fraction = Math.Max(0, Math.Min(1, fraction));
                if (detail != null) t.Detail = detail;
                RefreshOverall();
            }));
        }

        void RefreshOverall()
        {
            double total = _tasks.Sum(x => x.Weight), done = _tasks.Sum(x => x.Weight * (x.State == ItemState.Pending ? 0 : x.Fraction));
            int pct = total <= 0 ? 0 : (int)Math.Round(100 * done / total);
            OverallBar.Value = pct;
            OverallPercent.Text = pct + "%";
            var active = _tasks.FirstOrDefault(x => x.State == ItemState.Active);
            if (active != null) { CurrentPhase.Text = active.Title; CurrentDetail.Text = string.IsNullOrEmpty(active.Detail) ? " " : active.Detail; }
        }

        void Begin(TaskVm t) { t.State = ItemState.Active; _log.Info("▶ " + t.Title); RefreshOverall(); }
        void Finish(TaskVm t, ItemState s, string detail = null) { if (detail != null) t.Detail = detail; t.State = s; RefreshOverall(); }

        async Task RunAllAsync()
        {
            _busy = true; _runOk = false; _runError = null;
            _tasks.Clear();
            RunErrorPanel.Visibility = Visibility.Collapsed;
            _steps[2].State = ItemState.Active;
            _ticker.Start();
            UpdateButtons();
            var ct = _cts.Token;

            bool doInstall = SkipInstallCheck.IsChecked != true;
            bool doCert = SkipCertCheck.IsChecked != true && _cert != null && _cert.Ok;
            TaskVm tSha = null, tExtract = null, tInstall = null, tCert = null;
            if (doInstall && _bundle.IsZip)
            {
                tSha = AddTask("sha", "Paket bütünlüğü (SHA256)", 8);
                tExtract = AddTask("extract", "ZIP açılıyor", 22);
            }
            if (doInstall)
            {
                var from = _installedBefore?.IsInstalled == true ? (_installedBefore.Version ?? "mevcut kurulum") : null;
                tInstall = AddTask("install", from == null ? "Hermes " + _bundle.Release + " kuruluyor" : "Hermes güncelleniyor: " + from + " → " + _bundle.Release, 55);
            }
            tCert = AddTask("cert", doCert ? "Şirket sertifikası kuruluyor" : "Şirket sertifikası", 5);
            var tVerify = AddTask("verify", "Doğrulama: hermes --version", 10);
            RunTitle.Text = doInstall ? "3. Kurulum / güncelleme" : "3. Ayarlar uygulanıyor";
            RunLead.Text = doInstall ? "Lütfen bekleyin; bu işlem genellikle 5–15 dakika sürer. Bu sırada Hermes'i açmayın ve bu pencereyi kapatmayın." : "Kurulum atlandı; sertifika ve doğrulama adımları çalışıyor.";
            RefreshOverall();

            try
            {
                // 1) SHA256
                if (tSha != null)
                {
                    Begin(tSha);
                    if (_bundle.ExpectedSha256 == null) Finish(tSha, ItemState.Skipped, ".sha256 dosyası yok; atlandı (kurulum betiği dosyaları tek tek doğrular).");
                    else
                    {
                        var actual = await Task.Run(() => BundleInfo.ComputeSha256(_bundle.SourcePath, f => SetProgress(tSha, f, "%" + (int)(f * 100) + " okundu"), ct));
                        if (!string.Equals(actual, _bundle.ExpectedSha256, StringComparison.OrdinalIgnoreCase))
                            throw new StepException(tSha, "ZIP'in SHA256 değeri .sha256 dosyasıyla uyuşmuyor; aktarım bozulmuş olabilir. Dosyayı yeniden aktarın.\nBeklenen: " + _bundle.ExpectedSha256 + "\nHesaplanan: " + actual);
                        _log.Ok("SHA256 doğru: " + actual);
                        Finish(tSha, ItemState.Done, "SHA256 doğru");
                    }
                }
                // 2) Extract
                if (tExtract != null)
                {
                    Begin(tExtract);
                    var target = ExtractPathBox.Text.Trim().Trim('"');
                    string root;
                    try
                    {
                        root = await Task.Run(() => _bundle.Extract(target, (f, d) => SetProgress(tExtract, f, d), m => _log.Info(m), ct));
                    }
                    catch (Exception ex) when (!(ex is OperationCanceledException)) { throw new StepException(tExtract, "ZIP açılamadı: " + ex.Message); }
                    _log.Ok("Paket açıldı: " + root);
                    Finish(tExtract, ItemState.Done, root);
                }
                // 3) Bundle installer
                if (tInstall != null)
                {
                    Begin(tInstall);
                    await RunInstallerAsync(tInstall, "Auto", ct);
                }
                _installedNow = _paths.DetectInstalled();

                // 4) Certificate
                if (doCert)
                {
                    Begin(tCert);
                    try
                    {
                        var res = await Task.Run(() => new CertificateInstaller(_env, m => _log.Info(m))
                            .Install(_paths, _cert.Certificates, _installedNow?.Runtime?.CertifiBundle, StoreCheckValue, _stamp));
                        foreach (var s in res.StoreAdded) _log.Ok("Windows deposu: " + s);
                        foreach (var w in res.StoreWarnings) _log.Warn(w);
                        _certSummary = string.Join(", ", _cert.Certificates.Select(c => c.Subject)) + " → " + res.BundlePath +
                                       (res.StoreAdded.Count > 0 ? " (+ Windows kullanıcı deposu)" : "");
                        Finish(tCert, res.StoreWarnings.Count > 0 ? ItemState.Warning : ItemState.Done,
                               "SSL_CERT_FILE, REQUESTS_CA_BUNDLE, CURL_CA_BUNDLE, NODE_EXTRA_CA_CERTS ayarlandı" +
                               (res.StoreWarnings.Count > 0 ? " · Windows deposu: " + res.StoreWarnings[0] : res.StoreAdded.Count > 0 ? " · Windows deposuna eklendi" : ""));
                    }
                    catch (Exception ex) { throw new StepException(tCert, "Sertifika kurulamadı: " + ex.Message); }
                }
                else
                {
                    Finish(tCert, ItemState.Skipped, "Atlandı" + (CertificateInstaller.DescribeCurrent(_env) is string c ? " · mevcut: " + c : ""));
                    _certSummary = CertificateInstaller.DescribeCurrent(_env) is string c2 ? "Değiştirilmedi (mevcut: " + c2 + ")" : "Kurulmadı";
                }

                // 5) Verify
                Begin(tVerify);
                SetProgress(tVerify, 0.3, "hermes --version çalıştırılıyor (ilk çalıştırma biraz sürebilir)");
                _versionAfter = await HermesCommands.VersionAsync(_paths, _env, m => _log.Warn(m), ct);
                if (_versionAfter == null) throw new StepException(tVerify, "hermes --version çalışmadı. Ayrıntılar kayıt dosyasında.");
                _log.Ok("hermes --version: " + _versionAfter);
                if (doInstall && !_versionAfter.Contains(_bundle.Release.TrimStart('v')))
                    Finish(tVerify, ItemState.Warning, _versionAfter + "  (beklenen " + _bundle.Release + ")");
                else Finish(tVerify, ItemState.Done, _versionAfter);

                _runOk = true;
                _steps[2].State = ItemState.Done;
                CurrentPhase.Text = "Tamamlandı";
                CurrentDetail.Text = _versionAfter;
                OverallBar.Value = 100; OverallPercent.Text = "100%";
                RunLead.Text = "Her şey yolunda. Sıradaki adım: model bağlantısı.";
                ChipInstalled.Text = _installedNow?.Display ?? ChipInstalled.Text;
            }
            catch (OperationCanceledException) { Fail(null, "İşlem iptal edildi."); }
            catch (StepException sx) { Fail(sx.Task, sx.Message); }
            catch (Exception ex) { Fail(_tasks.FirstOrDefault(t => t.State == ItemState.Active), ex.Message); _log.Error(ex.ToString()); }
            finally
            {
                _busy = false;
                _ticker.Stop();
                UpdateButtons();
            }
        }

        bool StoreCheckValue => Dispatcher.Invoke(() => StoreCheck.IsChecked == true);

        void Fail(TaskVm t, string message)
        {
            _runOk = false; _runError = message;
            if (t != null) Finish(t, ItemState.Error, message.Split('\n')[0]);
            _steps[2].State = ItemState.Error;
            CurrentPhase.Text = "Hata";
            RunErrorText.Text = message + (_installRan ? "\n\nKurulum betiği hata durumunda önceki sürümü otomatik geri yükler; ayrıntılar kayıtta." : "");
            RunErrorPanel.Visibility = Visibility.Visible;
            LogExpander.IsExpanded = true;
            _log.Error(message);
        }

        async Task RunInstallerAsync(TaskVm t, string mode, CancellationToken ct)
        {
            var root = _bundle.ExtractedRoot;
            var parser = new InstallerOutputParser { TotalFiles = _bundle.AppFiles };
            string lastError = null;
            _installRan = true;
            _log.Info("Kurulum betiği: " + Path.Combine(root, BundleInfo.InstallerScript) + " -Mode " + mode + (mode == "Rollback" ? "" : " -CleanVenv"));
            var r = await BundleInstaller.RunAsync(root, mode, line =>
            {
                _log.Raw(line);
                var p = parser.Feed(line);
                if (p == null) return;
                if (p.BackupPath != null) _backupPath = p.BackupPath;
                if (p.ErrorText != null) lastError = p.ErrorText;
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    if (p.Phase != null) t.Detail = p.Phase + (p.Detail != null ? " · " + p.Detail : "");
                    else if (p.Detail != null) t.Detail = (parser.LastPhase != null ? parser.LastPhase + " · " : "") + p.Detail;
                    if (p.Fraction.HasValue) t.Fraction = p.Fraction.Value;
                    RefreshOverall();
                }));
            }, ct);
            if (r.TimedOut) throw new StepException(t, "Kurulum betiği 90 dakikada bitmedi ve durduruldu.");
            if (r.ExitCode != 0)
                throw new StepException(t, "Kurulum betiği hata verdi (çıkış kodu " + r.ExitCode + "): " + (lastError ?? "ayrıntılar kayıtta") +
                                           (mode == "Rollback" ? "" : "\nÖnceki kurulum betik tarafından otomatik geri yüklendi (\"Previous installation restored\" satırına bakın)."));
            Finish(t, ItemState.Done, mode == "Rollback" ? "Geri alma tamamlandı" : "Kurulum tamamlandı" + (_backupPath != null ? " · yedek: " + _backupPath : ""));
        }

        sealed class StepException : Exception
        {
            public TaskVm Task { get; }
            public StepException(TaskVm t, string m) : base(m) { Task = t; }
        }

        // ------------------------------------------------------------------ page 4: model
        async Task EnterModelPageAsync()
        {
            ShowPage(Page.Model);
            _installedNow = _installedNow ?? _paths.DetectInstalled();
            var rt = _installedNow?.Runtime;
            if (rt?.Problem() != null || rt == null)
            {
                CurrentModelText.Text = "Hermes çalışma ortamı bulunamadı (" + (rt?.Problem() ?? "install-stamp.json yok") + "). Modeli sonra `hermes model` ile ayarlayın.";
                ModelEnableCheck.IsChecked = false; ModelEnableCheck.IsEnabled = false;
                UpdateButtons(); return;
            }
            _helper = new ModelHelperClient(_paths, rt, HermesCommands.FreshEnv(_paths, _env), _redactor);
            try { _helper.UseScript(ModelHelperClient.ExtractScript(Path.Combine(_workDir, "helper"))); }
            catch (Exception ex) { _log.Error("Yardımcı betik çıkarılamadı: " + ex.Message); }
            _busy = true; UpdateButtons();
            CurrentModelText.Text = "Mevcut ayar okunuyor…";
            var show = await _helper.ShowAsync(_cts.Token);
            _busy = false;
            if (show.Ok && !string.IsNullOrEmpty(show.Data.Str("model")))
            {
                var cur = show.Data.Str("model") + (string.IsNullOrEmpty(show.Data.Str("base_url")) ? "" : "  ·  " + show.Data.Str("base_url"));
                CurrentModelText.Text = "Şu anki model: " + cur + ". Değiştirmek istemiyorsanız işareti kaldırın; ayar korunur.";
                _log.Info("Mevcut model ayarı: " + cur);
                _modelSummary = "Değiştirilmedi (" + cur + ")";
                ModelEnableCheck.IsChecked = false;
                if (string.IsNullOrEmpty(BaseUrlBox.Text)) BaseUrlBox.Text = show.Data.Str("base_url");
                if (string.IsNullOrEmpty(DisplayNameBox.Text)) DisplayNameBox.Text = show.Data.Str("display_name");
            }
            else
            {
                CurrentModelText.Text = show.Ok ? "Henüz model ayarlanmamış." : "Mevcut ayar okunamadı: " + (show.Message ?? show.Error);
                if (!show.Ok) _log.Warn("Mevcut model ayarı okunamadı: " + show.Message + "\n" + show.Raw);
                ModelEnableCheck.IsChecked = true;
                _modelSummary = "Ayarlanmadı";
            }
            ModelEnable_Changed(null, null);
        }

        void ModelEnable_Changed(object sender, RoutedEventArgs e)
        {
            if (!IsLoaded) return;
            ModelForm.IsEnabled = ModelEnableCheck.IsChecked == true;
            ModelForm.Opacity = ModelForm.IsEnabled ? 1 : 0.55;
            UpdateButtons();
        }

        void ModelInput_Changed(object sender, TextChangedEventArgs e)
        {
            BaseUrlPlaceholder.Visibility = string.IsNullOrEmpty(BaseUrlBox.Text) ? Visibility.Visible : Visibility.Collapsed;
            if (IsLoaded) UpdateButtons();
        }

        void ApiKey_Changed(object sender, RoutedEventArgs e) { if (IsLoaded) UpdateButtons(); }

        bool ModelInputsReady()
        {
            var u = (BaseUrlBox.Text ?? "").Trim();
            return (u.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || u.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                   && !string.IsNullOrWhiteSpace(ModelCombo.Text);
        }

        async void FetchModels_Click(object sender, RoutedEventArgs e)
        {
            if (_helper == null) return;
            var url = BaseUrlBox.Text.Trim();
            if (!(url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)))
            { SetProbe("Adres http:// veya https:// ile başlamalı.", "Bad"); return; }
            _busy = true; FetchModelsBtn.IsEnabled = false; UpdateButtons();
            SetProbe("Modeller getiriliyor…", "Muted");
            _log.Info("Model listesi isteniyor: " + url + "/models");
            try
            {
                var key = ApiKeyBox.Password;
                _redactor.Add(key);
                var r = await _helper.ProbeAsync(url, key, _cts.Token);
                if (r.Ok)
                {
                    var models = r.Data.StrList("models");
                    var previous = ModelCombo.Text;
                    ModelCombo.ItemsSource = models;
                    if (models.Contains(previous)) ModelCombo.Text = previous;
                    else if (models.Count > 0) ModelCombo.SelectedIndex = 0;
                    var resolved = r.Data.Str("resolved_base_url");
                    string note = "";
                    if (r.Data.Bool("used_fallback") && !string.IsNullOrEmpty(resolved))
                    {
                        BaseUrlBox.Text = resolved;
                        note = " Adres " + resolved + " olarak düzeltildi (Hermes da aynısını yapar).";
                    }
                    SetProbe("✓ " + models.Count + " model bulundu." + note, "Good");
                    _log.Ok("Model listesi: " + string.Join(", ", models));
                }
                else
                {
                    var msg = ModelHelperClient.ExplainProbe(r);
                    SetProbe("✕ " + msg + " Model adını elle de yazabilirsiniz.", "Bad");
                    _log.Warn("Model listesi alınamadı: " + msg + (r.Data.Obj("diagnosis") is Dictionary<string, object> d ? " [" + d.Str("code") + ": " + d.Str("detail") + "]" : ""));
                    if (!string.IsNullOrEmpty(r.Raw) && r.Error != "no_models") _log.Raw(r.Raw);
                }
            }
            finally { _busy = false; FetchModelsBtn.IsEnabled = true; UpdateButtons(); }
        }

        void SetProbe(string text, string brush)
        {
            ProbeStatus.Text = text;
            ProbeStatus.Foreground = (System.Windows.Media.Brush)FindResource(brush);
        }

        async Task<bool> ApplyModelAsync()
        {
            var url = BaseUrlBox.Text.Trim();
            var model = ModelCombo.Text.Trim();
            var mode = (ApiModeCombo.SelectedItem as ComboBoxItem)?.Tag as string ?? "";
            var ctx = ContextLenBox.Text.Trim();
            _busy = true; UpdateButtons();
            ModelResultPanel.Visibility = Visibility.Collapsed;
            _log.Info("Model ayarı kaydediliyor (hermes model → Custom endpoint): " + model + " @ " + url + ", mod: " + (mode == "" ? "otomatik" : mode));
            try
            {
                var key = ApiKeyBox.Password;
                _redactor.Add(key);
                var r = await _helper.ApplyAsync(url, key, model, DisplayNameBox.Text.Trim(), ctx, mode, _cts.Token);
                foreach (var p in r.Data.StrList("prompts")) _log.Raw("  hermes model › " + p);
                foreach (var l in r.Data.StrList("transcript")) _log.Raw("  hermes › " + l);
                if (r.Ok)
                {
                    _modelSummary = r.Data.Str("model") + "  ·  " + r.Data.Str("base_url") + "  ·  anahtar: " + (r.Data.Str("key_reference").Length > 0 ? ".env (" + r.Data.Str("key_reference") + ")" : "yok");
                    _log.Ok("Model kaydedildi: " + _modelSummary);
                    _steps[3].State = ItemState.Done;
                    return true;
                }
                var msg = r.Message ?? r.Error;
                ModelResultText.Text = "✕ Kaydedilemedi: " + msg + "\nAyrıntılar kayıt dosyasında. İsterseniz bu adımı atlayıp daha sonra komut satırında `hermes model` çalıştırabilirsiniz.";
                ModelResultText.Foreground = (System.Windows.Media.Brush)FindResource("Bad");
                ModelResultPanel.Background = (System.Windows.Media.Brush)FindResource("BadSoft");
                ModelResultPanel.Visibility = Visibility.Visible;
                _log.Error("Model kaydedilemedi: " + msg);
                if (!string.IsNullOrEmpty(r.Raw) && r.Data.StrList("transcript").Count == 0) _log.Raw(r.Raw);
                return false;
            }
            finally { _busy = false; UpdateButtons(); }
        }

        // ------------------------------------------------------------------ page 5: summary
        void ShowSummary()
        {
            ShowPage(Page.Summary);
            _steps[4].State = _runOk ? ItemState.Done : ItemState.Error;
            _summary.Clear();
            bool ok = _runOk;
            SummaryBanner.Background = (System.Windows.Media.Brush)FindResource(ok ? "GoodSoft" : "BadSoft");
            SummaryIcon.Background = (System.Windows.Media.Brush)FindResource(ok ? "Good" : "Bad");
            SummaryGlyph.Text = ok ? "✓" : "✕";
            SummaryTitle.Text = _afterRollback ? "Geri alma tamamlandı" : ok ? "Hermes hazır" : "Kurulum tamamlanamadı";
            SummaryLead.Text = ok ? "Yeni bir komut satırı açıp `hermes` yazabilir ya da aşağıdan doğrudan açabilirsiniz." : (_runError ?? "") + "  Kayıt dosyasını bu mesajla birlikte iletebilirsiniz.";
            _summary.Add(new KeyValue("Hermes sürümü", _versionAfter ?? (_installedNow ?? _installedBefore)?.Display ?? "?"));
            _summary.Add(new KeyValue("Önceki sürüm", _installedBefore?.Display ?? "?"));
            if (_bundle != null && SkipInstallCheck.IsChecked != true) _summary.Add(new KeyValue("Paket", _bundle.Release + " · " + (_bundle.ExtractedRoot ?? _bundle.SourcePath)));
            _summary.Add(new KeyValue("Şirket sertifikası", _certSummary));
            _summary.Add(new KeyValue("Model", _modelSummary));
            _summary.Add(new KeyValue("Ayarlar ve oturumlar", _paths.HermesHome + " (silinmedi)"));
            if (_backupPath != null) _summary.Add(new KeyValue("Yedek", _backupPath));
            _summary.Add(new KeyValue("Kayıt dosyası", _log.FilePath));
            bool hasHermes = File.Exists(_paths.HermesExe);
            OpenDesktopBtn.IsEnabled = File.Exists(_paths.DesktopExe) || File.Exists(_paths.StartDesktopBat);
            OpenDashboardBtn.IsEnabled = hasHermes; OpenChatBtn.IsEnabled = hasHermes;
            RollbackCard.Visibility = _installRan && _bundle?.ExtractedRoot != null ? Visibility.Visible : Visibility.Collapsed;
            _log.Info("Özet: " + string.Join(" | ", _summary.Select(k => k.Key + ": " + k.Value)));
        }

        void OpenDesktop_Click(object sender, RoutedEventArgs e) => Try(() => HermesCommands.OpenDesktop(_paths, _env));
        void OpenDashboard_Click(object sender, RoutedEventArgs e) => Try(() => HermesCommands.OpenConsole(_paths, _env, "dashboard", "Hermes dashboard"));
        void OpenChat_Click(object sender, RoutedEventArgs e) => Try(() => HermesCommands.OpenConsole(_paths, _env, "chat", "Hermes chat"));
        void OpenLogFile_Click(object sender, RoutedEventArgs e) => Try(() => Process.Start("notepad.exe", ProcessRunner.Quote(_log.FilePath)));
        void OpenLogFolder_Click(object sender, RoutedEventArgs e) => Try(() => Process.Start("explorer.exe", ProcessRunner.Quote(Path.GetDirectoryName(_log.FilePath))));

        void Try(Action a)
        {
            try { a(); } catch (Exception ex) { _log.Warn(ex.Message); MessageBox.Show(ex.Message, Title, MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        async void Rollback_Click(object sender, RoutedEventArgs e)
        {
            if (MessageBox.Show("Son kurulum/güncelleme geri alınsın mı?\n\nÖnceki Hermes sürümü, config.yaml/.env (güncelleme öncesi hâli), PATH ve kısayollar geri yüklenir. Oturumlar, beceriler ve hafıza silinmez.",
                                Title, MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
            var running = HermesCommands.RunningHermes(_paths);
            if (running.Count > 0) { MessageBox.Show("Önce Hermes'i kapatın: " + string.Join(", ", running), Title, MessageBoxButton.OK, MessageBoxImage.Warning); return; }
            ShowPage(Page.Run);
            _tasks.Clear(); RunErrorPanel.Visibility = Visibility.Collapsed;
            RunTitle.Text = "Geri alma"; RunLead.Text = "Önceki kurulum geri yükleniyor…";
            var t = AddTask("rollback", "Son güncelleme geri alınıyor", 1);
            _busy = true; UpdateButtons(); _ticker.Start();
            try
            {
                Begin(t);
                await RunInstallerAsync(t, "Rollback", _cts.Token);
                _installedNow = _paths.DetectInstalled();
                _versionAfter = await HermesCommands.VersionAsync(_paths, _env, m => _log.Warn(m), _cts.Token);
                RunLead.Text = "Geri alma tamamlandı. Şu anki sürüm: " + (_versionAfter ?? _installedNow.Display);
                ChipInstalled.Text = _installedNow.Display;
                _modelSummary = "Güncelleme öncesi config.yaml/.env geri yüklendi";
                _installRan = false; _backupPath = null;
                _afterRollback = true; _runOk = true;
                Finish(t, ItemState.Done, "Geri alma tamamlandı · " + (_versionAfter ?? _installedNow.Display));
            }
            catch (StepException sx) { Fail(sx.Task, sx.Message); }
            catch (Exception ex) { Fail(t, ex.Message); }
            finally { _busy = false; _ticker.Stop(); UpdateButtons(); }
        }
    }
}
