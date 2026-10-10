using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media.Imaging;

namespace OutdoorGear.Wpf.Features.Equipment.Presentation;

internal sealed class GearPhotoPathConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not string path || string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            return DependencyProperty.UnsetValue;
        try { return Load(path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or NotSupportedException or FormatException)
        {
            return DependencyProperty.UnsetValue;
        }
    }

    private static BitmapImage Load(string path)
    {
        using var stream = File.OpenRead(path);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.DecodePixelWidth = 96;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        return image;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
