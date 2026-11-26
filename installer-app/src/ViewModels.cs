using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using HermesKurulum.Core;

namespace HermesKurulum
{
    public enum ItemState { Pending, Active, Done, Error, Skipped, Warning }

    public abstract class Notifier : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler PropertyChanged;
        protected void Raise([CallerMemberName] string name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        protected void RaiseAll() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(string.Empty));
        protected static Brush B(string hex) { var b = (SolidColorBrush)new BrushConverter().ConvertFromString(hex); b.Freeze(); return b; }
    }

    /// <summary>Sidebar step.</summary>
    public sealed class StepVm : Notifier
    {
        ItemState _state; string _subtitle;
        public int Number { get; set; }
        public string Title { get; set; }
        public string Subtitle { get => _subtitle; set { _subtitle = value; Raise(); } }
        public ItemState State { get => _state; set { _state = value; RaiseAll(); } }
        public bool Current { get; private set; }
        public void SetCurrent(bool c) { Current = c; RaiseAll(); }

        public string Glyph => State == ItemState.Done ? "✓" : State == ItemState.Error ? "✕" : State == ItemState.Skipped ? "–" : State == ItemState.Warning ? "!" : Number.ToString();
        public Brush CircleBrush => State == ItemState.Done ? B("#16A34A") : State == ItemState.Error ? B("#DC2626") : State == ItemState.Warning ? B("#D97706")
                                  : Current ? B("#2563EB") : B("#FFFFFF");
        public Brush CircleBorder => State == ItemState.Done ? B("#16A34A") : State == ItemState.Error ? B("#DC2626") : State == ItemState.Warning ? B("#D97706")
                                   : Current ? B("#2563EB") : B("#CBD5E1");
        public Brush GlyphBrush => (State == ItemState.Pending || State == ItemState.Skipped) && !Current ? B("#64748B") : B("#FFFFFF");
        public Brush RowBrush => Current ? B("#EFF6FF") : Brushes.Transparent;
        public Brush TitleBrush => State == ItemState.Skipped && !Current ? B("#94A3B8") : B("#0F172A");
        public FontWeight TitleWeight => Current ? FontWeights.SemiBold : FontWeights.Normal;
    }

    /// <summary>Row in the live progress list.</summary>
    public sealed class TaskVm : Notifier
    {
        ItemState _state; string _detail; DateTime? _start; TimeSpan? _took;
        public string Key { get; set; }
        public string Title { get; set; }
        public double Weight { get; set; } = 1;
        public double Fraction { get; set; }
        public string Detail { get => _detail; set { _detail = value; Raise(); } }
        public ItemState State
        {
            get => _state;
            set
            {
                if (value == ItemState.Active && _start == null) _start = DateTime.Now;
                if ((value == ItemState.Done || value == ItemState.Error || value == ItemState.Warning) && _start != null) _took = DateTime.Now - _start.Value;
                if (value == ItemState.Done || value == ItemState.Skipped || value == ItemState.Warning) Fraction = 1;
                _state = value; RaiseAll();
            }
        }
        public string Duration => _took.HasValue ? (_took.Value.TotalMinutes >= 1 ? $"{(int)_took.Value.TotalMinutes} dk {_took.Value.Seconds} sn" : $"{_took.Value.Seconds} sn") : State == ItemState.Active ? "sürüyor…" : "";
        public string Glyph => State == ItemState.Done ? "✓" : State == ItemState.Error ? "✕" : State == ItemState.Active ? "●" : State == ItemState.Skipped ? "–" : State == ItemState.Warning ? "!" : "";
        public Brush CircleBrush => State == ItemState.Done ? B("#16A34A") : State == ItemState.Error ? B("#DC2626") : State == ItemState.Active ? B("#2563EB")
                                  : State == ItemState.Warning ? B("#D97706") : B("#CBD5E1");
        public Brush TitleBrush => State == ItemState.Pending || State == ItemState.Skipped ? B("#94A3B8") : B("#0F172A");
        public void Tick() => Raise(nameof(Duration));
    }

    public sealed class CertVm
    {
        public CertVm(CertInfo c)
        {
            Subject = c.Subject; Issuer = c.Issuer; Kind = c.Kind; Fingerprint = c.Sha256Fingerprint;
            Validity = c.Cert.NotBefore.ToString("dd.MM.yyyy") + " – " + c.Cert.NotAfter.ToString("dd.MM.yyyy");
        }
        public string Subject { get; } public string Issuer { get; } public string Kind { get; } public string Validity { get; } public string Fingerprint { get; }
    }

    public sealed class KeyValue
    {
        public KeyValue(string k, string v) { Key = k; Value = v; }
        public string Key { get; } public string Value { get; }
    }
}
