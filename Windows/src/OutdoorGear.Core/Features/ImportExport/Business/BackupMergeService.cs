using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Features.ImportExport.Business;

public static class BackupMergeService
{
    public static InventoryDocument Merge(InventoryDocument backup, InventoryDocument current, int sourceVersion)
    {
        var next = InventoryDocument.Parse(current.Serialize());
        var restoredIds = backup.Gear().Select(item => item.Id!).ToHashSet(StringComparer.OrdinalIgnoreCase);
        MergeById(next.GearNodes, backup.GearNodes, "id");
        MergeById(next.PackingNodes, backup.PackingNodes, "id");
        MergeBorrowed(next, backup);
        if (sourceVersion >= 9) next.Root["mealPlan"] = backup.MealPlan.DeepClone();
        MergeById(next.HikeNodes, backup.HikeNodes, "id");
        MergeDetails(next, backup);
        MergeLabels(next, backup);
        MergeTemplates(next, backup);
        RepairAssetIdentifiers(next, restoredIds);
        RebuildLocations(next);
        if (backup.Root["selectedRoute"] is not null) next.Root["selectedRoute"] = backup.Root["selectedRoute"]!.DeepClone();
        next.Root["settings"] = backup.Settings.DeepClone();
        next.Validate();
        return next;
    }

    private static void MergeById(JsonArray target, JsonArray source, string idKey)
    {
        var restoredIds = source.OfType<JsonObject>().Select(item => item[idKey]?.ToString()).Where(id => id is not null).ToHashSet(StringComparer.OrdinalIgnoreCase);
        for (var index = target.Count - 1; index >= 0; index--)
            if (target[index] is JsonObject item && restoredIds.Contains(item[idKey]?.ToString())) target.RemoveAt(index);
        foreach (var item in source) target.Add(item?.DeepClone());
    }

    private static void MergeBorrowed(InventoryDocument target, InventoryDocument source)
    {
        foreach (var restored in source.BorrowedNodes.OfType<JsonObject>())
        {
            var owner = restored["ownerID"]?.ToString(); var gearId = restored["gear"]?["id"]?.ToString();
            for (var index = target.BorrowedNodes.Count - 1; index >= 0; index--)
                if (target.BorrowedNodes[index] is JsonObject item && InventoryDocument.IdEquals(item["ownerID"]?.ToString(), owner) && InventoryDocument.IdEquals(item["gear"]?["id"]?.ToString(), gearId))
                    target.BorrowedNodes.RemoveAt(index);
            target.BorrowedNodes.Add(restored.DeepClone());
        }
    }

    private static void MergeDetails(InventoryDocument target, InventoryDocument source)
    {
        foreach (var pair in source.Details) target.Details[pair.Key] = pair.Value?.DeepClone();
    }

    private static void MergeLabels(InventoryDocument target, InventoryDocument source)
    {
        foreach (var restored in source.Labels.OfType<JsonObject>()) MergeLabel(target.Labels, restored);
    }

    private static void MergeLabel(JsonArray labels, JsonObject restored)
    {
        var restoredId = restored["id"]?.ToString(); var restoredName = restored["name"]?.ToString();
        var previous = labels.OfType<JsonObject>().FirstOrDefault(label => label["name"]?.ToString() == restoredName && !InventoryDocument.IdEquals(label["id"]?.ToString(), restoredId));
        if (previous is not null) ReplaceLabelParentReferences(labels, previous["id"]?.ToString(), restoredId);
        RemoveLabelDuplicates(labels, restoredId, restoredName);
        labels.Add(restored.DeepClone());
    }

    private static void ReplaceLabelParentReferences(JsonArray labels, string? oldId, string? newId)
    {
        foreach (var label in labels.OfType<JsonObject>())
            if (InventoryDocument.IdEquals(label["parentID"]?.ToString(), oldId)) label["parentID"] = newId;
    }

    private static void RemoveLabelDuplicates(JsonArray labels, string? id, string? name)
    {
        for (var index = labels.Count - 1; index >= 0; index--)
            if (labels[index] is JsonObject label && (InventoryDocument.IdEquals(label["id"]?.ToString(), id) || label["name"]?.ToString() == name))
                labels.RemoveAt(index);
    }

    private static void MergeTemplates(InventoryDocument target, InventoryDocument source) => MergeById(target.Templates, source.Templates, "id");

    private static void RepairAssetIdentifiers(InventoryDocument inventory, HashSet<string> restoredIds)
    {
        var used = new HashSet<int>();
        var nextId = inventory.Details.Select(pair => InventoryDocument.Int(pair.Value?["assetID"])).DefaultIfEmpty().Max() + 1;
        foreach (var gear in inventory.Gear().OrderByDescending(item => restoredIds.Contains(item.Id!)))
        {
            var extras = gear.Extras;
            if (extras.AssetId <= 0 || !used.Add(extras.AssetId)) extras.AssetId = AllocateAssetId(used, ref nextId);
        }
    }

    private static int AllocateAssetId(HashSet<int> used, ref int nextId)
    {
        while (used.Contains(nextId)) nextId++;
        var allocated = nextId++;
        used.Add(allocated);
        return allocated;
    }

    private static void RebuildLocations(InventoryDocument inventory)
    {
        inventory.Locations.Clear();
        foreach (var location in inventory.Gear(false).Where(item => item.IsLocation).Select(item => item.Name).Distinct(StringComparer.OrdinalIgnoreCase))
            inventory.Locations.Add(location);
    }
}
