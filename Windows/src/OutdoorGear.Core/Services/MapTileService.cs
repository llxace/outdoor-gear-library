using System.Net.Http;

namespace OutdoorGear.Core.Services;

public static class MapTileService
{
    public static string Attribution(bool satellite) => satellite
        ? "卫星影像 · Source: Esri, Vantor, Earthstar Geographics, GIS User Community"
        : "OpenStreetMap · © OpenStreetMap contributors";

    public static Uri TileUri(int zoom, int x, int y, bool satellite)
    {
        var count = zoom is >= 0 and <= 23 ? 1 << zoom : throw new ArgumentOutOfRangeException(nameof(zoom));
        if (x < 0 || x >= count) throw new ArgumentOutOfRangeException(nameof(x));
        if (y < 0 || y >= count) throw new ArgumentOutOfRangeException(nameof(y));
        var address = satellite
            ? $"https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{zoom}/{y}/{x}"
            : $"https://tile.openstreetmap.org/{zoom}/{x}/{y}.png";
        return new Uri(address);
    }

    public static async Task<byte[]> LoadAsync(HttpClient client, int zoom, int x, int y, bool satellite, string? cacheRoot = null)
    {
        var uri = TileUri(zoom, x, y, satellite);
        var root = cacheRoot ?? Path.Combine(Path.GetTempPath(), "OutdoorGearTiles");
        var provider = satellite ? "esri-imagery" : "openstreetmap";
        var folder = Path.Combine(root, provider, zoom.ToString(), x.ToString());
        var path = Path.Combine(folder, y + ".tile");
        if (File.Exists(path)) return await File.ReadAllBytesAsync(path);
        return await DownloadAsync(client, uri, folder, path);
    }

    private static async Task<byte[]> DownloadAsync(HttpClient client, Uri uri, string folder, string path)
    {
        var bytes = await client.GetByteArrayAsync(uri);
        Directory.CreateDirectory(folder);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { await File.WriteAllBytesAsync(temporary, bytes); File.Move(temporary, path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
        return bytes;
    }
}
