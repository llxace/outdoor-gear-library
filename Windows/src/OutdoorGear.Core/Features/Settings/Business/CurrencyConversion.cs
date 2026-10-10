using System.Globalization;
using OutdoorGear.Core.Features.Settings.Domain;

namespace OutdoorGear.Core.Features.Settings.Business;

public static class CurrencyConversion
{
    public static string DisplayCurrency(
        string preference,
        IReadOnlyDictionary<string, ExchangeRate> rates) =>
        preference == "CNY" || rates.ContainsKey(preference) ? preference : "CNY";

    public static double ConvertYuan(
        double yuan,
        string currency,
        IReadOnlyDictionary<string, ExchangeRate> rates) =>
        yuan * (currency == "CNY" ? 1 : rates.GetValueOrDefault(currency)?.Rate ?? 1);

    public static string FormatMoney(
        double yuan,
        string preference,
        IReadOnlyDictionary<string, ExchangeRate> rates)
    {
        var currency = DisplayCurrency(preference, rates);
        var amount = ConvertYuan(yuan, currency, rates);
        return amount.ToString("C", CultureInfo.GetCultureInfo(CultureFor(currency)));
    }

    public static string Describe(
        string preference,
        IReadOnlyDictionary<string, ExchangeRate> rates,
        bool loading,
        bool offline)
    {
        if (preference == "CNY")
            return "金额以人民币保存；切换货币后按每日参考汇率显示。";
        if (!rates.TryGetValue(preference, out var rate))
            return loading ? "正在获取汇率，暂以人民币显示…" : "汇率不可用，暂以人民币显示。";
        var note = offline ? " · 离线缓存" : "";
        return $"1 CNY = {rate.Rate.ToString("0.######", CultureInfo.InvariantCulture)} {preference} · 汇率日期 {rate.Date} · Frankfurter{note}";
    }

    private static string CultureFor(string currency) => currency switch
    {
        "USD" => "en-US",
        "EUR" => "de-DE",
        "GBP" => "en-GB",
        "JPY" => "ja-JP",
        "HKD" => "zh-HK",
        "TWD" => "zh-TW",
        _ => "zh-CN"
    };
}
