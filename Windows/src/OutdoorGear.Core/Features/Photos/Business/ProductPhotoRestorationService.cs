using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;

namespace OutdoorGear.Core.Features.Photos.Business;

public sealed record ProductPhotoRestoreChange(
    GearRecord Gear,
    string? PreviousPhoto,
    JsonObject OriginalAttachment,
    int AttachmentIndex,
    string? CreatedPhotoPath);

public static class ProductPhotoRestorationService
{
    public static ProductPhotoRestoreChange Restore(InventoryDocument inventory, string dataDirectory, string gearId)
    {
        var gear = inventory.FindGear(gearId) ?? throw new InvalidOperationException("装备记录不存在。");
        if (gear.Trashed) throw new InvalidOperationException("回收站中的装备不能恢复主照片。");
        var (index, original) = FindOriginalAttachment(gear);
        var restoredName = RestorePhotoFile(dataDirectory, original, out var createdPhotoPath);
        var change = new ProductPhotoRestoreChange(
            gear,
            gear.Photo,
            (JsonObject)original.DeepClone(),
            index,
            createdPhotoPath);
        gear.Photo = restoredName;
        gear.Extras.Attachments.RemoveAt(index);
        return change;
    }

    private static (int Index, JsonObject Attachment) FindOriginalAttachment(GearRecord gear)
    {
        var attachments = gear.Extras.Attachments;
        var index = Enumerable.Range(0, attachments.Count)
            .Where(i => attachments[i] is JsonObject item && item["title"]?.ToString() == "修图原图")
            .DefaultIfEmpty(-1)
            .Last();
        if (index < 0 || attachments[index] is not JsonObject attachment)
            throw new InvalidOperationException("没有找到可恢复的原始照片。");
        return (index, attachment);
    }

    private static string RestorePhotoFile(string dataDirectory, JsonObject attachment, out string? createdPhotoPath)
    {
        var fileName = attachment["file"]?.ToString() ?? "";
        var legacyPhoto = GearAssetService.AssetPath(dataDirectory, "Photos", fileName);
        if (File.Exists(legacyPhoto)) { createdPhotoPath = null; return fileName; }
        var restoredName = GearAssetService.CopyImageAttachmentToPhotos(dataDirectory, attachment);
        createdPhotoPath = GearAssetService.AssetPath(dataDirectory, "Photos", restoredName);
        return restoredName;
    }

    public static void RollBack(ProductPhotoRestoreChange change)
    {
        change.Gear.Photo = change.PreviousPhoto;
        change.Gear.Extras.Attachments.Insert(
            Math.Clamp(change.AttachmentIndex, 0, change.Gear.Extras.Attachments.Count),
            (JsonObject)change.OriginalAttachment.DeepClone());
        if (change.CreatedPhotoPath is { } path) GearAssetService.DeleteCreated([path]);
    }
}
