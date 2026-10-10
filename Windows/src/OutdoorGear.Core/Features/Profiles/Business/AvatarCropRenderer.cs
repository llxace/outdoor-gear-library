using SkiaSharp;

namespace OutdoorGear.Core.Features.Profiles.Business;

public static class AvatarCropRenderer
{
    private const int OutputSize = 512;
    private const double ViewportSize = 320;
    private const long MaxInputPixels = 60_000_000;

    public static void Render(string sourcePath, string destinationPath, double zoom, double offsetX, double offsetY)
    {
        ValidatePaths(sourcePath, destinationPath, zoom, offsetX, offsetY);
        using var source = SKBitmap.Decode(sourcePath) ?? throw new InvalidDataException("无法读取所选头像图片。");
        ValidateImage(source);
        using var output = RenderSquare(source, zoom, offsetX, offsetY);
        SavePng(output, destinationPath);
    }

    private static void ValidatePaths(string sourcePath, string destinationPath, double zoom, double offsetX, double offsetY)
    {
        if (!File.Exists(sourcePath)) throw new FileNotFoundException("找不到原始头像图片。", sourcePath);
        if (string.Equals(Path.GetFullPath(sourcePath), Path.GetFullPath(destinationPath), OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
            throw new InvalidOperationException("头像裁剪结果不能覆盖原始图片。");
        if (!double.IsFinite(zoom) || zoom is < 1 or > 5 || !double.IsFinite(offsetX) || !double.IsFinite(offsetY))
            throw new ArgumentOutOfRangeException(nameof(zoom), "头像裁剪参数无效。");
    }

    private static void ValidateImage(SKBitmap image)
    {
        if (image.Width < 1 || image.Height < 1 || (long)image.Width * image.Height > MaxInputPixels)
            throw new InvalidDataException("头像图片尺寸无效或过大。");
    }

    private static SKBitmap RenderSquare(SKBitmap source, double zoom, double offsetX, double offsetY)
    {
        var scale = Math.Max(ViewportSize / source.Width, ViewportSize / source.Height) * zoom;
        var (x, y) = ClampOffset(source, scale, offsetX, offsetY);
        var factor = OutputSize / ViewportSize;
        var width = source.Width * (float)scale * (float)factor; var height = source.Height * (float)scale * (float)factor;
        var left = (OutputSize - width) / 2 + (float)x * (float)factor; var top = (OutputSize - height) / 2 + (float)y * (float)factor;
        var target = new SKRect(left, top, left + width, top + height);
        var result = new SKBitmap(OutputSize, OutputSize, SKColorType.Rgba8888, SKAlphaType.Unpremul);
        using var canvas = new SKCanvas(result);
        canvas.Clear(SKColors.Transparent);
        canvas.DrawBitmap(source, target, new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.Linear));
        canvas.Flush();
        return result;
    }

    private static (double X, double Y) ClampOffset(SKBitmap source, double scale, double x, double y)
    {
        var maxX = Math.Max(0, (source.Width * scale - ViewportSize) / 2);
        var maxY = Math.Max(0, (source.Height * scale - ViewportSize) / 2);
        return (Math.Clamp(x, -maxX, maxX), Math.Clamp(y, -maxY, maxY));
    }

    private static void SavePng(SKBitmap image, string destinationPath)
    {
        var directory = Path.GetDirectoryName(Path.GetFullPath(destinationPath))!;
        Directory.CreateDirectory(directory);
        using var encoded = image.Encode(SKEncodedImageFormat.Png, 100) ?? throw new InvalidDataException("无法生成头像 PNG。");
        using var output = new FileStream(destinationPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        encoded.SaveTo(output);
    }
}
