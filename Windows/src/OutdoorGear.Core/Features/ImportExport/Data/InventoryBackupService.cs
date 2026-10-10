using System.IO.Compression;
using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;

namespace OutdoorGear.Core.Features.ImportExport.Data;

public static class InventoryBackupService
{
    public static string Create(InventoryDocument inventory, string dataDirectory, string destination)
    {
        inventory.Validate();
        var target = Path.GetFullPath(destination);
        if (Directory.Exists(target)) throw new IOException("备份路径指向一个文件夹，请选择文件名。");
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        var temporary = target + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { WriteArchive(inventory, dataDirectory, temporary); File.Move(temporary, target, overwrite: true); return target; }
        catch { if (File.Exists(temporary)) File.Delete(temporary); throw; }
    }

    public static BackupSource Open(string path)
    {
        var fullPath = Path.GetFullPath(path);
        if (Directory.Exists(fullPath)) return new BackupSource(fullPath, null);
        if (!File.Exists(fullPath)) throw new FileNotFoundException("找不到备份文件或目录。", fullPath);
        return ExtractArchive(fullPath);
    }

    private static void WriteArchive(InventoryDocument inventory, string dataDirectory, string temporary)
    {
        using var archive = ZipFile.Open(temporary, ZipArchiveMode.Create);
        var json = archive.CreateEntry("inventory.json", CompressionLevel.Optimal);
        using (var writer = new StreamWriter(json.Open())) writer.Write(inventory.Serialize());
        foreach (var folder in new[] { "Photos", "Files" }) AddAssets(archive, dataDirectory, folder);
    }

    private static void AddAssets(ZipArchive archive, string root, string folder)
    {
        var directory = Path.Combine(root, folder);
        if (!Directory.Exists(directory)) return;
        foreach (var file in Directory.EnumerateFiles(directory, "*", SearchOption.TopDirectoryOnly))
            archive.CreateEntryFromFile(file, folder + "/" + Path.GetFileName(file), CompressionLevel.Optimal);
    }

    private static BackupSource ExtractArchive(string archivePath)
    {
        var staging = Path.Combine(Path.GetTempPath(), "OutdoorGearBackup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            ExtractEntries(archivePath, staging);
            if (!File.Exists(Path.Combine(staging, "inventory.json"))) throw new InvalidDataException("备份中缺少 inventory.json。");
            return new BackupSource(staging, staging);
        }
        catch { Directory.Delete(staging, recursive: true); throw; }
    }

    private static void ExtractEntries(string archivePath, string staging)
    {
        using var archive = ZipFile.OpenRead(archivePath);
        if (archive.Entries.Count > 20_000 || archive.Entries.Sum(entry => entry.Length) > 2_000_000_000)
            throw new InvalidDataException("备份文件超出解压限制。");
        foreach (var entry in archive.Entries) ExtractEntry(entry, staging);
    }

    private static void ExtractEntry(ZipArchiveEntry entry, string staging)
    {
        var relative = entry.FullName.Replace('\\', '/');
        if (IsInvalidEntryPath(relative)) throw new InvalidDataException("备份包含无效路径。");
        var target = Path.GetFullPath(Path.Combine(staging, relative.Replace('/', Path.DirectorySeparatorChar)));
        var root = Path.GetFullPath(staging) + Path.DirectorySeparatorChar;
        if (!target.StartsWith(root, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)) throw new InvalidDataException("备份包含无效路径。");
        if (entry.Name.Length == 0) { Directory.CreateDirectory(target); return; }
        Directory.CreateDirectory(Path.GetDirectoryName(target)!);
        entry.ExtractToFile(target, overwrite: false);
    }

    private static bool IsInvalidEntryPath(string path)
    {
        var driveQualified = path.Length >= 2 && char.IsAsciiLetter(path[0]) && path[1] == ':';
        return string.IsNullOrWhiteSpace(path) || Path.IsPathRooted(path) || path.StartsWith('/') || driveQualified ||
            path.TrimEnd('/').Split('/').Any(part => part.Length == 0 || part is "." or ".." || part.Contains(':'));
    }
}

public sealed class BackupSource(string root, string? temporaryDirectory) : IDisposable
{
    public string Root { get; } = root;
    public void Dispose()
    {
        if (temporaryDirectory is not null && Directory.Exists(temporaryDirectory))
            try { Directory.Delete(temporaryDirectory, recursive: true); } catch { }
    }
}
