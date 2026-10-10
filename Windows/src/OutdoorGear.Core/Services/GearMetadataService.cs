using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public static class GearMetadataService
{
    public static void SaveLabel(InventoryDocument inventory, JsonObject label)
    {
        var id = InventoryDocument.NormalizeId(label["id"]?.ToString()) ?? Guid.NewGuid().ToString("D").ToUpperInvariant();
        var name = label["name"]?.ToString()?.Trim() ?? "";
        if (name.Length == 0 || name.Contains(',') || inventory.Labels.OfType<JsonObject>().Any(item => !InventoryDocument.IdEquals(item["id"]?.ToString(), id) && string.Equals(item["name"]?.ToString(), name, StringComparison.OrdinalIgnoreCase)))
            throw new InvalidDataException("标签名不能为空、重复或包含逗号。");
        var parent = InventoryDocument.NormalizeId(label["parentID"]?.ToString());
        if (parent is not null && !inventory.Labels.OfType<JsonObject>().Any(item => InventoryDocument.IdEquals(item["id"]?.ToString(), parent))) throw new InvalidDataException("标签父级不存在。");
        var cursor = parent; var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { id };
        while (cursor is not null)
        {
            if (!seen.Add(cursor)) throw new InvalidDataException("标签层级不能形成循环。");
            cursor = inventory.Labels.OfType<JsonObject>().FirstOrDefault(item => InventoryDocument.IdEquals(item["id"]?.ToString(), cursor))?["parentID"] is { } next ? InventoryDocument.NormalizeId(next.ToString()) : null;
        }

        var existing = inventory.Labels.OfType<JsonObject>().FirstOrDefault(item => InventoryDocument.IdEquals(item["id"]?.ToString(), id));
        var oldName = existing?["name"]?.ToString();
        label["id"] = id; label["name"] = name;
        if (label["color"] is null) label["color"] = "绿色";
        if (existing is not null) inventory.Labels.Remove(existing);
        inventory.Labels.Add((JsonObject)label.DeepClone());
        if (!string.IsNullOrEmpty(oldName) && oldName != name)
        {
            foreach (var gear in inventory.Gear()) gear.Tags = RenameTag(gear.Tags, oldName, name);
            foreach (var template in inventory.Templates.OfType<JsonObject>())
                if (template["gear"] is JsonObject node) node["tags"] = RenameTag(node["tags"]?.ToString() ?? "", oldName, name);
        }
    }

    public static void RemoveLabel(InventoryDocument inventory, string id)
    {
        var label = inventory.Labels.OfType<JsonObject>().FirstOrDefault(item => InventoryDocument.IdEquals(item["id"]?.ToString(), id))
            ?? throw new InvalidOperationException("找不到这个标签。");
        var name = label["name"]?.ToString() ?? ""; var parentId = label["parentID"]?.ToString();
        foreach (var child in inventory.Labels.OfType<JsonObject>().Where(item => InventoryDocument.IdEquals(item["parentID"]?.ToString(), id))) child["parentID"] = parentId;
        inventory.Labels.Remove(label);
        foreach (var gear in inventory.Gear()) gear.Tags = RemoveTag(gear.Tags, name);
        foreach (var template in inventory.Templates.OfType<JsonObject>())
            if (template["gear"] is JsonObject node) node["tags"] = RemoveTag(node["tags"]?.ToString() ?? "", name);
    }

    public static void SaveTemplate(InventoryDocument inventory, JsonObject template)
    {
        var id = InventoryDocument.NormalizeId(template["id"]?.ToString()) ?? Guid.NewGuid().ToString("D").ToUpperInvariant();
        if (string.IsNullOrWhiteSpace(template["name"]?.ToString())) throw new InvalidDataException("模板名称不能为空。");
        if (template["gear"] is not JsonObject gear || string.IsNullOrWhiteSpace(gear["name"]?.ToString())) throw new InvalidDataException("模板需要有效的装备资料。");
        if (template["extras"] is not JsonObject) template["extras"] = new JsonObject();
        template["id"] = id;
        for (var index = inventory.Templates.Count - 1; index >= 0; index--)
            if (InventoryDocument.IdEquals((inventory.Templates[index] as JsonObject)?["id"]?.ToString(), id)) inventory.Templates.RemoveAt(index);
        inventory.Templates.Add((JsonObject)template.DeepClone());
    }

    public static void RemoveTemplate(InventoryDocument inventory, string id)
    {
        var removed = false;
        for (var index = inventory.Templates.Count - 1; index >= 0; index--)
            if (InventoryDocument.IdEquals((inventory.Templates[index] as JsonObject)?["id"]?.ToString(), id)) { inventory.Templates.RemoveAt(index); removed = true; }
        if (!removed) throw new InvalidOperationException("找不到这个装备模板。");
    }

    public static GearRecord CreateFromTemplate(InventoryDocument inventory, string id)
    {
        var template = inventory.Templates.OfType<JsonObject>().FirstOrDefault(item => InventoryDocument.IdEquals(item["id"]?.ToString(), id))
            ?? throw new InvalidOperationException("找不到这个装备模板。");
        var gearNode = (JsonObject)template["gear"]!.DeepClone();
        var gearId = Guid.NewGuid().ToString("D").ToUpperInvariant(); gearNode["id"] = gearId; gearNode["trashed"] = false; gearNode["location"] = "";
        var extras = template["extras"] is JsonObject extrasNode ? (JsonObject)extrasNode.DeepClone() : new JsonObject();
        extras["assetID"] = 0; extras["parentID"] = null; extras["locationOverrideID"] = null; extras["isLocation"] = false;
        extras["importRef"] = gearId;
        inventory.GearNodes.Add(gearNode); inventory.Details[gearId] = extras;
        return new GearRecord(gearNode, new GearExtrasRecord(extras));
    }

    private static string RenameTag(string tags, string oldName, string newName) => string.Join(", ", tags.Split(',').Select(item => item.Trim()).Select(item => item == oldName ? newName : item).Where(item => item.Length > 0));
    private static string RemoveTag(string tags, string name) => string.Join(", ", tags.Split(',').Select(item => item.Trim()).Where(item => item.Length > 0 && item != name));
}
