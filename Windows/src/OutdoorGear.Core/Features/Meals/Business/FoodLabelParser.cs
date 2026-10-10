using System.Globalization;
using System.Text.RegularExpressions;
using OutdoorGear.Core.Features.Meals.Domain;

namespace OutdoorGear.Core.Features.Meals.Business;

public static partial class FoodLabelParser
{
    public static FoodLabelResult Parse(string text)
    {
        var name = Capture(text, @"(?:品名|产品名称|食品名称|名称)\s*[:：]?\s*([^\r\n]+)")?.Trim() ?? "";
        var grams = ParseGrams(text);
        var calories = ParseCalories(text, grams, out var message);
        if (message.Length == 0) message = "未能完整识别营养信息，请核对文字并手动补齐。";
        return new FoodLabelResult(name, grams, calories, message);
    }

    private static double? ParseGrams(string text)
    {
        var match = Regex.Match(text, @"(?:净含量|净重|net\s*weight)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(kg|千克|g|克)", RegexOptions.IgnoreCase);
        if (!match.Success || !TryNumber(match.Groups[1].Value, out var value)) return null;
        return value * (match.Groups[2].Value.Equals("kg", StringComparison.OrdinalIgnoreCase) || match.Groups[2].Value == "千克" ? 1000 : 1);
    }

    private static double? ParseCalories(string text, double? grams, out string message)
    {
        message = "";
        var match = Regex.Match(text, @"(?:能量|热量|energy|calories)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(kcal|千卡|大卡|kj|千焦)", RegexOptions.IgnoreCase);
        if (!match.Success || !TryNumber(match.Groups[1].Value, out var value)) return null;
        var kcal = match.Groups[2].Value.Equals("kj", StringComparison.OrdinalIgnoreCase) || match.Groups[2].Value == "千焦" ? value / 4.184 : value;
        if (Regex.IsMatch(text, @"(每\s*100\s*(?:g|克)|per\s*100\s*g)", RegexOptions.IgnoreCase) && grams is { } mass)
        {
            message = "能量按每 100 g 换算为整包；净重不含包装，请补齐包装重量并核对每包是否算一份。";
            return kcal * mass / 100;
        }
        if (Regex.IsMatch(text, @"(每份|per\s*serving)", RegexOptions.IgnoreCase))
        {
            message = "识别为每份能量；净含量可能是整包重量，请核对一份对应的重量。";
            return kcal;
        }
        message = "检测到能量值，但无法确认是每份还是每 100 g，暂不自动填入热量。";
        return null;
    }

    private static string? Capture(string text, string pattern)
    {
        var match = Regex.Match(text, pattern, RegexOptions.IgnoreCase);
        return match.Success ? match.Groups[1].Value : null;
    }

    private static bool TryNumber(string value, out double number) => double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out number);
}
