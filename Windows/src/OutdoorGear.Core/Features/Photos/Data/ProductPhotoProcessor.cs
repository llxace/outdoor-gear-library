using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using SkiaSharp;

namespace OutdoorGear.Core.Features.Photos.Data;

/// <summary>Local, offline equivalent of the 0.20.4 product photo pipeline.</summary>
public sealed class ProductPhotoProcessor
{
    private const int CanvasSize = 1024;
    private const int MaxObjectEdge = 840;
    private const int MaxInputPixels = 60_000_000;
    private static readonly object SessionLock = new();
    private static InferenceSession? cachedSession;
    private static string? cachedModelPath;

    public void Process(string sourcePath, string destinationPath, string modelPath, bool whiteBackground, bool softShadow)
    {
        ValidatePaths(sourcePath, destinationPath);
        var destinationFullPath = Path.GetFullPath(destinationPath);
        Directory.CreateDirectory(Path.GetDirectoryName(destinationFullPath)!);
        var outputCreated = false;
        try
        {
            using var subject = PrepareSubject(sourcePath, modelPath, whiteBackground);
            SaveNormalized(subject, destinationFullPath, softShadow, out outputCreated);
        }
        catch
        {
            if (outputCreated && File.Exists(destinationFullPath))
                File.Delete(destinationFullPath);
            throw;
        }
    }

    private static void ValidatePaths(string sourcePath, string destinationPath)
    {
        if (!File.Exists(sourcePath))
            throw new FileNotFoundException("找不到原始照片。", sourcePath);
        var source = Path.GetFullPath(sourcePath);
        var destination = Path.GetFullPath(destinationPath);
        var comparison = OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;
        if (string.Equals(source, destination, comparison))
            throw new InvalidOperationException("处理结果不能覆盖原始照片。");
    }

    private static SKBitmap PrepareSubject(string sourcePath, string modelPath, bool whiteBackground)
    {
        using var decoded = SKBitmap.Decode(sourcePath)
            ?? throw new InvalidDataException("无法读取此图片格式。");
        if ((long)decoded.Width * decoded.Height > MaxInputPixels)
            throw new InvalidDataException("图片尺寸过大，无法安全处理。");
        using var bounded = ResizeToLimit(decoded, 3000);
        using var rgba = ToRgba(bounded);
        if (whiteBackground)
        {
            EnsureModelExists(modelPath);
            return ApplySegmentation(rgba, modelPath);
        }
        var subject = rgba.Copy()
            ?? throw new InvalidDataException("无法复制图片。");
        if (IsFullyOpaque(subject) && HasWhiteBorder(subject))
            RemoveConnectedWhiteBackground(subject);
        return subject;
    }

    private static void EnsureModelExists(string modelPath)
    {
        if (!File.Exists(modelPath))
            throw new FileNotFoundException("未找到本地白底处理模型。", modelPath);
    }

    private static void SaveNormalized(
        SKBitmap subject,
        string destinationPath,
        bool shadow,
        out bool outputCreated)
    {
        outputCreated = false;
        using var normalized = Normalize(subject, shadow);
        using var image = SKImage.FromBitmap(normalized);
        using var data = image.Encode(SKEncodedImageFormat.Png, 100);
        using var output = new FileStream(
            destinationPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None);
        outputCreated = true;
        data.SaveTo(output);
    }

    private static SKBitmap ApplySegmentation(SKBitmap source, string modelPath)
    {
        var mask = RunModel(CreateModelInput(source), modelPath);
        using var maskBitmap = CreateMaskBitmap(mask);
        using var scaledMask = ScaleMask(maskBitmap, source.Width, source.Height);
        return ApplyMask(source, scaledMask);
    }

    private static DenseTensor<float> CreateModelInput(SKBitmap source)
    {
        using var small = source.Resize(
            new SKImageInfo(320, 320, SKColorType.Rgba8888), Sampling)
            ?? throw new InvalidDataException("无法缩放照片用于抠图。");
        var tensor = new DenseTensor<float>(new[] { 1, 3, 320, 320 });
        var pixels = small.GetPixelSpan();
        FillTensorChannels(tensor, pixels);
        return tensor;
    }

    private static readonly SKSamplingOptions Sampling =
        new(SKFilterMode.Linear, SKMipmapMode.None);

    private static void FillTensorChannels(DenseTensor<float> tensor, Span<byte> pixels)
    {
        var means = new[] { .485f, .456f, .406f };
        var deviations = new[] { .229f, .224f, .225f };
        for (var pixel = 0; pixel < 320 * 320; pixel++)
        {
            var offset = pixel * 4;
            var red = pixels[offset] / 255f;
            var green = pixels[offset + 1] / 255f;
            var blue = pixels[offset + 2] / 255f;
            var maximum = Math.Max(Math.Max(red, green), Math.Max(blue, 1e-6f));
            var x = pixel % 320;
            var y = pixel / 320;
            tensor[0, 0, y, x] = (red / maximum - means[0]) / deviations[0];
            tensor[0, 1, y, x] = (green / maximum - means[1]) / deviations[1];
            tensor[0, 2, y, x] = (blue / maximum - means[2]) / deviations[2];
        }
    }

    private static float[] RunModel(DenseTensor<float> input, string modelPath)
    {
        lock (SessionLock)
        {
            var session = GetSession(modelPath);
            using var results = session.Run(
                new[] { NamedOnnxValue.CreateFromTensor("input.1", input) });
            return results.First().AsTensor<float>().ToArray();
        }
    }

    private static InferenceSession GetSession(string modelPath)
    {
        var fullPath = Path.GetFullPath(modelPath);
        if (cachedSession is not null && cachedModelPath == fullPath)
            return cachedSession;
        cachedSession?.Dispose();
        cachedSession = new InferenceSession(fullPath);
        cachedModelPath = fullPath;
        return cachedSession;
    }

    private static SKBitmap CreateMaskBitmap(float[] values)
    {
        var minimum = values.Min();
        var maximum = values.Max();
        if (!float.IsFinite(minimum) || !float.IsFinite(maximum) || maximum - minimum < 1e-7f)
            throw new InvalidDataException("抠图模型没有生成有效遮罩。");
        var result = new SKBitmap(
            new SKImageInfo(320, 320, SKColorType.Alpha8, SKAlphaType.Unpremul));
        var pixels = result.GetPixelSpan();
        var length = Math.Min(values.Length, pixels.Length);
        for (var index = 0; index < length; index++)
        {
            var normalized = (values[index] - minimum) / (maximum - minimum);
            pixels[index] = (byte)Math.Clamp(normalized * 255f, 0f, 255f);
        }
        return result;
    }

    private static SKBitmap ScaleMask(SKBitmap mask, int width, int height) =>
        mask.Resize(
            new SKImageInfo(width, height, SKColorType.Alpha8, SKAlphaType.Unpremul), Sampling)
        ?? throw new InvalidDataException("无法缩放抠图遮罩。");

    private static SKBitmap ApplyMask(SKBitmap source, SKBitmap mask)
    {
        var result = source.Copy()
            ?? throw new InvalidDataException("无法复制抠图结果。");
        var imagePixels = result.GetPixelSpan();
        var maskPixels = mask.GetPixelSpan();
        for (var index = 0; index < maskPixels.Length; index++)
            imagePixels[index * 4 + 3] = maskPixels[index];
        if (FindBounds(result, 32) is not null)
            return result;
        result.Dispose();
        throw new InvalidDataException("没有识别到照片中的主体，请关闭白底抠图后重试。");
    }

    private static SKBitmap Normalize(SKBitmap source, bool shadow)
    {
        var bounds = FindBounds(source, 32) ?? new SKRectI(0, 0, source.Width, source.Height);
        var padding = (int)Math.Ceiling(Math.Max(bounds.Width, bounds.Height) * .10);
        var left = Math.Max(0, bounds.Left - padding); var top = Math.Max(0, bounds.Top - padding);
        var right = Math.Min(source.Width, bounds.Right + padding); var bottom = Math.Min(source.Height, bounds.Bottom + padding);
        var cropRect = new SKRectI(left, top, right, bottom);
        using var cropped = new SKBitmap(new SKImageInfo(cropRect.Width, cropRect.Height, SKColorType.Rgba8888, SKAlphaType.Unpremul));
        using (var canvas = new SKCanvas(cropped)) canvas.DrawBitmap(source, cropRect, new SKRect(0, 0, cropRect.Width, cropRect.Height), new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.None));
        var scale = (float)MaxObjectEdge / Math.Max(bounds.Width, bounds.Height);
        var targetW = Math.Max(1, (int)Math.Round(cropped.Width * scale)); var targetH = Math.Max(1, (int)Math.Round(cropped.Height * scale));
        using var scaled = cropped.Resize(new SKImageInfo(targetW, targetH, SKColorType.Rgba8888, SKAlphaType.Unpremul), new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.None))
            ?? throw new InvalidDataException("无法规格化照片。");
        var output = new SKBitmap(new SKImageInfo(CanvasSize, CanvasSize, SKColorType.Rgba8888, SKAlphaType.Premul));
        using (var canvas = new SKCanvas(output))
        {
            canvas.Clear(SKColors.White);
            var x = (CanvasSize - targetW) / 2f; var y = (CanvasSize - targetH) / 2f;
            if (shadow)
            {
                using var paint = new SKPaint { Color = new SKColor(40, 40, 40, 38), IsAntialias = true, MaskFilter = SKMaskFilter.CreateBlur(SKBlurStyle.Normal, 18) };
                canvas.DrawOval(new SKRect(x + targetW * .08f, y + targetH * .91f, x + targetW * .92f, y + targetH * .99f), paint);
            }
            canvas.DrawBitmap(scaled, new SKRect(x, y, x + targetW, y + targetH), new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.None));
        }
        return output;
    }

    private static SKBitmap ResizeToLimit(SKBitmap bitmap, int edge)
    {
        var ratio = Math.Min(1f, (float)edge / Math.Max(bitmap.Width, bitmap.Height));
        return bitmap.Resize(new SKImageInfo(Math.Max(1, (int)(bitmap.Width * ratio)), Math.Max(1, (int)(bitmap.Height * ratio)), SKColorType.Rgba8888), new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.None))
            ?? throw new InvalidDataException("无法缩放图片。");
    }

    private static SKBitmap ToRgba(SKBitmap source)
    {
        var result = new SKBitmap(new SKImageInfo(source.Width, source.Height, SKColorType.Rgba8888, SKAlphaType.Premul));
        using var canvas = new SKCanvas(result);
        canvas.DrawBitmap(source, new SKRect(0, 0, source.Width, source.Height), new SKSamplingOptions(SKFilterMode.Linear, SKMipmapMode.None));
        return result;
    }

    private static bool IsFullyOpaque(SKBitmap bitmap)
    {
        var pixels = bitmap.GetPixelSpan();
        for (var index = 3; index < pixels.Length; index += 4) if (pixels[index] != 255) return false;
        return true;
    }

    private static SKRectI? FindBounds(SKBitmap bitmap, byte threshold)
    {
        var pixels = bitmap.GetPixelSpan(); var minX = bitmap.Width; var minY = bitmap.Height; var maxX = -1; var maxY = -1;
        for (var y = 0; y < bitmap.Height; y++) for (var x = 0; x < bitmap.Width; x++) if (pixels[(y * bitmap.Width + x) * 4 + 3] > threshold)
        { minX = Math.Min(minX, x); minY = Math.Min(minY, y); maxX = Math.Max(maxX, x); maxY = Math.Max(maxY, y); }
        return maxX < minX ? null : new SKRectI(minX, minY, maxX + 1, maxY + 1);
    }

    private static bool HasWhiteBorder(SKBitmap bitmap)
    {
        var hits = 0; var total = 0; var pixels = bitmap.GetPixelSpan().ToArray();
        for (var x = 0; x < bitmap.Width; x++) { Count(x); Count((bitmap.Height - 1) * bitmap.Width + x); }
        for (var y = 1; y < bitmap.Height - 1; y++) { Count(y * bitmap.Width); Count(y * bitmap.Width + bitmap.Width - 1); }
        return total > 0 && (double)hits / total > .92;
        void Count(int index) { total++; var offset = index * 4; if (Math.Min(pixels[offset], Math.Min(pixels[offset + 1], pixels[offset + 2])) > 240) hits++; }
    }

    private static void RemoveConnectedWhiteBackground(SKBitmap bitmap)
    {
        var pixels = bitmap.GetPixelSpan().ToArray(); var visited = new bool[checked(bitmap.Width * bitmap.Height)]; var stack = new Stack<int>();
        for (var x = 0; x < bitmap.Width; x++) { Add(x); Add((bitmap.Height - 1) * bitmap.Width + x); }
        for (var y = 1; y < bitmap.Height - 1; y++) { Add(y * bitmap.Width); Add(y * bitmap.Width + bitmap.Width - 1); }
        while (stack.Count > 0)
        {
            var index = stack.Pop(); var offset = index * 4; pixels[offset + 3] = 0;
            var x = index % bitmap.Width; var y = index / bitmap.Width;
            if (x > 0) Add(index - 1); if (x + 1 < bitmap.Width) Add(index + 1);
            if (y > 0) Add(index - bitmap.Width); if (y + 1 < bitmap.Height) Add(index + bitmap.Width);
        }
        void Add(int index)
        {
            if (visited[index]) return;
            var offset = index * 4;
            if (Math.Min(pixels[offset], Math.Min(pixels[offset + 1], pixels[offset + 2])) < 242) return;
            visited[index] = true; stack.Push(index);
        }
        pixels.AsSpan().CopyTo(bitmap.GetPixelSpan());
    }
}
