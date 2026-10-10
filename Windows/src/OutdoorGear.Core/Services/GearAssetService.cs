using System.IO;
using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public static class GearAssetService
{
    public static string AssetPath(string dataDirectory, string folder, string fileName)
    {
        if (folder is not ("Photos" or "Files") || string.IsNullOrWhiteSpace(fileName) ||
            fileName.Contains('/') || fileName.Contains('\\') ||
            !string.Equals(fileName, Path.GetFileName(fileName), StringComparison.Ordinal))
            throw new InvalidDataException("附件路径无效。");
        var root = Path.GetFullPath(Path.Combine(dataDirectory, folder));
        var path = Path.GetFullPath(Path.Combine(root, fileName));
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        if (!path.StartsWith(root + Path.DirectorySeparatorChar, comparison)) throw new InvalidDataException("附件路径超出当前资料库。");
        return path;
    }

    public static string CopyImageAttachmentToPhotos(string dataDirectory, JsonObject attachment)
    {
        if (!InventoryDocument.Bool(attachment["isImage"])) throw new InvalidDataException("所选附件不是图片。");
        var source = AttachmentPath(dataDirectory, attachment);
        if (!File.Exists(source)) throw new FileNotFoundException("找不到这张图片附件。", source);
        var extension = Path.GetExtension(source);
        if (extension.Length is < 2 or > 12) throw new InvalidDataException("图片附件类型无效。");
        var fileName = Guid.NewGuid().ToString("D").ToUpperInvariant() + extension;
        File.Copy(source, AssetPath(dataDirectory, "Photos", fileName));
        return fileName;
    }

    public static IReadOnlyList<string> CopyGearAssetsToDirectory(
        GearRecord gear,
        string sourceDirectory,
        string destinationDirectory)
    {
        if (string.Equals(Path.GetFullPath(sourceDirectory), Path.GetFullPath(destinationDirectory), PathComparison()))
            return [];

        var created = new List<string>();
        try
        {
            if (!string.IsNullOrWhiteSpace(gear.Photo))
                gear.Photo = CopyAsset(sourceDirectory, destinationDirectory, "Photos", gear.Photo, created);

            foreach (var attachment in (gear.Extras.Node["attachments"] as JsonArray)?.OfType<JsonObject>() ?? [])
            {
                var fileName = attachment["file"]?.ToString();
                if (!string.IsNullOrWhiteSpace(fileName))
                    attachment["file"] = CopyAsset(sourceDirectory, destinationDirectory, "Files", fileName, created, attachment);
            }
            return created;
        }
        catch
        {
            DeleteCreated(created);
            throw;
        }
    }

    public static void DeleteCreated(IEnumerable<string> paths)
    {
        foreach (var path in paths)
            try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    private static string CopyAsset(
        string sourceDirectory,
        string destinationDirectory,
        string destinationFolder,
        string fileName,
        List<string> created,
        JsonObject? attachment = null)
    {
        var source = attachment is null
            ? AssetPath(sourceDirectory, "Photos", fileName)
            : AttachmentPath(sourceDirectory, attachment);
        if (!File.Exists(source)) throw new FileNotFoundException("新增装备引用的照片或附件不存在。", source);
        var extension = Path.GetExtension(source);
        if (extension.Length is < 2 or > 12) throw new InvalidDataException("照片或附件类型无效。");
        var copiedName = Guid.NewGuid().ToString("D").ToUpperInvariant() + extension;
        var destination = AssetPath(destinationDirectory, destinationFolder, copiedName);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        created.Add(destination);
        File.Copy(source, destination);
        return copiedName;
    }

    private static StringComparison PathComparison() => OperatingSystem.IsWindows()
        ? StringComparison.OrdinalIgnoreCase
        : StringComparison.Ordinal;

    public static string AttachmentPath(string dataDirectory, JsonObject attachment)
    {
        var fileName = attachment["file"]?.ToString() ?? "";
        var path = AssetPath(dataDirectory, "Files", fileName);
        if (File.Exists(path) || attachment["title"]?.ToString() != "修图原图") return path;
        var legacyPath = AssetPath(dataDirectory, "Photos", fileName);
        return File.Exists(legacyPath) ? legacyPath : path;
    }
}
