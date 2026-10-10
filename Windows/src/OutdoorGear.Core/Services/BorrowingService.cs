using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public sealed record BorrowableGearRecord(
    LibraryUserRecord Owner,
    GearRecord Gear,
    string? Subcategory,
    string SourceDirectory);

public sealed record BorrowedGearSnapshot(JsonObject Gear, string? CopiedPhoto);

public static class BorrowingService
{
    public static IReadOnlyList<BorrowableGearRecord> ReadAvailableGear(
        LocalLibraryRepository repository,
        string currentUserId,
        string ownerId)
    {
        if (InventoryDocument.IdEquals(currentUserId, ownerId))
            throw new InvalidOperationException("只能从其他用户的装备库借用装备。");
        var owner = repository.Catalog.Users.FirstOrDefault(user => InventoryDocument.IdEquals(user.Id, ownerId))
            ?? throw new InvalidOperationException("来源用户不存在。");
        var sourceDirectory = repository.DirectoryFor(owner.Id);
        var inventory = repository.ReadUserInventory(owner.Id);
        return inventory.Gear(false)
            .Where(gear => !gear.IsLocation)
            .Select(gear => new BorrowableGearRecord(owner, gear, gear.Extras.Subcategory, sourceDirectory))
            .ToList();
    }

    public static bool RefreshSnapshots(
        LocalLibraryRepository repository,
        string currentUserId,
        InventoryDocument inventory)
    {
        var sources = new Dictionary<string, InventoryDocument?>(StringComparer.OrdinalIgnoreCase);
        var changed = false;
        foreach (var borrowed in inventory.BorrowedNodes.OfType<JsonObject>())
            changed |= RefreshSnapshot(repository, currentUserId, borrowed, sources);
        return changed;
    }

    private static bool RefreshSnapshot(
        LocalLibraryRepository repository,
        string currentUserId,
        JsonObject borrowed,
        Dictionary<string, InventoryDocument?> sources)
    {
        var ownerId = InventoryDocument.NormalizeId(borrowed["ownerID"]?.ToString());
        if (ownerId is null || InventoryDocument.IdEquals(ownerId, currentUserId)) return SetUnavailable(borrowed);
        var owner = repository.Catalog.Users.FirstOrDefault(user => InventoryDocument.IdEquals(user.Id, ownerId));
        if (owner is null) return SetUnavailable(borrowed);
        var source = ReadSource(repository, ownerId, sources);
        var gear = source?.FindGear(borrowed["gear"]?["id"]?.ToString());
        if (gear is null || gear.Trashed || gear.IsLocation) return SetUnavailable(borrowed);
        return UpdateSnapshot(borrowed, owner, gear);
    }

    private static InventoryDocument? ReadSource(
        LocalLibraryRepository repository,
        string ownerId,
        Dictionary<string, InventoryDocument?> sources)
    {
        if (sources.TryGetValue(ownerId, out var cached)) return cached;
        try { return sources[ownerId] = repository.ReadUserInventory(ownerId); }
        catch { return sources[ownerId] = null; }
    }

    private static bool UpdateSnapshot(JsonObject borrowed, LibraryUserRecord owner, GearRecord gear)
    {
        var updated = (JsonObject)gear.Node.DeepClone();
        updated["location"] = "";
        updated["photo"] = borrowed["gear"]?["photo"]?.DeepClone();
        var quantity = Math.Min(InventoryDocument.Number(borrowed["quantity"]), gear.Quantity);
        var unavailable = gear.Status == "损坏";
        if (JsonNode.DeepEquals(borrowed["gear"], updated) &&
            borrowed["ownerName"]?.ToString() == owner.Name &&
            InventoryDocument.Number(borrowed["quantity"]) == quantity &&
            borrowed["subcategory"]?.ToString() == gear.Extras.Subcategory &&
            InventoryDocument.Bool(borrowed["unavailable"]) == unavailable)
            return false;

        borrowed["gear"] = updated;
        borrowed["ownerName"] = owner.Name;
        borrowed["quantity"] = quantity;
        borrowed["subcategory"] = gear.Extras.Subcategory;
        borrowed["unavailable"] = unavailable;
        return true;
    }

    private static bool SetUnavailable(JsonObject borrowed)
    {
        if (InventoryDocument.Bool(borrowed["unavailable"])) return false;
        borrowed["unavailable"] = true;
        return true;
    }

    public static BorrowedGearSnapshot CopyGearSnapshot(
        string sourceDirectory,
        string destinationDirectory,
        GearRecord source)
    {
        var snapshot = (JsonObject)source.Node.DeepClone();
        snapshot["location"] = "";
        var photo = source.Photo;
        if (string.IsNullOrWhiteSpace(photo)) return new BorrowedGearSnapshot(snapshot, null);

        var sourcePath = GearAssetService.AssetPath(sourceDirectory, "Photos", photo);
        if (!File.Exists(sourcePath)) throw new FileNotFoundException("来源装备的主照片不存在。", sourcePath);
        var extension = Path.GetExtension(photo);
        if (extension.Length is < 2 or > 12) throw new InvalidDataException("来源装备的照片扩展名无效。");
        var copiedPhoto = Guid.NewGuid().ToString("D").ToUpperInvariant() + extension.ToLowerInvariant();
        var destinationPath = GearAssetService.AssetPath(destinationDirectory, "Photos", copiedPhoto);
        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
        try
        {
            File.Copy(sourcePath, destinationPath);
            snapshot["photo"] = copiedPhoto;
            return new BorrowedGearSnapshot(snapshot, copiedPhoto);
        }
        catch
        {
            try { File.Delete(destinationPath); } catch { }
            throw;
        }
    }

    public static void RemoveCopiedPhoto(string destinationDirectory, string? copiedPhoto)
    {
        if (string.IsNullOrWhiteSpace(copiedPhoto)) return;
        var path = GearAssetService.AssetPath(destinationDirectory, "Photos", copiedPhoto);
        if (File.Exists(path)) File.Delete(path);
    }
}
