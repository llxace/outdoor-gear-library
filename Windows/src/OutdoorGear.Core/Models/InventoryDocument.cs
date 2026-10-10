using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using OutdoorGear.Core.Services;

namespace OutdoorGear.Core.Models;

public sealed class InventoryDocument
{
    public const int CurrentSchema = 9;
    public static readonly string[] OutdoorCategories = ["背包与收纳", "帐篷与睡眠", "服装与配饰", "鞋袜与行走", "炊具与饮水", "照明与电子", "工具与急救", "洗漱与杂项"];
    public JsonObject Root { get; }
    public int Version => Int(Root["version"]);
    public JsonArray GearNodes => EnsureArray(Root, "gear");
    public JsonArray PackingNodes => EnsureArray(Root, "packingItems");
    public JsonArray BorrowedNodes => EnsureArray(Root, "borrowedPackingItems");
    public JsonArray HikeNodes => EnsureArray(Root, "hikeHistory");
    public JsonArray Categories => EnsureArray(Root, "categories");
    public JsonObject Details => EnsureObject(Root, "details");
    public JsonArray Favorites => EnsureArray(Root, "favoriteGearIDs");
    public JsonArray Locations => EnsureArray(Root, "locations");
    public JsonArray Labels => EnsureArray(Root, "labels");
    public JsonArray Templates => EnsureArray(Root, "templates");
    public JsonObject Settings => EnsureObject(Root, "settings");
    public JsonObject MealPlan => EnsureObject(Root, "mealPlan");

    public InventoryDocument(JsonObject root)
    {
        Root = root;
        Normalize();
    }

    public static InventoryDocument Empty()
    {
        var root = new JsonObject { ["version"] = CurrentSchema, ["gear"] = new JsonArray(), ["categories"] = new JsonArray() };
        return new InventoryDocument(root);
    }

    public static InventoryDocument Parse(string json)
    {
        var root = JsonNode.Parse(json) as JsonObject ?? throw new InvalidDataException("装备库 JSON 顶层格式错误。 ");
        var schema = Int(root["version"]);
        if (schema is < 1 or > CurrentSchema) throw new InvalidDataException($"不支持的装备库数据版本：{schema}。原文件未修改。");
        var document = new InventoryDocument(root);
        if (schema == 1) document.MigrateVersionOne();
        document.OrganizeCategories();
        document.Root["version"] = CurrentSchema;
        return document;
    }

    public IEnumerable<GearRecord> Gear(bool includeTrashed = true) => GearNodes.OfType<JsonObject>()
        .Select(node => new GearRecord(node, Extras(node["id"]?.ToString())))
        .Where(gear => includeTrashed || !gear.Trashed);

    public GearExtrasRecord Extras(string? id)
    {
        var key = NormalizeId(id);
        if (key is null) return new GearExtrasRecord(new JsonObject());
        if (Details[key] is not JsonObject value) Details[key] = value = new JsonObject();
        return new GearExtrasRecord(value);
    }

    public GearRecord? FindGear(string? id) => Gear().FirstOrDefault(g => IdEquals(g.Id, id));
    public bool IsFavorite(string? id) => Favorites.Any(node => IdEquals(node?.ToString(), id));

    public void Normalize()
    {
        _ = GearNodes; _ = PackingNodes; _ = BorrowedNodes; _ = HikeNodes; _ = Categories; _ = Details;
        _ = Favorites; _ = Locations; _ = Labels; _ = Templates; _ = Settings; _ = MealPlan;
        if (Categories.Count == 0) foreach (var category in OutdoorCategories) Categories.Add(category);
        Root["version"] = CurrentSchema;
    }

    private void MigrateVersionOne()
    {
        if (Labels.Count == 0) foreach (var category in Categories.Select(node => node?.ToString() ?? "")) Labels.Add(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["name"] = category, ["color"] = "绿色", ["description"] = "" });
        foreach (var name in Locations.Select(node => node?.ToString() ?? "").Where(name => name.Length > 0))
        {
            if (Gear().Any(item => item.IsLocation && item.Name == name)) continue;
            var location = GearService.Create(this, name, "位置"); location.Extras.IsLocation = true; location.Extras.ImportRef = location.Id!;
        }
        foreach (var gear in Gear())
        {
            if (gear.Extras.AssetId == 0) gear.Extras.AssetId = Gear().Max(item => item.Extras.AssetId) + 1;
            if (gear.Extras.ImportRef.Length == 0) gear.Extras.ImportRef = gear.Id!;
            if (!gear.IsLocation && gear.Extras.ParentId is null && gear.Location.Length > 0)
                gear.Extras.ParentId = Gear().FirstOrDefault(item => item.IsLocation && item.Name == gear.Location)?.Id;
        }
    }

    private void OrganizeCategories()
    {
        Categories.Clear(); foreach (var category in OutdoorCategories) Categories.Add(category);
        foreach (var gear in Gear())
        {
            if (gear.IsLocation) { gear.Category = "位置"; continue; }
            var source = gear.Category.Trim();
            gear.Category = source switch
            {
                "背包" or "登山包" or "收纳包" or "防水袋" or "腰包" or "压缩袋" => OutdoorCategories[0],
                "帐篷" or "防潮垫" or "睡袋" or "睡袋内胆" or "地布" or "枕头" or "天幕" => OutdoorCategories[1],
                "服装" or "硬壳/冲锋衣" or "贴身层" or "抓绒" or "徒步裤" or "保暖层" or "眼部防护" or "遮阳帽" or "硬壳/防水裤" or "雨衣" or "防晒面罩" or "速干长袖" or "针织帽" or "手套" or "防晒外壳" => OutdoorCategories[2],
                "鞋袜" or "雪套" or "徒步鞋" or "重装徒步鞋" or "登山杖" or "袜子" or "冰爪" => OutdoorCategories[3],
                "炊具" or "饮水" or "水壶" or "水袋" or "滤水器" or "炉头" or "锅具" or "餐具" or "燃料" => OutdoorCategories[4],
                "照明" or "头灯" or "营灯" or "手机云台" or "充电宝" or "电池" or "Electronics" or "IOT" => OutdoorCategories[5],
                "应急毯" or "急救包" or "维修工具" or "刀具" or "导航" or "指南针" or "卫星通信" => OutdoorCategories[6],
                _ => OutdoorCategories.Contains(source) ? source : OutdoorCategories[7]
            };
        }
    }

    public void Validate()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var assets = new HashSet<int>();
        ValidateGear(seen, assets);
        ValidatePacking();
        ValidateBorrowed();
        ValidateMeals();
        ValidateHikes();
    }

    private void ValidateGear(HashSet<string> seen, HashSet<int> assets)
    {
        foreach (var item in Gear())
        {
            if (item.Id is null || !Guid.TryParse(item.Id, out _) || !seen.Add(item.Id)) throw new InvalidDataException("装备 ID 缺失或重复。");
            if (string.IsNullOrWhiteSpace(item.Name) || !double.IsFinite(item.Weight) || item.Weight < 0 || !double.IsFinite(item.Quantity) || item.Quantity <= 0)
                throw new InvalidDataException($"装备“{item.Name}”包含无效名称、数量或重量。");
            if (!double.IsFinite(item.PurchasePrice) || item.PurchasePrice < 0) throw new InvalidDataException($"装备“{item.Name}”购买价格无效。");
            if (item.Extras.AssetId < 0 || (item.Extras.AssetId > 0 && !assets.Add(item.Extras.AssetId))) throw new InvalidDataException("装备资产编号为负数或重复。");
            if (item.Extras.ParentId is { } parent)
            {
                if (!seen.Contains(parent) && FindGear(parent) is null || IdEquals(item.Id, parent)) throw new InvalidDataException("装备父子关系引用无效。");
                if (item.IsLocation && !Extras(parent).IsLocation) throw new InvalidDataException("存储位置只能放在其他存储位置下。");
                if (!GearService.CanSetParent(this, item.Id, parent)) throw new InvalidDataException("装备层级不能形成循环。");
            }
            if (item.Extras.LocationOverrideId is { } location && (FindGear(location) is not { IsLocation: true })) throw new InvalidDataException("装备指定的存放位置无效。");
        }
    }

    private void ValidatePacking()
    {
        var packingIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in PackingNodes.OfType<JsonObject>())
        {
            if (!Guid.TryParse(item["sourceGearID"]?.ToString(), out _)) throw new InvalidDataException("打包清单中包含无效装备引用。");
            var source = NormalizeId(item["sourceGearID"]?.ToString())!;
            if (!packingIds.Add(source)) throw new InvalidDataException("同一件装备在打包清单中重复。");
            var gear = FindGear(source); if (gear is null) throw new InvalidDataException("打包清单引用了不存在的装备。");
            var count = Number(item["quantity"], 0);
            if (!double.IsFinite(count) || count <= 0) throw new InvalidDataException("打包数量必须大于 0。");
            if (count > gear.Quantity || gear.Status == "损坏" || gear.Trashed) throw new InvalidDataException("打包数量超过库存或装备不可用。");
        }
    }

    private void ValidateBorrowed()
    {
        if (BorrowedNodes.OfType<JsonObject>().Any(item => !InventoryDocument.Bool(item["unavailable"]) && (item["gear"] is not JsonObject gear || InventoryDocument.Number(item["quantity"]) <= 0 || InventoryDocument.Number(item["quantity"]) > InventoryDocument.Number(gear["quantity"]) || gear["status"]?.ToString() == "损坏"))) throw new InvalidDataException("借用装备数量或状态无效。");
    }

    private void ValidateMeals()
    {
        if (MealPlan["foods"] is JsonArray foods && foods.OfType<JsonObject>().Any(food => string.IsNullOrWhiteSpace(food["name"]?.ToString()) || InventoryDocument.Int(food["day"], 1) < 1 || InventoryDocument.Int(food["day"], 1) > InventoryDocument.Int(MealPlan["days"], 1) || InventoryDocument.Number(food["quantity"]) <= 0 || new[] { "grams", "calories", "price" }.Any(key => !double.IsFinite(InventoryDocument.Number(food[key])) || InventoryDocument.Number(food[key]) < 0))) throw new InvalidDataException("路餐项目包含无效日期或数值。");
    }

    private void ValidateHikes()
    {
        if (HikeNodes.OfType<JsonObject>().Any(hike => !InventoryDocument.Bool(hike["deleted"]) && string.IsNullOrWhiteSpace(hike["title"]?.ToString()))) throw new InvalidDataException("徒步记录标题不能为空。");
    }

    public string Serialize() => Root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });

    public static JsonArray EnsureArray(JsonObject node, string key)
    {
        if (node[key] is not JsonArray array) node[key] = array = new JsonArray();
        return array;
    }

    public static JsonObject EnsureObject(JsonObject node, string key)
    {
        if (node[key] is not JsonObject value) node[key] = value = new JsonObject();
        return value;
    }

    public static int Int(JsonNode? node, int fallback = 0) => int.TryParse(node?.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) ? value : fallback;
    public static long Int64(JsonNode? node, long fallback = 0) => long.TryParse(node?.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) ? value : fallback;
    public static double Number(JsonNode? node, double fallback = 0) => double.TryParse(node?.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ? value : fallback;
    public static bool Bool(JsonNode? node, bool fallback = false) => bool.TryParse(node?.ToString(), out var value) ? value : fallback;
    public static string? NormalizeId(string? id) => Guid.TryParse(id, out var value) ? value.ToString("D").ToUpperInvariant() : null;
    public static bool IdEquals(string? a, string? b) => Guid.TryParse(a, out var first) && Guid.TryParse(b, out var second) && first == second;
}

public sealed class GearRecord(JsonObject node, GearExtrasRecord extras)
{
    public JsonObject Node { get; } = node;
    public GearExtrasRecord Extras { get; } = extras;
    public string? Id => InventoryDocument.NormalizeId(Node["id"]?.ToString());
    public string Name { get => Node["name"]?.ToString() ?? ""; set => Node["name"] = value; }
    public string Brand { get => Node["brand"]?.ToString() ?? ""; set => Node["brand"] = value; }
    public string Model { get => Node["model"]?.ToString() ?? ""; set => Node["model"] = value; }
    public string Category { get => Node["category"]?.ToString() ?? "洗漱与杂项"; set => Node["category"] = value; }
    public string Location { get => Node["location"]?.ToString() ?? ""; set => Node["location"] = value; }
    public string Status { get => Node["status"]?.ToString() ?? "可用"; set => Node["status"] = value; }
    public string Notes { get => Node["notes"]?.ToString() ?? ""; set => Node["notes"] = value; }
    public string PurchaseFrom { get => Node["purchaseFrom"]?.ToString() ?? ""; set => Node["purchaseFrom"] = value; }
    public string PurchaseDate { get => Node["purchaseDate"]?.ToString() ?? ""; set => Node["purchaseDate"] = value; }
    public string Tags { get => Node["tags"]?.ToString() ?? ""; set => Node["tags"] = value; }
    public string? Photo { get => Node["photo"]?.ToString(); set => Node["photo"] = value; }
    public double Quantity { get => InventoryDocument.Number(Node["quantity"], 1); set => Node["quantity"] = value; }
    public double Weight { get => InventoryDocument.Number(Node["weight"]); set => Node["weight"] = value; }
    public double PurchasePrice { get => InventoryDocument.Number(Node["purchasePrice"]); set => Node["purchasePrice"] = value; }
    public bool Trashed { get => InventoryDocument.Bool(Node["trashed"]); set => Node["trashed"] = value; }
    public bool IsLocation => Extras.IsLocation;
    public string SearchText => string.Join(' ', Name, Brand, Model, Category, Location, Notes, Tags, Extras.AssetId.ToString(CultureInfo.InvariantCulture), Extras.Description, Extras.ImportRef);
}

public sealed class GearExtrasRecord(JsonObject node)
{
    public JsonObject Node { get; } = node;
    public bool IsLocation { get => InventoryDocument.Bool(Node["isLocation"]); set => Node["isLocation"] = value; }
    public int AssetId { get => InventoryDocument.Int(Node["assetID"]); set => Node["assetID"] = value; }
    public string Description { get => Node["description"]?.ToString() ?? ""; set => Node["description"] = value; }
    public string ImportRef { get => Node["importRef"]?.ToString() ?? ""; set => Node["importRef"] = value; }
    public string? Subcategory { get => Node["subcategory"]?.ToString(); set => Node["subcategory"] = value; }
    public string? ParentId { get => InventoryDocument.NormalizeId(Node["parentID"]?.ToString()); set => Node["parentID"] = value; }
    public string? LocationOverrideId { get => InventoryDocument.NormalizeId(Node["locationOverrideID"]?.ToString()); set => Node["locationOverrideID"] = value; }
    public JsonArray Attachments => InventoryDocument.EnsureArray(Node, "attachments");
}
