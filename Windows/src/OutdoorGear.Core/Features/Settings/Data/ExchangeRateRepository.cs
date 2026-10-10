using System.Net.Http.Headers;
using System.Text.Json;
using OutdoorGear.Core.Features.Settings.Domain;

namespace OutdoorGear.Core.Features.Settings.Data;

public sealed class ExchangeRateRepository(string userDataDirectory)
{
    private static readonly HttpClient Client = CreateClient();
    private static readonly string[] SupportedQuotes = ["USD", "EUR", "GBP", "JPY", "HKD", "TWD"];
    private readonly string cachePath = Path.Combine(userDataDirectory, "exchange-rates.json");

    public IReadOnlyDictionary<string, ExchangeRate> ReadCachedRates()
    {
        if (!File.Exists(cachePath))
            return new Dictionary<string, ExchangeRate>();
        try
        {
            var rows = JsonSerializer.Deserialize<List<ExchangeRate>>(File.ReadAllBytes(cachePath));
            return IndexValidRows(rows ?? []);
        }
        catch (JsonException)
        {
            return new Dictionary<string, ExchangeRate>();
        }
        catch (IOException)
        {
            return new Dictionary<string, ExchangeRate>();
        }
    }

    public async Task<IReadOnlyDictionary<string, ExchangeRate>> FetchAndSaveAsync(
        CancellationToken cancellationToken = default)
    {
        using var response = await Client.GetAsync(RequestUri, cancellationToken);
        response.EnsureSuccessStatusCode();
        var bytes = await response.Content.ReadAsByteArrayAsync(cancellationToken);
        var rows = JsonSerializer.Deserialize<List<ExchangeRate>>(bytes)
            ?? throw new InvalidDataException("汇率数据格式无效。");
        var rates = IndexValidRows(rows);
        if (rates.Count == 0)
            throw new InvalidDataException("汇率服务没有返回可用数据。");
        SaveCache(bytes);
        return rates;
    }

    private static Uri RequestUri => new(
        "https://api.frankfurter.dev/v2/rates?base=CNY&quotes=" +
        string.Join(',', SupportedQuotes));

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        client.DefaultRequestHeaders.UserAgent.Add(
            new ProductInfoHeaderValue("OutdoorGearLibraryWindows", "0.20.4"));
        return client;
    }

    private static IReadOnlyDictionary<string, ExchangeRate> IndexValidRows(
        IEnumerable<ExchangeRate> rows) => rows
        .Where(IsValid)
        .GroupBy(row => row.Quote, StringComparer.OrdinalIgnoreCase)
        .ToDictionary(group => group.Key, group => group.OrderByDescending(row => row.Date).First(), StringComparer.OrdinalIgnoreCase);

    private static bool IsValid(ExchangeRate row) =>
        row.Base == "CNY" &&
        SupportedQuotes.Contains(row.Quote, StringComparer.Ordinal) &&
        double.IsFinite(row.Rate) && row.Rate > 0 &&
        DateOnly.TryParseExact(row.Date, "yyyy-MM-dd", out _);

    private void SaveCache(byte[] data)
    {
        var directory = Path.GetDirectoryName(cachePath)!;
        Directory.CreateDirectory(directory);
        var temporaryPath = Path.Combine(directory, $"exchange-rates-{Guid.NewGuid():N}.tmp");
        try
        {
            File.WriteAllBytes(temporaryPath, data);
            File.Move(temporaryPath, cachePath, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
                File.Delete(temporaryPath);
        }
    }
}
