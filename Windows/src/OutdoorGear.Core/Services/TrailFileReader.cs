using System.Globalization;
using System.Xml;
using System.Xml.Linq;
using System.Text.Json.Nodes;

namespace OutdoorGear.Core.Services;

public sealed record TrailCoordinate(double Latitude, double Longitude, double? Elevation = null);
public sealed record ImportedTrail(long Id, string Name, string Area, TrailCoordinate Center, string Distance, IReadOnlyList<IReadOnlyList<TrailCoordinate>> Segments, string ImportedFile);

public static class TrailFileReader
{
    public const int MaximumFileBytes = 10_000_000;
    public const int MaximumPoints = 50_000;

    public static ImportedTrail Read(string filename, Stream input)
    {
        using var buffer = new MemoryStream(); input.CopyTo(buffer);
        if (buffer.Length > MaximumFileBytes) throw new InvalidDataException("轨迹文件超过 10 MB，请先精简。");
        buffer.Position = 0;
        using var xml = XmlReader.Create(buffer, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = MaximumFileBytes, IgnoreComments = true });
        var document = XDocument.Load(xml, LoadOptions.None); var root = document.Root?.Name.LocalName.ToLowerInvariant();
        if (root is not ("gpx" or "kml")) throw new InvalidDataException("文件不是有效的 GPX 或 KML 轨迹。");
        var title = ReadTitle(document, root!);
        var segments = root == "gpx" ? ReadGpx(document) : ReadKml(document);
        segments = segments.Where(segment => segment.Count >= 2).ToList();
        var points = segments.SelectMany(segment => segment).ToList();
        if (points.Count < 2) throw new InvalidDataException("文件中没有可显示的线路；仅有位置标记不能作为徒步轨迹。");
        if (points.Count > MaximumPoints) throw new InvalidDataException("轨迹超过 50,000 个点，暂时无法导入。");
        if (points.Any(point => !Valid(point))) throw new InvalidDataException("轨迹包含无效经纬度。");
        var center = new TrailCoordinate((points.Min(p => p.Latitude) + points.Max(p => p.Latitude)) / 2, (points.Min(p => p.Longitude) + points.Max(p => p.Longitude)) / 2);
        var distanceKm = DistanceMeters(segments) / 1000;
        var name = string.IsNullOrWhiteSpace(title) ? Path.GetFileNameWithoutExtension(filename) : title;
        return new ImportedTrail(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() * 1000, name, "导入轨迹", center, distanceKm.ToString("0.0", CultureInfo.InvariantCulture) + " km（轨迹估算）", segments, Path.GetFileName(filename));
    }

    public static JsonObject ToJson(ImportedTrail trail)
    {
        var segments = new JsonArray();
        foreach (var segment in trail.Segments)
        {
            var rows = new JsonArray();
            foreach (var point in segment) rows.Add(new JsonObject { ["lat"] = point.Latitude, ["lon"] = point.Longitude, ["elevation"] = point.Elevation });
            segments.Add(rows);
        }
        return new JsonObject { ["id"] = trail.Id, ["name"] = trail.Name, ["area"] = trail.Area, ["center"] = new JsonObject { ["lat"] = trail.Center.Latitude, ["lon"] = trail.Center.Longitude }, ["distance"] = trail.Distance, ["segments"] = segments, ["importedFile"] = trail.ImportedFile };
    }

    public static double DistanceMeters(IEnumerable<IReadOnlyList<TrailCoordinate>> segments)
    {
        const double radius = 6_371_000;
        return segments.Sum(segment => Enumerable.Range(0, Math.Max(0, segment.Count - 1)).Sum(index =>
        {
            var a = segment[index]; var b = segment[index + 1]; var latA = Degrees(a.Latitude); var latB = Degrees(b.Latitude);
            var h = Math.Pow(Math.Sin((latB - latA) / 2), 2) + Math.Cos(latA) * Math.Cos(latB) * Math.Pow(Math.Sin(Degrees(b.Longitude - a.Longitude) / 2), 2);
            return radius * 2 * Math.Asin(Math.Sqrt(Math.Clamp(h, 0, 1)));
        }));
    }

    public static bool Valid(TrailCoordinate point) => double.IsFinite(point.Latitude) && double.IsFinite(point.Longitude) && point.Latitude is >= -90 and <= 90 && point.Longitude is >= -180 and <= 180 && (point.Elevation is null || double.IsFinite(point.Elevation.Value));
    private static double Degrees(double value) => value * Math.PI / 180;
    private static string ReadTitle(XDocument document, string root) => document.Descendants().Where(element => element.Name.LocalName == "name" && (root == "gpx" || element.Ancestors().Any(parent => new[] { "Document", "Placemark" }.Contains(parent.Name.LocalName)))).Select(element => element.Value.Trim()).FirstOrDefault(value => value.Length > 0) ?? "";

    private static List<List<TrailCoordinate>> ReadGpx(XDocument document)
    {
        var result = new List<List<TrailCoordinate>>();
        foreach (var segment in document.Descendants().Where(element => element.Name.LocalName is "trkseg" or "rte"))
        {
            var points = segment.Elements().Where(element => element.Name.LocalName is "trkpt" or "rtept").Select(element =>
            {
                var lat = Parse(element.Attribute("lat")?.Value, "轨迹点缺少纬度。"); var lon = Parse(element.Attribute("lon")?.Value, "轨迹点缺少经度。");
                var elevation = element.Elements().FirstOrDefault(child => child.Name.LocalName == "ele")?.Value;
                return new TrailCoordinate(lat, lon, elevation is null ? null : Parse(elevation, "轨迹包含无效高程。"));
            }).ToList();
            result.Add(points);
        }
        return result;
    }

    private static List<List<TrailCoordinate>> ReadKml(XDocument document)
    {
        var result = new List<List<TrailCoordinate>>();
        foreach (var line in document.Descendants().Where(element => element.Name.LocalName == "LineString"))
        {
            var text = line.Descendants().FirstOrDefault(element => element.Name.LocalName == "coordinates")?.Value ?? "";
            var points = ParseKmlCoordinates(text); if (points.Count > 0) result.Add(points);
        }
        foreach (var track in document.Descendants().Where(element => element.Name.LocalName == "Track"))
        {
            var points = track.Elements().Where(element => element.Name.LocalName == "coord").Select(element =>
            {
                var values = element.Value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                if (values.Length < 2) throw new InvalidDataException("KML 轨迹坐标格式不正确。");
                return new TrailCoordinate(Parse(values[1], "KML 纬度无效。"), Parse(values[0], "KML 经度无效。"), values.Length > 2 ? Parse(values[2], "KML 高程无效。") : null);
            }).ToList();
            if (points.Count > 0) result.Add(points);
        }
        return result;
    }

    private static List<TrailCoordinate> ParseKmlCoordinates(string text)
    {
        var result = new List<TrailCoordinate>();
        foreach (var token in text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
        {
            var values = token.Split(','); if (values.Length < 2) throw new InvalidDataException("KML 轨迹坐标格式不正确。");
            result.Add(new TrailCoordinate(Parse(values[1], "KML 纬度无效。"), Parse(values[0], "KML 经度无效。"), values.Length > 2 && values[2].Length > 0 ? Parse(values[2], "KML 高程无效。") : null));
        }
        return result;
    }

    private static double Parse(string? text, string error) => double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) && double.IsFinite(value) ? value : throw new InvalidDataException(error);
}
