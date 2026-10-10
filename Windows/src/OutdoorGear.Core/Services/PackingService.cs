using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public sealed record PackingUndo(JsonArray Own, JsonArray Borrowed);
public sealed record PackingSummary(double WeightGrams, double GearCost, int ItemCount, int FoodCount, double WaterLiters, int MissingPriceCount);

public static class PackingService
{
    public static void SetOwnQuantity(InventoryDocument inventory, string gearId, double? quantity)
    {
        var gear = inventory.FindGear(gearId) ?? throw new InvalidOperationException("这件装备不在当前装备库中。");
        if (gear.Trashed) throw new InvalidOperationException("回收站中的装备不能加入打包清单。");
        if (quantity is not null)
        {
            if (gear.Status == "损坏") throw new InvalidOperationException("已损坏的装备不能加入打包清单。");
            if (!double.IsFinite(quantity.Value) || quantity <= 0) throw new InvalidOperationException("携带数量须大于 0。");
            if (quantity > gear.Quantity) throw new InvalidOperationException($"“{gear.Name}”录入了 {gear.Quantity:0.##} 件，携带数量不能超过这个数量。");
        }
        Remove(inventory.PackingNodes, node => InventoryDocument.IdEquals(node["sourceGearID"]?.ToString(), gearId));
        if (quantity is null) return;
        inventory.PackingNodes.Add(new JsonObject { ["id"] = NewId(), ["quantity"] = quantity.Value, ["sourceGearID"] = gear.Id });
    }

    public static void SetBorrowedQuantity(InventoryDocument inventory, string ownerId, string ownerName, JsonObject gearSnapshot, double? quantity, string? subcategory = null)
    {
        var gear = new GearRecord(gearSnapshot, new GearExtrasRecord(new JsonObject()));
        if (quantity is not null)
        {
            if (gear.Status == "损坏") throw new InvalidOperationException("已损坏的装备不能加入打包清单。");
            if (!double.IsFinite(quantity.Value) || quantity <= 0 || quantity > gear.Quantity) throw new InvalidOperationException("携带数量不能超过来源库的库存数量。");
        }
        Remove(inventory.BorrowedNodes, node => InventoryDocument.IdEquals(node["ownerID"]?.ToString(), ownerId) && InventoryDocument.IdEquals(node["gear"]?["id"]?.ToString(), gear.Id));
        if (quantity is null) return;
        inventory.BorrowedNodes.Add(new JsonObject { ["id"] = NewId(), ["ownerID"] = InventoryDocument.NormalizeId(ownerId), ["ownerName"] = ownerName, ["gear"] = (JsonObject)gearSnapshot.DeepClone(), ["quantity"] = quantity.Value, ["unavailable"] = false, ["subcategory"] = subcategory });
    }

    public static PackingUndo Clear(InventoryDocument inventory)
    {
        var undo = new PackingUndo(CloneArray(inventory.PackingNodes), CloneArray(inventory.BorrowedNodes));
        inventory.PackingNodes.Clear(); inventory.BorrowedNodes.Clear(); return undo;
    }

    public static void Restore(InventoryDocument inventory, PackingUndo undo)
    {
        foreach (var node in undo.Own.OfType<JsonObject>())
            if (!inventory.PackingNodes.OfType<JsonObject>().Any(current => InventoryDocument.IdEquals(current["sourceGearID"]?.ToString(), node["sourceGearID"]?.ToString()))) inventory.PackingNodes.Add(node.DeepClone());
        foreach (var node in undo.Borrowed.OfType<JsonObject>())
            if (!inventory.BorrowedNodes.OfType<JsonObject>().Any(current => InventoryDocument.IdEquals(current["ownerID"]?.ToString(), node["ownerID"]?.ToString()) && InventoryDocument.IdEquals(current["gear"]?["id"]?.ToString(), node["gear"]?["id"]?.ToString()))) inventory.BorrowedNodes.Add(node.DeepClone());
    }

    public static int RemoveUnavailable(InventoryDocument inventory)
    {
        var valid = inventory.Gear(false).Select(g => g.Id).Where(id => id is not null).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var before = inventory.PackingNodes.Count + inventory.BorrowedNodes.Count;
        Remove(inventory.PackingNodes, item => !valid.Contains(InventoryDocument.NormalizeId(item["sourceGearID"]?.ToString()) ?? ""));
        Remove(inventory.BorrowedNodes, item => InventoryDocument.Bool(item["unavailable"]));
        return before - inventory.PackingNodes.Count - inventory.BorrowedNodes.Count;
    }

    public static PackingSummary Summarize(InventoryDocument inventory)
    {
        var own = SummarizeOwnGear(inventory);
        var borrowed = SummarizeBorrowedGear(inventory);
        var plan = MealService.Summarize(inventory);
        return new PackingSummary(own.Grams + borrowed.Grams + plan.TotalWeightGrams,
            own.Cost + borrowed.Cost, own.Count + borrowed.Count, plan.FoodCount, plan.WaterLiters,
            own.MissingPrices + borrowed.MissingPrices);
    }

    private static (double Grams, double Cost, int Count, int MissingPrices) SummarizeOwnGear(InventoryDocument inventory)
    {
        double grams = 0, cost = 0; var count = 0; var missingPrices = 0;
        foreach (var node in inventory.PackingNodes.OfType<JsonObject>())
        {
            var gear = inventory.FindGear(node["sourceGearID"]?.ToString()); if (gear is null || gear.Trashed || gear.Status == "损坏") continue;
            var quantity = Math.Min(InventoryDocument.Number(node["quantity"]), gear.Quantity);
            grams += gear.Weight * quantity;
            cost += gear.Quantity > 0 ? gear.PurchasePrice / gear.Quantity * quantity : 0;
            if (gear.PurchasePrice == 0) missingPrices++;
            count++;
        }
        return (grams, cost, count, missingPrices);
    }

    private static (double Grams, double Cost, int Count, int MissingPrices) SummarizeBorrowedGear(InventoryDocument inventory)
    {
        double grams = 0, cost = 0; var count = 0; var missingPrices = 0;
        foreach (var node in inventory.BorrowedNodes.OfType<JsonObject>())
        {
            var gearNode = node["gear"] as JsonObject; if (gearNode is null || InventoryDocument.Bool(node["unavailable"])) continue;
            var quantity = Math.Min(InventoryDocument.Number(node["quantity"]), InventoryDocument.Number(gearNode["quantity"]));
            grams += InventoryDocument.Number(gearNode["weight"]) * quantity;
            var stock = InventoryDocument.Number(gearNode["quantity"]);
            cost += stock > 0 ? InventoryDocument.Number(gearNode["purchasePrice"]) / stock * quantity : 0;
            if (InventoryDocument.Number(gearNode["purchasePrice"]) == 0) missingPrices++;
            count++;
        }
        return (grams, cost, count, missingPrices);
    }

    private static JsonArray CloneArray(JsonArray source) { var copy = new JsonArray(); foreach (var node in source) copy.Add(node?.DeepClone()); return copy; }
    private static string NewId() => Guid.NewGuid().ToString("D").ToUpperInvariant();
    private static void Remove(JsonArray array, Func<JsonObject, bool> predicate) { for (var index = array.Count - 1; index >= 0; index--) if (array[index] is JsonObject node && predicate(node)) array.RemoveAt(index); }
}
