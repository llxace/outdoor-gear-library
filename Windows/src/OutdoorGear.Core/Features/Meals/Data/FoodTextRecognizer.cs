using TesseractOCR;
using TesseractOCR.Enums;
using TesseractOCR.Pix;

namespace OutdoorGear.Core.Features.Meals.Data;

public static class FoodTextRecognizer
{
    public static Task<string> RecognizeAsync(string imagePath, string dataDirectory, CancellationToken cancellationToken = default)
    {
        return Task.Run(() => Recognize(imagePath, dataDirectory), cancellationToken);
    }

    private static string Recognize(string imagePath, string dataDirectory)
    {
        using var engine = new Engine(dataDirectory, new List<Language> { Language.ChineseSimplified, Language.English }, EngineMode.Default);
        using var image = Image.LoadFromFile(imagePath);
        using var page = engine.Process(image);
        var text = page.Text.Trim();
        if (text.Length == 0) throw new InvalidDataException("没有识别到文字，请拍清晰的包装营养表。");
        return text;
    }
}
