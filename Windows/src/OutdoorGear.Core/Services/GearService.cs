using System.Text.Json.Nodes;
using System.Globalization;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public static class GearService
{
    public static int EnsureIdentifiers(InventoryDocument inventory)
    {
        var nextId = inventory.Details
            .Select(pair => InventoryDocument.Int(pair.Value?["assetID"]))
            .DefaultIfEmpty()
            .Max();
        var changed = 0;
        foreach (var gear in inventory.Gear())
        {
            if (gear.Extras.AssetId == 0)
            {
                gear.Extras.AssetId = ++nextId;
                changed++;
            }
            if (!string.IsNullOrWhiteSpace(gear.Extras.ImportRef))
                continue;
            gear.Extras.ImportRef = gear.Id ?? "";
            changed++;
        }
        return changed;
    }

    public static int NormalizePurchaseDates(InventoryDocument inventory)
    {
        var changed = 0;
        foreach (var gear in inventory.Gear())
        {
            var normalized = NormalizePurchaseDate(gear.PurchaseDate);
            if (normalized == gear.PurchaseDate)
                continue;
            gear.PurchaseDate = normalized;
            changed++;
        }
        return changed;
    }

    private static string NormalizePurchaseDate(string value)
    {
        if (value.Length < 10)
            return value;
        var date = value[..10];
        return DateTime.TryParseExact(
            date,
            "yyyy-MM-dd",
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out _)
            ? date
            : value;
    }

    public static int ChangeRecords(InventoryDocument inventory, IEnumerable<string> selectedIds, string? status = null, bool? trashed = null)
    {
        var roots = selectedIds.Select(InventoryDocument.NormalizeId).ToList();
        if (roots.Count == 0 || roots.Any(id => id is null) || roots.Distinct(StringComparer.OrdinalIgnoreCase).Count() != roots.Count)
            throw new InvalidDataException("请选择有效且不重复的装备记录。");
        if (roots.Any(id => inventory.FindGear(id) is not { IsLocation: false })) throw new InvalidOperationException("选择中包含已不存在或非装备记录。");
        if (status is not null && !new[] { "可用", "想买", "借出", "损坏", "已出售" }.Contains(status)) throw new InvalidDataException("请选择有效状态。");

        var rootIds = roots.Cast<string>().ToList();
        var targets = trashed is null ? rootIds.ToHashSet(StringComparer.OrdinalIgnoreCase) : rootIds.Concat(rootIds.SelectMany(id => Descendants(inventory, id)).Select(item => item.Id!)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var gear in inventory.Gear())
        {
            if (gear.Id is not { } id || !targets.Contains(id)) continue;
            if (status is not null && rootIds.Contains(id, StringComparer.OrdinalIgnoreCase)) gear.Status = status;
            if (trashed is not null) gear.Trashed = trashed.Value;
        }
        return targets.Count;
    }

    public static GearRecord Create(InventoryDocument inventory, string name, string category, string? parentId = null)
    {
        if (string.IsNullOrWhiteSpace(name)) throw new ArgumentException("装备名称不能为空。");
        if (!InventoryDocument.OutdoorCategories.Contains(category) && category != "位置") throw new ArgumentException("请选择有效分类。");
        if (parentId is not null && inventory.FindGear(parentId) is null) throw new InvalidOperationException("上级装备不存在。");
        var id = Guid.NewGuid().ToString("D").ToUpperInvariant();
        var node = new JsonObject { ["id"] = id, ["name"] = name.Trim(), ["brand"] = "", ["model"] = "", ["category"] = category, ["location"] = "", ["quantity"] = 1, ["weight"] = 0, ["status"] = "可用", ["purchasePrice"] = 0, ["purchaseFrom"] = "", ["purchaseDate"] = "", ["tags"] = "", ["notes"] = "", ["trashed"] = false };
        inventory.GearNodes.Add(node);
        var extras = inventory.Extras(id); extras.IsLocation = category == "位置"; extras.ParentId = parentId;
        return new GearRecord(node, extras);
    }

    public static void Save(InventoryDocument inventory, GearRecord item)
    {
        if (string.IsNullOrWhiteSpace(item.Name) || !double.IsFinite(item.Quantity) || item.Quantity <= 0 || !double.IsFinite(item.Weight) || item.Weight < 0 || !double.IsFinite(item.PurchasePrice) || item.PurchasePrice < 0)
            throw new InvalidDataException("装备名称、数量、重量或价格无效。");
        if (item.Id is null || inventory.FindGear(item.Id) is null) throw new InvalidOperationException("装备已不存在。");
        if (item.Extras.ParentId is { } parent && !CanSetParent(inventory, item.Id!, parent)) throw new InvalidOperationException("上级关系会形成循环或引用无效装备。");
        if (item.Extras.AssetId < 0) throw new InvalidDataException("资产编号不能为负数。");
        if (item.Extras.AssetId == 0 && InventoryDocument.Bool(inventory.Settings["autoAssetID"], true))
            item.Extras.AssetId = inventory.Details.Select(pair => InventoryDocument.Int(pair.Value?["assetID"])).DefaultIfEmpty().Max() + 1;
        if (item.Extras.AssetId > 0 && inventory.Details.Any(pair => !InventoryDocument.IdEquals(pair.Key, item.Id) && InventoryDocument.Int(pair.Value?["assetID"]) == item.Extras.AssetId))
            throw new InvalidDataException("资产编号已被其他装备使用。");
        item.Extras.IsLocation = item.Category == "位置";
        foreach (var name in item.Tags.Split(',').Select(tag => tag.Trim()).Where(tag => tag.Length > 0))
            if (!inventory.Labels.OfType<JsonObject>().Any(label => label["name"]?.ToString() == name))
                inventory.Labels.Add(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["name"] = name, ["description"] = "", ["color"] = "绿色" });
    }

    public static bool CanSetParent(InventoryDocument inventory, string childId, string parentId)
    {
        if (InventoryDocument.IdEquals(childId, parentId) || inventory.FindGear(parentId) is null) return false;
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { childId };
        var current = parentId;
        while (current is not null)
        {
            if (!visited.Add(current)) return false;
            current = inventory.Extras(current).ParentId!;
        }
        return true;
    }

    public static IReadOnlyList<GearRecord> Children(InventoryDocument inventory, string parentId) => inventory.Gear(false).Where(g => InventoryDocument.IdEquals(g.Extras.ParentId, parentId)).ToList();

    public static IReadOnlyList<GearRecord> Descendants(InventoryDocument inventory, string parentId)
    {
        var output = new List<GearRecord>(); var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { parentId }; var frontier = new Queue<string>(); frontier.Enqueue(parentId);
        while (frontier.TryDequeue(out var parent)) foreach (var child in inventory.Gear().Where(item => InventoryDocument.IdEquals(item.Extras.ParentId, parent))) if (child.Id is { } id && seen.Add(id)) { output.Add(child); frontier.Enqueue(id); }
        return output;
    }

    public static void SetTrashed(InventoryDocument inventory, IEnumerable<string> ids, bool trashed)
    {
        var roots = ids.Select(InventoryDocument.NormalizeId).Where(x => x is not null).Cast<string>().Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        var targets = new HashSet<string>(roots, StringComparer.OrdinalIgnoreCase);
        foreach (var id in roots) foreach (var child in Descendants(inventory, id)) if (child.Id is { } childId) targets.Add(childId);
        foreach (var gear in inventory.Gear()) if (gear.Id is { } id && targets.Contains(id)) gear.Trashed = trashed;
    }

    public static void DeletePermanently(InventoryDocument inventory, IEnumerable<string> ids)
    {
        var targets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var id in ids.Select(InventoryDocument.NormalizeId).Where(x => x is not null).Cast<string>()) { targets.Add(id); foreach (var child in Descendants(inventory, id)) if (child.Id is { } childId) targets.Add(childId); }
        for (var i = inventory.GearNodes.Count - 1; i >= 0; i--) if (inventory.GearNodes[i] is JsonObject node && targets.Contains(InventoryDocument.NormalizeId(node["id"]?.ToString()) ?? "")) inventory.GearNodes.RemoveAt(i);
        foreach (var key in inventory.Details.Select(kv => kv.Key).Where(key => targets.Contains(InventoryDocument.NormalizeId(key) ?? "")).ToList()) inventory.Details.Remove(key);
        for (var i = inventory.Favorites.Count - 1; i >= 0; i--) if (targets.Contains(InventoryDocument.NormalizeId(inventory.Favorites[i]?.ToString()) ?? "")) inventory.Favorites.RemoveAt(i);
        for (var i = inventory.PackingNodes.Count - 1; i >= 0; i--) if (inventory.PackingNodes[i] is JsonObject n && targets.Contains(InventoryDocument.NormalizeId(n["sourceGearID"]?.ToString()) ?? "")) inventory.PackingNodes.RemoveAt(i);
    }

    public static void ToggleFavorite(InventoryDocument inventory, string id)
    {
        if (inventory.FindGear(id) is null) throw new InvalidOperationException("装备不存在。");
        var existing = inventory.Favorites.Select(x => x?.ToString()).FirstOrDefault(x => InventoryDocument.IdEquals(x, id));
        if (existing is not null)
        {
            for (var i = inventory.Favorites.Count - 1; i >= 0; i--)
                if (InventoryDocument.IdEquals(inventory.Favorites[i]?.ToString(), id)) inventory.Favorites.RemoveAt(i);
        }
        else inventory.Favorites.Add(InventoryDocument.NormalizeId(id));
    }

    public static GearRecord Duplicate(InventoryDocument inventory, string id, bool copyAttachments = true, string prefix = "副本 · ")
    {
        var original = inventory.FindGear(id) ?? throw new InvalidOperationException("装备不存在。");
        var clone = (JsonObject)original.Node.DeepClone();
        var newId = Guid.NewGuid().ToString("D").ToUpperInvariant();
        clone["id"] = newId; clone["name"] = prefix + original.Name; clone["trashed"] = false;
        if (!copyAttachments) clone["photo"] = null;
        inventory.GearNodes.Add(clone);
        var extras = (JsonObject)original.Extras.Node.DeepClone();
        extras["assetID"] = 0; extras["importRef"] = "";
        if (extras["attachments"] is JsonArray attachments)
            foreach (var attachment in attachments.OfType<JsonObject>())
                if (copyAttachments) attachment["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant();
        if (!copyAttachments) extras["attachments"] = new JsonArray();
        inventory.Details[newId] = extras;
        return new GearRecord(clone, new GearExtrasRecord(extras));
    }

    public static IEnumerable<GearRecord> Search(InventoryDocument inventory, string query, string? category = null, bool includeTrashed = false)
    {
        var normalized = query.Trim(); return inventory.Gear().Where(g => (includeTrashed || !g.Trashed) && (category is null || g.Category == category) && (normalized.Length == 0 || g.SearchText.Contains(normalized, StringComparison.CurrentCultureIgnoreCase)));
    }

    public static string Subcategory(GearRecord gear)
    {
        var stored = gear.Extras.Subcategory;
        var allowed = gear.Category switch { "帐篷与睡眠" => new[] { "帐篷", "睡袋", "防潮垫与睡眠配件" }, "鞋袜与行走" => new[] { "鞋", "袜子", "行走配件" }, "服装与配饰" => new[] { "贴身与速干", "抓绒与中层", "羽绒与棉服", "防风与雨衣", "裤装", "帽子与头巾", "手套", "眼镜与面罩", "其他服装" }, _ => Array.Empty<string>() };
        if (stored is not null && allowed.Contains(stored)) return stored;
        var text = (gear.Name + " " + gear.Model).ToLowerInvariant();
        if (gear.Category == "帐篷与睡眠") return text.Contains("帐篷") || text.Contains("天幕") || text.Contains("tent") ? "帐篷" : text.Contains("睡袋") || text.Contains("sleeping bag") ? "睡袋" : "防潮垫与睡眠配件";
        if (gear.Category == "鞋袜与行走") return text.Contains("袜") || text.Contains("sock") ? "袜子" : text.Contains("鞋") || text.Contains("靴") || text.Contains("shoe") || text.Contains("boot") ? "鞋" : "行走配件";
        if (gear.Category != "服装与配饰") return "";
        if (Has("手套", "glove", "mitten")) return "手套";
        if (Has("风镜", "眼镜", "面罩", "护目", "goggle", "sunglass", "mask")) return "眼镜与面罩";
        if (Has("围巾", "头巾", "脖套", "beanie", "brimmer", "scarf", "buff") || (Has("帽", "hat") && !Has("外套", "夹克", "衣", "jacket", "coat", "hoodie"))) return "帽子与头巾";
        if (Has("内裤", "内衣", "贴身", "dotknit", "base layer", "underwear")) return "贴身与速干";
        if (Has("裤", "pant", "trouser")) return "裤装";
        if (Has("羽绒", "棉服", "棉衣", "化纤保暖", "ventrix", "50/50", "cloud down", "parka", "down jacket", "insulated")) return "羽绒与棉服";
        if (Has("抓绒", "fleece", "polartec")) return "抓绒与中层";
        if (Has("硬壳", "冲锋衣", "雨衣", "防晒外套", "防晒外壳", "防风", "futurelight", "sangro", "shell", "rain jacket", "windbreaker")) return "防风与雨衣";
        if (Has("速干", "美利奴", "长袖t", "t恤", "短袖", "merino", "tee", "t-shirt")) return "贴身与速干";
        return "其他服装";
        bool Has(params string[] words) => words.Any(text.Contains);
    }
}
