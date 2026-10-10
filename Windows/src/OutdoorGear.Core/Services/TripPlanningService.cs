using System.Collections.Concurrent;
using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public sealed record RouteElevationSample(double DistanceMeters, double Latitude, double Longitude, double ElevationMeters);
public sealed record RouteElevationStats(double MinimumMeters, double MaximumMeters, double AverageMeters, double EstimatedAscentMeters, double EstimatedDescentMeters, double ProfileDistanceMeters, int ProfileSampleCount, double NoiseThresholdMeters, string Source, double SourceResolutionMeters, string Method);
public sealed record RouteSummary(long Id, string Name, string Area, TrailCoordinate Center, string Distance, IReadOnlyList<IReadOnlyList<TrailCoordinate>> Segments, string? ImportedFile = null, bool IsDestinationOnly = false, RouteElevationStats? ElevationStats = null, IReadOnlyList<RouteElevationSample>? ElevationProfile = null, int? SelectedSectionCount = null);
public sealed record WeatherNow(string Time, double Temperature, double FeelsLike, int Code);
public sealed record WeatherDay(string Id, int Code, double Low, double High, double RainChance, double Rain, double Wind);
public sealed record WeatherForecast(WeatherNow Departure, IReadOnlyList<WeatherDay> Days, double? Elevation, string Timezone);
public sealed record WeatherTrend(string Start, string End, bool Monthly, double Temperature, double TemperatureAnomaly, double PrecipitationAnomaly, double? Wind, double? CloudCover);
public sealed record SeasonalOutlook(IReadOnlyList<WeatherTrend> Weeks, IReadOnlyList<WeatherTrend> Months, string Timezone);
public sealed class ForecastRangeException : InvalidOperationException
{
    public ForecastRangeException(string message) : base(message) { }
}
public sealed record PlaceResult(string Name, TrailCoordinate Point);
public sealed record TerrainSummary(double Low, double High, double? Average, double? Ascent, double? Descent, string Source);

public sealed class TripPlanningService
{
    private static readonly HttpClient SharedClient = CreateClient();
    private static readonly ConcurrentDictionary<string, byte[]> Cache = new();
    private readonly HttpClient client;
    private readonly string? catalogPath;
    private const string RouteApi = "https://hiking.waymarkedtrails.org/api/v1";

    public TripPlanningService(string? domesticRouteCatalogPath = null, HttpClient? httpClient = null)
    {
        catalogPath = domesticRouteCatalogPath;
        client = httpClient ?? SharedClient;
    }

    public async Task<IReadOnlyList<PlaceResult>> SearchPlacesAsync(string query, CancellationToken cancellationToken = default)
    {
        var text = query.Trim(); if (text.Length == 0) return [];
        if (text == "五台山") text = "山西省忻州市五台山风景名胜区";
        var url = "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=8&q=" + Uri.EscapeDataString(text);
        var data = await RequestAsync(url, cancellationToken); var rows = JsonNode.Parse(data)?.AsArray() ?? new JsonArray();
        return rows.OfType<JsonObject>().Select(row =>
        {
            var lat = InventoryDocument.Number(row["lat"], double.NaN); var lon = InventoryDocument.Number(row["lon"], double.NaN);
            var name = row["display_name"]?.ToString() ?? ""; return new PlaceResult(name, new TrailCoordinate(lat, lon));
        }).Where(result => TrailFileReader.Valid(result.Point)).ToList();
    }

    public async Task<IReadOnlyList<RouteSummary>> SearchNamedRoutesAsync(string query, CancellationToken cancellationToken = default)
    {
        var needle = Normalize(query); if (needle.Length == 0) return [];
        var local = LoadDomestic().Where(route => Normalize(route.Name).Contains(needle, StringComparison.Ordinal)).ToList();
        try
        {
            var url = RouteApi + "/list/search?query=" + Uri.EscapeDataString(query.Trim()) + "&limit=50";
            var data = await RequestAsync(url, cancellationToken); var response = JsonNode.Parse(data)?["results"]?.AsArray() ?? new JsonArray();
            var online = response.OfType<JsonObject>().Select(node => new RouteSummary(InventoryDocument.Int64(node["id"]), node["name"]?.ToString() ?? node["ref"]?.ToString() ?? $"未命名徒步路线 #{node["id"]}", "按路线名称搜索", new TrailCoordinate(0, 0), "", [])).Where(route => Normalize(route.Name).Contains(needle, StringComparison.Ordinal)).ToList();
            return Merge(local, online);
        }
        catch (OperationCanceledException) { throw; }
        catch when (local.Count > 0) { return local; }
    }

    public async Task<IReadOnlyList<RouteSummary>> SearchNearbyRoutesAsync(PlaceResult place, int radiusKm, CancellationToken cancellationToken = default)
    {
        if (!TrailFileReader.Valid(place.Point) || radiusKm is < 1 or > 500) throw new ArgumentOutOfRangeException(nameof(radiusKm));
        var local = LoadDomestic().Where(route => DistanceMeters(route.Center, place.Point) <= radiusKm * 1000).ToList();
        var deltaLat = radiusKm / 111.32; var deltaLon = deltaLat / Math.Max(0.1, Math.Cos(Degrees(place.Point.Latitude)));
        var bounds = new[] { Project(place.Point.Longitude - deltaLon, place.Point.Latitude - deltaLat), Project(place.Point.Longitude + deltaLon, place.Point.Latitude + deltaLat) };
        var url = RouteApi + "/list/by_area?bbox=" + string.Join(',', bounds.SelectMany(pair => pair).Select(value => value.ToString("G", CultureInfo.InvariantCulture))) + "&limit=50";
        try
        {
            var data = await RequestAsync(url, cancellationToken); var response = JsonNode.Parse(data)?["results"]?.AsArray() ?? new JsonArray();
            var online = response.OfType<JsonObject>().Select(node => new RouteSummary(InventoryDocument.Int64(node["id"]), node["name"]?.ToString() ?? node["ref"]?.ToString() ?? $"未命名徒步路线 #{node["id"]}", place.Name, place.Point, "", [])).ToList();
            return Merge(local, online);
        }
        catch (OperationCanceledException) { throw; }
        catch when (local.Count > 0) { return local; }
    }

    public async Task<RouteSummary> LoadRouteAsync(RouteSummary summary, CancellationToken cancellationToken = default)
    {
        if (summary.ImportedFile is not null || summary.IsDestinationOnly || summary.Segments.Count > 0) return summary;
        var data = await RequestAsync($"{RouteApi}/details/relation/{summary.Id}", cancellationToken);
        var root = JsonNode.Parse(data) as JsonObject ?? throw new InvalidDataException("路线详情格式无效。");
        var bbox = root["bbox"]?.AsArray(); if (bbox?.Count != 4) throw new InvalidDataException("这条路线缺少位置信息。");
        var center = Unproject((InventoryDocument.Number(bbox[0]) + InventoryDocument.Number(bbox[2])) / 2, (InventoryDocument.Number(bbox[1]) + InventoryDocument.Number(bbox[3])) / 2);
        var length = InventoryDocument.Number(root["official_length"] ?? root["route"]?["length"], double.NaN);
        var distance = double.IsFinite(length) && length > 0 ? $"{length / 1000:0.0} km（{(root["official_length"] is null ? "地图估算" : "来源标注")}）" : "";
        var name = root["tags"]?["name:zh"]?.ToString() ?? root["name"]?.ToString() ?? summary.Name;
        var segments = ReadRouteSegments(root["route"]);
        if (segments.Sum(segment => segment.Count) > 50_000 || segments.SelectMany(s => s).Any(point => !TrailFileReader.Valid(point))) throw new InvalidDataException("这条路线的轨迹过大或无效，无法保存。");
        return summary with { Name = name, Center = center, Distance = distance, Segments = segments };
    }

    public static RouteSummary? ReadSelectedRoute(JsonNode? node)
    {
        if (node is not JsonObject route || route["center"] is not JsonObject center) return null;
        var id = InventoryDocument.Int64(route["id"]); var point = new TrailCoordinate(InventoryDocument.Number(center["lat"], double.NaN), InventoryDocument.Number(center["lon"], double.NaN));
        if (id <= 0 || !TrailFileReader.Valid(point)) return null;
        var segments = new List<IReadOnlyList<TrailCoordinate>>();
        if (route["segments"] is JsonArray parts) foreach (var part in parts.OfType<JsonArray>()) segments.Add(part.OfType<JsonObject>().Select(value => new TrailCoordinate(InventoryDocument.Number(value["lat"]), InventoryDocument.Number(value["lon"]), value["elevation"] is null ? null : InventoryDocument.Number(value["elevation"]))).ToList());
        return new RouteSummary(id, route["name"]?.ToString() ?? "", route["area"]?.ToString() ?? "", point, route["distance"]?.ToString() ?? "", segments, route["importedFile"]?.ToString(), InventoryDocument.Bool(route["destinationOnly"]), ReadElevationStats(route["elevationStats"]), ReadElevationProfile(route["elevationProfile"]), route["selectedSectionCount"] is null ? null : InventoryDocument.Int(route["selectedSectionCount"]));
    }

    public static JsonObject ToJson(RouteSummary route)
    {
        var segments = new JsonArray();
        foreach (var part in route.Segments)
        {
            var points = new JsonArray(); foreach (var point in part) points.Add(new JsonObject { ["lat"] = point.Latitude, ["lon"] = point.Longitude, ["elevation"] = point.Elevation }); segments.Add(points);
        }
        var result = new JsonObject { ["id"] = route.Id, ["name"] = route.Name, ["area"] = route.Area, ["center"] = new JsonObject { ["lat"] = route.Center.Latitude, ["lon"] = route.Center.Longitude }, ["distance"] = route.Distance, ["segments"] = segments };
        if (route.ImportedFile is not null) result["importedFile"] = route.ImportedFile;
        if (route.IsDestinationOnly) result["destinationOnly"] = true;
        if (route.ElevationStats is { } stats) result["elevationStats"] = StatsJson(stats);
        if (route.ElevationProfile is { } profile) result["elevationProfile"] = ProfileJson(profile);
        if (route.SelectedSectionCount is { } sections) result["selectedSectionCount"] = sections;
        return result;
    }

    public async Task<TerrainSummary?> TerrainAsync(RouteSummary route, CancellationToken cancellationToken = default)
    {
        if (RecordedTerrain(route) is { } recorded) return recorded;
        var points = route.Segments.SelectMany(segment => segment).ToList(); if (points.Count == 0) return null;
        var count = Math.Min(100, points.Count); var samples = Enumerable.Range(0, count).Select(index => points[index * (points.Count - 1) / Math.Max(1, count - 1)]).ToList();
        var lat = string.Join(',', samples.Select(point => point.Latitude.ToString("G", CultureInfo.InvariantCulture)));
        var lon = string.Join(',', samples.Select(point => point.Longitude.ToString("G", CultureInfo.InvariantCulture)));
        var url = $"https://api.open-meteo.com/v1/elevation?latitude={Uri.EscapeDataString(lat)}&longitude={Uri.EscapeDataString(lon)}";
        var data = JsonNode.Parse(await RequestAsync(url, cancellationToken))?["elevation"]?.AsArray() ?? throw new InvalidDataException("海拔数据不完整。");
        var heights = data.Select(node => InventoryDocument.Number(node, double.NaN)).ToList();
        if (heights.Count != samples.Count || heights.Any(value => !double.IsFinite(value))) throw new InvalidDataException("海拔数据不完整。");
        return new TerrainSummary(heights.Min(), heights.Max(), heights.Average(), null, null, "Open-Meteo / Copernicus DEM 90 m，沿线采样估算");
    }

    public static TerrainSummary? RecordedTerrain(RouteSummary route)
    {
        if (route.ElevationStats is { } stats) return new TerrainSummary(stats.MinimumMeters, stats.MaximumMeters, stats.AverageMeters, stats.EstimatedAscentMeters, stats.EstimatedDescentMeters, stats.Source);
        var segments = route.Segments;
        var points = segments.SelectMany(segment => segment).ToList();
        if (points.Count == 0 || points.Any(point => point.Elevation is null)) return null;
        var heights = points.Select(point => point.Elevation!.Value).ToList(); var ascent = 0d; var descent = 0d;
        foreach (var segment in segments)
            for (var index = 1; index < segment.Count; index++)
            {
                var change = segment[index].Elevation!.Value - segment[index - 1].Elevation!.Value;
                ascent += Math.Max(0, change); descent += Math.Max(0, -change);
            }
        return new TerrainSummary(heights.Min(), heights.Max(), heights.Average(), ascent, descent, "轨迹文件高程，累计升降未去噪");
    }

    public async Task<WeatherForecast> ForecastAsync(TrailCoordinate point, DateTimeOffset departure, CancellationToken cancellationToken = default)
    {
        if (!TrailFileReader.Valid(point)) throw new ArgumentException("路线中心坐标无效。");
        var url = "https://api.open-meteo.com/v1/forecast?latitude=" + point.Latitude.ToString("G", CultureInfo.InvariantCulture) + "&longitude=" + point.Longitude.ToString("G", CultureInfo.InvariantCulture) + "&hourly=temperature_2m,apparent_temperature,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max&timezone=auto&forecast_days=16&wind_speed_unit=kmh";
        var root = JsonNode.Parse(await RequestAsync(url, cancellationToken)) as JsonObject ?? throw new InvalidDataException("天气数据格式无效。");
        var zone = root["timezone"]?.ToString() ?? "UTC"; var daily = root["daily"] as JsonObject ?? throw new InvalidDataException("天气逐日数据缺失。");
        var hourly = root["hourly"] as JsonObject ?? throw new InvalidDataException("天气小时数据缺失。");
        var times = Strings(daily["time"]); var codes = Numbers(daily["weather_code"]); var lows = Numbers(daily["temperature_2m_min"]); var highs = Numbers(daily["temperature_2m_max"]); var chances = Numbers(daily["precipitation_probability_max"]); var rain = Numbers(daily["precipitation_sum"]); var winds = Numbers(daily["wind_speed_10m_max"]);
        var length = times.Count;
        if (length == 0 || new[] { codes.Count, lows.Count, highs.Count, chances.Count, rain.Count, winds.Count }.Any(count => count != length)) throw new InvalidDataException("天气数据不完整，请重新查询。");
        var days = new List<WeatherDay>();
        for (var index = 0; index < length; index++)
        {
            var values = new[] { codes[index], lows[index], highs[index], chances[index], rain[index], winds[index] };
            if (values.Any(value => value is null || !double.IsFinite(value.Value))) continue;
            days.Add(new WeatherDay(times[index], (int)codes[index]!.Value, lows[index]!.Value, highs[index]!.Value, chances[index]!.Value, rain[index]!.Value, winds[index]!.Value));
        }
        if (days.Count == 0) throw new InvalidDataException("天气数据不完整，请重新查询。");
        var timeZone = FindZone(zone); var localDeparture = TimeZoneInfo.ConvertTime(departure, timeZone).DateTime;
        var startDay = localDeparture.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        if (startDay.CompareTo(days[0].Id) < 0 || startDay.CompareTo(days[^1].Id) > 0) throw new ForecastRangeException($"所选出发日期不在当前预报范围（{days[0].Id} 至 {days[^1].Id}）内。远期可查看周／月趋势，临近出发时再查询逐日天气。");
        var hourlyTimes = Strings(hourly["time"]); var at = hourlyTimes.IndexOf(localDeparture.ToString("yyyy-MM-dd'T'HH':00'", CultureInfo.InvariantCulture));
        var temperatures = Numbers(hourly["temperature_2m"]); var feels = Numbers(hourly["apparent_temperature"]); var hourlyCodes = Numbers(hourly["weather_code"]);
        if (at < 0 || at >= temperatures.Count || at >= feels.Count || at >= hourlyCodes.Count || temperatures[at] is null || feels[at] is null || hourlyCodes[at] is null) throw new InvalidOperationException("出发时段的小时预报暂不可用，请调整出发时间或稍后查询。");
        return new WeatherForecast(new WeatherNow(hourlyTimes[at], temperatures[at]!.Value, feels[at]!.Value, (int)hourlyCodes[at]!.Value), days.Where(day => day.Id.CompareTo(startDay) >= 0).Take(16).ToList(), root["elevation"] is null ? null : InventoryDocument.Number(root["elevation"]), zone);
    }

    public async Task<SeasonalOutlook> OutlookAsync(TrailCoordinate point, CancellationToken cancellationToken = default)
    {
        var url = "https://seasonal-api.open-meteo.com/v1/seasonal?latitude=" + point.Latitude.ToString("G", CultureInfo.InvariantCulture) + "&longitude=" + point.Longitude.ToString("G", CultureInfo.InvariantCulture) + "&models=ecmwf_seasonal_ensemble_mean_seamless&weekly=temperature_2m_mean,temperature_2m_anomaly,precipitation_anomaly,wind_speed_10m_mean,cloud_cover_mean&monthly=temperature_2m_mean,temperature_2m_anomaly,precipitation_anomaly,wind_speed_10m_mean,cloud_cover_mean&forecast_days=210&timezone=auto&wind_speed_unit=kmh";
        var root = JsonNode.Parse(await RequestAsync(url, cancellationToken)) as JsonObject ?? throw new InvalidDataException("远期天气数据格式无效。");
        var zone = root["timezone"]?.ToString() ?? "UTC"; var weeks = ReadTrends(root["weekly"] as JsonObject, false); var months = ReadTrends(root["monthly"] as JsonObject, true);
        if (weeks.Count == 0 && months.Count == 0) throw new InvalidOperationException("远期趋势暂不可用。");
        return new SeasonalOutlook(weeks, months, zone);
    }

    public static WeatherTrend? TrendAt(SeasonalOutlook outlook, DateTime departure)
    {
        var date = TimeZoneInfo.ConvertTime(new DateTimeOffset(departure), FindZone(outlook.Timezone)).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        return outlook.Weeks.Concat(outlook.Months).FirstOrDefault(trend => trend.Start.CompareTo(date) <= 0 && date.CompareTo(trend.End) <= 0);
    }

    public static string WeatherText(int code) => code switch { 0 => "晴", 1 or 2 or 3 => "多云", 45 or 48 => "雾", >= 51 and <= 67 or >= 80 and <= 82 => "雨", >= 71 and <= 77 or 85 or 86 => "雪", >= 95 => "雷暴", _ => "天气" };
    public static double DistanceMeters(TrailCoordinate a, TrailCoordinate b)
    {
        var latA = Degrees(a.Latitude); var latB = Degrees(b.Latitude); var h = Math.Pow(Math.Sin((latB - latA) / 2), 2) + Math.Cos(latA) * Math.Cos(latB) * Math.Pow(Math.Sin(Degrees(b.Longitude - a.Longitude) / 2), 2); return 6_371_008.8 * 2 * Math.Asin(Math.Sqrt(Math.Clamp(h, 0, 1)));
    }

    private IReadOnlyList<RouteSummary> LoadDomestic()
    {
        if (catalogPath is null || !File.Exists(catalogPath)) return [];
        using var document = JsonDocument.Parse(File.ReadAllText(catalogPath)); if (!document.RootElement.TryGetProperty("entries", out var entries)) return [];
        return entries.EnumerateArray().Select(entry => entry.GetProperty("route")).Select(route => ParseRoute(route)).Where(route => route is not null).Cast<RouteSummary>().ToList();
    }

    private static RouteSummary? ParseRoute(JsonElement node)
    {
        if (!node.TryGetProperty("center", out var center)) return null;
        var point = new TrailCoordinate(center.GetProperty("lat").GetDouble(), center.GetProperty("lon").GetDouble());
        if (!TrailFileReader.Valid(point)) return null;
        var segments = new List<IReadOnlyList<TrailCoordinate>>();
        if (node.TryGetProperty("segments", out var parts)) foreach (var part in parts.EnumerateArray()) segments.Add(part.EnumerateArray().Select(ReadPoint).ToList());
        var stats = node.TryGetProperty("elevationStats", out var statsNode) ? ReadElevationStats(JsonNode.Parse(statsNode.GetRawText())) : null;
        var profile = node.TryGetProperty("elevationProfile", out var profileNode) ? ReadElevationProfile(JsonNode.Parse(profileNode.GetRawText())) : null;
        return new RouteSummary(node.GetProperty("id").GetInt64(), node.GetProperty("name").GetString() ?? "", node.GetProperty("area").GetString() ?? "", point, node.GetProperty("distance").GetString() ?? "", segments, ElevationStats: stats, ElevationProfile: profile);
    }

    private static RouteElevationStats? ReadElevationStats(JsonNode? node)
    {
        if (node is not JsonObject value) return null;
        return new RouteElevationStats(InventoryDocument.Number(value["minimumMeters"]), InventoryDocument.Number(value["maximumMeters"]), InventoryDocument.Number(value["averageMeters"]), InventoryDocument.Number(value["estimatedAscentMeters"]), InventoryDocument.Number(value["estimatedDescentMeters"]), InventoryDocument.Number(value["profileDistanceMeters"]), InventoryDocument.Int(value["profileSampleCount"]), InventoryDocument.Number(value["noiseThresholdMeters"]), value["source"]?.ToString() ?? "", InventoryDocument.Number(value["sourceResolutionMeters"]), value["method"]?.ToString() ?? "");
    }

    private static IReadOnlyList<RouteElevationSample>? ReadElevationProfile(JsonNode? node) => node is JsonArray values
        ? values.OfType<JsonObject>().Select(value => new RouteElevationSample(InventoryDocument.Number(value["distanceMeters"]), InventoryDocument.Number(value["lat"]), InventoryDocument.Number(value["lon"]), InventoryDocument.Number(value["elevationMeters"]))).ToArray()
        : null;

    private static JsonObject StatsJson(RouteElevationStats value) => new() { ["minimumMeters"] = value.MinimumMeters, ["maximumMeters"] = value.MaximumMeters, ["averageMeters"] = value.AverageMeters, ["estimatedAscentMeters"] = value.EstimatedAscentMeters, ["estimatedDescentMeters"] = value.EstimatedDescentMeters, ["profileDistanceMeters"] = value.ProfileDistanceMeters, ["profileSampleCount"] = value.ProfileSampleCount, ["noiseThresholdMeters"] = value.NoiseThresholdMeters, ["source"] = value.Source, ["sourceResolutionMeters"] = value.SourceResolutionMeters, ["method"] = value.Method };

    private static JsonArray ProfileJson(IEnumerable<RouteElevationSample> values) => new(values.Select(value => (JsonNode?)new JsonObject { ["distanceMeters"] = value.DistanceMeters, ["lat"] = value.Latitude, ["lon"] = value.Longitude, ["elevationMeters"] = value.ElevationMeters }).ToArray());

    private static TrailCoordinate ReadPoint(JsonElement point) => new(point.GetProperty("lat").GetDouble(), point.GetProperty("lon").GetDouble(), point.TryGetProperty("elevation", out var elevation) && elevation.ValueKind == JsonValueKind.Number ? elevation.GetDouble() : null);
    private static IReadOnlyList<RouteSummary> Merge(IEnumerable<RouteSummary> first, IEnumerable<RouteSummary> second) => first.Concat(second).GroupBy(route => route.Id).Select(group => group.First()).ToList();
    private static string Normalize(string text) => string.Concat(text.ToLowerInvariant().Where(char.IsLetterOrDigit));
    private static double Degrees(double value) => value * Math.PI / 180;
    private static double[] Project(double lon, double lat) => [Math.Clamp(lon, -180, 180) * 20037508.34 / 180, Math.Log(Math.Tan(Math.PI / 4 + Math.Clamp(lat, -85, 85) * Math.PI / 360)) * 6_378_137];
    private static TrailCoordinate Unproject(double x, double y) => new((2 * Math.Atan(Math.Exp(y / 6_378_137)) - Math.PI / 2) * 180 / Math.PI, x / 20037508.34 * 180);
    private static TimeZoneInfo FindZone(string zone)
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById(zone); }
        catch { if (TimeZoneInfo.TryConvertIanaIdToWindowsId(zone, out var win)) try { return TimeZoneInfo.FindSystemTimeZoneById(win); } catch { } return TimeZoneInfo.Utc; }
    }
    private async Task<byte[]> RequestAsync(string url, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (Cache.TryGetValue(url, out var cached)) return cached;
        using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken); response.EnsureSuccessStatusCode();
        var data = await response.Content.ReadAsByteArrayAsync(cancellationToken); if (data.Length > 20_000_000) throw new InvalidDataException("联网响应超过大小限制。");
        Cache.TryAdd(url, data); return data;
    }
    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) }; client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("OutdoorGearLibraryWindows", "0.20.4")); client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json")); return client;
    }
    private static List<string> Strings(JsonNode? node) => node is JsonArray array ? array.Select(value => value?.ToString() ?? "").ToList() : [];
    private static List<double?> Numbers(JsonNode? node) => node is JsonArray array ? array.Select(value => (double?)(value is not null && double.TryParse(value.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var result) ? result : null)).ToList() : [];
    private static List<IReadOnlyList<TrailCoordinate>> ReadRouteSegments(JsonNode? route)
    {
        var segments = new List<IReadOnlyList<TrailCoordinate>>(); if (route is not JsonObject node) return segments;
        if (node["geometry"] is JsonObject geometry && geometry["type"]?.ToString() == "LineString" && geometry["coordinates"] is JsonArray coordinates)
        {
            var points = coordinates.OfType<JsonArray>().Where(pair => pair.Count >= 2).Select(pair => Unproject(InventoryDocument.Number(pair[0]), InventoryDocument.Number(pair[1]))).ToList(); if (points.Count > 1) segments.Add(points);
        }
        foreach (var key in new[] { "main", "ways", "appendices" }) if (node[key] is JsonArray children) foreach (var child in children) segments.AddRange(ReadRouteSegments(child));
        return segments;
    }
    private static List<WeatherTrend> ReadTrends(JsonObject? period, bool monthly)
    {
        if (period is null) return [];
        var times = Strings(period["time"]); var means = Numbers(period["temperature_2m_mean"]); var anomalies = Numbers(period["temperature_2m_anomaly"]); var rain = Numbers(period["precipitation_anomaly"]); var wind = Numbers(period["wind_speed_10m_mean"]); var cloud = Numbers(period["cloud_cover_mean"]);
        if (new[] { means.Count, anomalies.Count, rain.Count }.Any(count => count != times.Count)) throw new InvalidDataException("远期趋势数据不完整。");
        var result = new List<WeatherTrend>();
        for (var i = 0; i < times.Count; i++)
        {
            if (means[i] is not { } t || anomalies[i] is not { } a || rain[i] is not { } r || !double.IsFinite(t) || !double.IsFinite(a) || !double.IsFinite(r)) continue;
            if (!DateTime.TryParseExact(times[i], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var start)) continue;
            var end = (monthly ? start.AddMonths(1).AddDays(-1) : start.AddDays(6)).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
            result.Add(new WeatherTrend(times[i], end, monthly, t, a, r, wind.ElementAtOrDefault(i), cloud.ElementAtOrDefault(i)));
        }
        return result;
    }
}
