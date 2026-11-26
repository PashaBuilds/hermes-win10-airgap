using System;
using System.Windows;
using System.Windows.Threading;

namespace HermesKurulum
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            DispatcherUnhandledException += (s, a) =>
            {
                MessageBox.Show("Beklenmeyen hata: " + a.Exception.Message + "\n\nAyrıntılar kayıt dosyasında.", "Hermes Kurulum Asistanı",
                                MessageBoxButton.OK, MessageBoxImage.Error);
                (MainWindow as MainWindow)?.LogUnhandled(a.Exception);
                a.Handled = true;
            };
            base.OnStartup(e);
        }
    }
}
