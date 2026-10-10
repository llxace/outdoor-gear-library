using System.Text.Json.Serialization;

namespace OutdoorGear.Core.Features.Settings.Domain;

public sealed record ExchangeRate(
    [property: JsonPropertyName("date")] string Date,
    [property: JsonPropertyName("base")] string Base,
    [property: JsonPropertyName("quote")] string Quote,
    [property: JsonPropertyName("rate")] double Rate);
