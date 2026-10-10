using System.Configuration;
using System.Data;
using System.Windows;
using System.Windows.Media;

namespace OutdoorGear.Wpf;

/// <summary>
/// Interaction logic for App.xaml
/// </summary>
public partial class App : Application
{
    private static readonly (string Key, string Light, string Dark)[] AppearanceBrushes =
    [
        ("WindowBrush", "#F4F6F5", "#1E2424"), ("SidebarBrush", "#E9EEEC", "#171C1D"),
        ("SurfaceBrush", "#FFFFFF", "#252C2B"), ("SurfaceAltBrush", "#E4EAE7", "#2C3432"),
        ("LineBrush", "#CAD4D0", "#3C4644"), ("TextBrush", "#1E2824", "#EDF1EF"),
        ("MutedBrush", "#5F6F68", "#9BA6A3"), ("AccentBrush", "#28795D", "#8FCBB8"),
        ("BlueBrush", "#0878CC", "#2498F5"), ("InputBrush", "#FFFFFF", "#1C2221"),
        ("GridBrush", "#FFFFFF", "#202625"), ("GridAlternateBrush", "#F2F5F3", "#242B29"),
        ("GridHeaderBrush", "#E9EEEC", "#252D2B"), ("ButtonHoverBrush", "#D8E2DE", "#37413E"),
        ("SelectionBrush", "#DCEBE3", "#3B4442"), ("HoverBrush", "#EDF2F0", "#303936"),
        ("ForecastCardBrush", "#F1F5F3", "#1D2322"), ("DashboardTrackBrush", "#DEE6E2", "#303835")
    ];

    public void ApplyAppearance(string appearance)
    {
        var light = appearance == "浅色" || appearance == "跟随系统" && IsSystemLight();
        foreach (var (key, lightColor, darkColor) in AppearanceBrushes)
            Resources[key] = Brush(light ? lightColor : darkColor);
    }

    private static SolidColorBrush Brush(string value) => new((Color)ColorConverter.ConvertFromString(value));
    private static bool IsSystemLight()
    {
        try { return Microsoft.Win32.Registry.CurrentUser.OpenSubKey("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize")?.GetValue("AppsUseLightTheme") is int value && value == 1; }
        catch { return false; }
    }
}
