using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;

namespace OutdoorGear.Core.Features.ImportExport.Data;

public sealed class BackupAssetRestorer(string sourceDirectory, string targetDirectory)
{
    private readonly Dictionary<string, string> copiedNames = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<string> createdFiles = [];

    public InventoryDocument Read(out int sourceVersion)
    {
        var root = JsonNode.Parse(File.ReadAllText(Path.Combine(sourceDirectory, "inventory.json"))) as JsonObject
            ?? throw new InvalidDataException("备份中的 inventory.json 格式无效。");
        sourceVersion = InventoryDocument.Int(root["version"]);
        if (sourceVersion is < 1 or > InventoryDocument.CurrentSchema) throw new InvalidDataException("备份数据版本不受支持。");
        var inventory = InventoryDocument.Parse(root.ToJsonString());
        RewriteEquipment(inventory);
        RewriteTemplates(inventory);
        RewriteBorrowedGear(inventory);
        RewriteHistoryGear(inventory);
        return inventory;
    }

    public void CleanupCreatedFiles()
    {
        foreach (var file in createdFiles) try { if (File.Exists(file)) File.Delete(file); } catch { }
        createdFiles.Clear();
    }

    private void RewriteEquipment(InventoryDocument inventory)
    {
        foreach (var gear in inventory.GearNodes.OfType<JsonObject>())
            RewriteGearAssets(gear, inventory.Extras(gear["id"]?.ToString()).Node);
    }

    private void RewriteTemplates(InventoryDocument inventory)
    {
        foreach (var template in inventory.Templates.OfType<JsonObject>())
        {
            if (template["gear"] is not JsonObject gear) continue;
            var extras = template["extras"] as JsonObject ?? new JsonObject();
            RewriteGearAssets(gear, extras); template["extras"] = extras;
        }
    }

    private void RewriteBorrowedGear(InventoryDocument inventory)
    {
        foreach (var item in inventory.BorrowedNodes.OfType<JsonObject>())
            if (item["gear"] is JsonObject gear) RewritePhoto(gear);
    }

    private void RewriteHistoryGear(InventoryDocument inventory)
    {
        foreach (var hike in inventory.HikeNodes.OfType<JsonObject>())
            foreach (var item in (hike["gear"] as JsonArray ?? []).OfType<JsonObject>())
                if (item["gear"] is JsonObject gear) RewritePhoto(gear);
    }

    private void RewriteGearAssets(JsonObject gear, JsonObject extras)
    {
        RewritePhoto(gear);
        foreach (var attachment in (extras["attachments"] as JsonArray ?? []).OfType<JsonObject>())
            RewriteAttachment(attachment);
    }

    private void RewritePhoto(JsonObject gear)
    {
        if (gear["photo"]?.ToString() is not { Length: > 0 } file) return;
        gear["photo"] = CopyAsset(file, "Photos", "Photos");
    }

    private void RewriteAttachment(JsonObject attachment)
    {
        if (attachment["file"]?.ToString() is not { Length: > 0 } file) throw new InvalidDataException("备份中存在空的附件文件名。");
        var legacy = attachment["title"]?.ToString() == "修图原图" && !File.Exists(AssetSourcePath("Files", file));
        attachment["file"] = CopyAsset(file, "Files", legacy ? "Photos" : "Files");
    }

    private string CopyAsset(string fileName, string targetFolder, string sourceFolder)
    {
        if (Path.GetFileName(fileName) != fileName || fileName is "." or "..") throw new InvalidDataException("备份附件路径无效。");
        var key = targetFolder + "/" + fileName;
        if (copiedNames.TryGetValue(key, out var existing)) return existing;
        var source = AssetSourcePath(sourceFolder, fileName);
        if (!File.Exists(source)) throw new FileNotFoundException("备份引用了缺失的照片或附件。", source);
        var extension = Path.GetExtension(fileName);
        if (extension.Length > 12) throw new InvalidDataException("备份附件扩展名无效。");
        var copied = Guid.NewGuid().ToString("D").ToUpperInvariant() + extension;
        var target = GearAssetService.AssetPath(targetDirectory, targetFolder, copied);
        Directory.CreateDirectory(Path.GetDirectoryName(target)!); File.Copy(source, target);
        copiedNames.Add(key, copied); createdFiles.Add(target);
        return copied;
    }

    private string AssetSourcePath(string folder, string fileName) => GearAssetService.AssetPath(sourceDirectory, folder, fileName);
}
