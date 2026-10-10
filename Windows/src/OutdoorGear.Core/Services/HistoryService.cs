using System.Globalization;
using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public static class HistoryService
{
    private static readonly DateTime SwiftEpoch = new(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    public static double ToSwiftDate(DateTime date) => (date.ToUniversalTime() - SwiftEpoch).TotalSeconds;

    public static DateTime FromSwiftDate(JsonNode? node)
    {
        if (double.TryParse(node?.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds) && double.IsFinite(seconds))
            return SwiftEpoch.AddSeconds(seconds).ToLocalTime();
        if (DateTime.TryParse(node?.ToString(), CultureInfo.CurrentCulture, DateTimeStyles.AssumeLocal, out var legacy)) return legacy;
        return DateTime.Today;
    }

    public static void Save(InventoryDocument inventory, JsonObject record)
    {
        var id = InventoryDocument.NormalizeId(record["id"]?.ToString());
        if (id is null) throw new InvalidDataException("徒步记录 ID 无效。");
        record["id"] = id;
        if (string.IsNullOrWhiteSpace(record["title"]?.ToString())) throw new InvalidDataException("记录标题不能为空。");
        var seconds = InventoryDocument.Number(record["date"], double.NaN);
        if (!double.IsFinite(seconds) || seconds < -62135596800d || seconds > 253402300799d) throw new InvalidDataException("徒步日期无效。");
        var gear = InventoryDocument.EnsureArray(record, "gear");
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in gear.OfType<JsonObject>())
        {
            if (InventoryDocument.NormalizeId(item["id"]?.ToString()) is not { } itemId || !ids.Add(itemId)) throw new InvalidDataException("当次装备包含无效或重复 ID。");
            item["id"] = itemId;
            var snapshot = item["gear"] as JsonObject ?? throw new InvalidDataException("当次装备快照缺少装备资料。");
            if (string.IsNullOrWhiteSpace(snapshot["name"]?.ToString())) throw new InvalidDataException("当次装备名称不能为空。");
            var weight = InventoryDocument.Number(snapshot["weight"], double.NaN);
            var quantity = InventoryDocument.Number(item["quantity"], double.NaN);
            if (!double.IsFinite(weight) || weight < 0 || !double.IsFinite(quantity) || quantity <= 0) throw new InvalidDataException("当次装备重量或数量无效。");
        }

        var records = inventory.HikeNodes;
        for (var index = records.Count - 1; index >= 0; index--)
            if (InventoryDocument.IdEquals((records[index] as JsonObject)?["id"]?.ToString(), id)) records.RemoveAt(index);
        records.Add((JsonObject)record.DeepClone());
    }

    public static void SetDeleted(InventoryDocument inventory, string id, bool deleted)
    {
        var record = inventory.HikeNodes.OfType<JsonObject>().FirstOrDefault(item => InventoryDocument.IdEquals(item["id"]?.ToString(), id))
            ?? throw new InvalidOperationException("找不到这条徒步记录。");
        record["deleted"] = deleted;
    }

    public static JsonObject FromPacking(InventoryDocument inventory)
    {
        var gear = new JsonArray();
        foreach (var item in inventory.PackingNodes.OfType<JsonObject>())
        {
            var source = inventory.FindGear(item["sourceGearID"]?.ToString());
            if (source is null) continue;
            gear.Add(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["gear"] = source.Node.DeepClone(), ["quantity"] = InventoryDocument.Number(item["quantity"], 1) });
        }
        foreach (var item in inventory.BorrowedNodes.OfType<JsonObject>().Where(item => !InventoryDocument.Bool(item["unavailable"])))
            if (item["gear"] is JsonObject snapshot)
                gear.Add(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["gear"] = snapshot.DeepClone(), ["quantity"] = InventoryDocument.Number(item["quantity"], 1), ["ownerName"] = item["ownerName"]?.DeepClone() });

        var route = inventory.Root["selectedRoute"]?.DeepClone();
        var routeName = (route as JsonObject)?["name"]?.ToString() ?? "";
        return new JsonObject
        {
            ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(),
            ["title"] = string.IsNullOrWhiteSpace(routeName) ? "徒步记录" : routeName,
            ["date"] = ToSwiftDate(DateTime.Today),
            ["routeName"] = routeName,
            ["distance"] = (route as JsonObject)?["distance"]?.DeepClone(),
            ["notes"] = "",
            ["route"] = route,
            ["gear"] = gear,
            ["mealPlan"] = inventory.MealPlan.DeepClone(),
            ["deleted"] = false
        };
    }
}
