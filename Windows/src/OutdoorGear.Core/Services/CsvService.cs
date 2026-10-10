using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public sealed record CsvImportResult(InventoryDocument Inventory, int Added, int Updated, IReadOnlyList<string> Warnings);

public static class CsvService
{
    public static readonly string[] Columns = ["Native.id", "HB.import_ref", "HB.asset_id", "HB.name", "HB.description", "HB.quantity", "HB.is_location", "HB.location", "Native.parent_ref", "HB.label", "HB.model_number", "HB.manufacturer", "HB.notes", "HB.purchase_from", "HB.purchase_price", "HB.purchase_time", "Native.category", "Native.weight_g", "Native.status"];

    public static string Export(InventoryDocument inventory)
    {
        var records = inventory.Gear(false).OrderBy(item => item.IsLocation ? 0 : 1).ThenBy(item => item.Extras.AssetId).ToList();
        var rows = new List<IReadOnlyList<string>> { Columns };
        foreach (var gear in records)
        {
            var parent = gear.Extras.ParentId is { } id ? inventory.FindGear(id) : null;
            var location = gear.IsLocation ? parent?.Name ?? "" : gear.Location;
            rows.Add([gear.Id!, gear.Extras.ImportRef, gear.Extras.AssetId.ToString(CultureInfo.InvariantCulture), gear.Name, gear.Extras.Description, gear.Quantity.ToString("G", CultureInfo.InvariantCulture), gear.IsLocation.ToString().ToLowerInvariant(), location, parent?.Extras.ImportRef ?? "", gear.Tags, gear.Model, gear.Brand, gear.Notes, gear.PurchaseFrom, gear.PurchasePrice.ToString("G", CultureInfo.InvariantCulture), gear.PurchaseDate, gear.Category, gear.Weight.ToString("G", CultureInfo.InvariantCulture), gear.Status]);
        }
        return Encode(rows);
    }

    public static CsvImportResult Merge(string text, InventoryDocument existing)
    {
        var rows = Parse(text, text.Split('\n', '\r').FirstOrDefault()?.Contains('\t') == true ? '\t' : ',');
        ValidateHeaders(rows);
        var batch = new MergeBatch(InventoryDocument.Parse(existing.Serialize()), rows[0]);
        for (var line = 1; line < rows.Count; line++) MergeRow(batch, rows[line], line);
        ApplyParents(batch);
        ValidateAssetIds(batch.Inventory);
        AddMissingLabels(batch.Inventory);
        batch.Inventory.Validate();
        return new CsvImportResult(batch.Inventory, batch.Added, batch.Updated, batch.Warnings);
    }

    private static void ValidateHeaders(IReadOnlyList<IReadOnlyList<string>> rows)
    {
        if (rows.Count == 0 || (!rows[0].Contains("HB.name") && !rows[0].Contains("名称"))) throw new InvalidDataException("缺少 HB.name 或名称列。");
    }

    private static void MergeRow(MergeBatch batch, IReadOnlyList<string> cells, int line)
    {
        if (cells.All(string.IsNullOrEmpty)) return;
        string Value(string first, string? second = null) => ReadValue(batch.Headers, cells, second is null ? [first] : [first, second]);
        var name = Value("HB.name", "名称").Trim();
        if (name.Length == 0) throw new InvalidDataException($"第 {line + 1} 行名称为空。");
        var importRef = Value("HB.import_ref");
        var nativeId = InventoryDocument.NormalizeId(Value("Native.id"));
        var record = FindImportedGear(batch.Inventory, importRef, nativeId);
        var wasExisting = record is not null;
        record ??= GearService.Create(batch.Inventory, name, "洗漱与杂项");
        UpdateGearFields(record, Value, line);
        UpdateGearAssets(batch.Inventory, record, Value("HB.asset_id"), line);
        record.Extras.ImportRef = importRef.Length == 0 ? record.Id! : importRef;
        AddPendingParent(batch, record, Value("Native.parent_ref"));
        UpdateGearLocation(batch.Inventory, record, Value("HB.location", "存放位置"));
        record.Trashed = false;
        GearService.Save(batch.Inventory, record);
        if (wasExisting) batch.Updated++; else batch.Added++;
    }

    private static string ReadValue(IReadOnlyList<string> headers, IReadOnlyList<string> cells, params string[] names)
    {
        foreach (var key in names)
        {
            var index = headers.ToList().IndexOf(key);
            if (index >= 0 && index < cells.Count) return cells[index];
        }
        return "";
    }

    private static GearRecord? FindImportedGear(InventoryDocument inventory, string importRef, string? nativeId) =>
        inventory.Gear().FirstOrDefault(item => (importRef.Length > 0 && item.Extras.ImportRef == importRef) || (nativeId is not null && InventoryDocument.IdEquals(nativeId, item.Id)));

    private static void UpdateGearFields(GearRecord record, Func<string, string?, string> value, int line)
    {
        record.Name = value("HB.name", "名称").Trim();
        record.Brand = value("HB.manufacturer", "品牌"); record.Model = value("HB.model_number", "型号");
        record.Notes = value("HB.notes", "备注"); record.PurchaseFrom = value("HB.purchase_from", "购买渠道");
        record.PurchaseDate = value("HB.purchase_time", "购买日期"); record.Tags = value("HB.label", "标签");
        var category = value("Native.category", "分类"); var status = value("Native.status", "状态");
        record.Category = string.IsNullOrWhiteSpace(category) ? record.Category : category;
        record.Status = string.IsNullOrWhiteSpace(status) ? record.Status : status;
        record.Quantity = Number(value("HB.quantity", "数量"), 1, "数量", line);
        record.Weight = Number(value("Native.weight_g", "单件重量(g)"), 0, "重量", line);
        record.PurchasePrice = Number(value("HB.purchase_price", "购买价格"), 0, "价格", line);
        if (record.Quantity <= 0 || record.Weight < 0 || record.PurchasePrice < 0) throw new InvalidDataException($"第 {line + 1} 行数量或重量/价格无效。");
        record.Extras.Description = value("HB.description", null); record.Extras.IsLocation = ParseFlag(value("HB.is_location", null));
    }

    private static void UpdateGearAssets(InventoryDocument inventory, GearRecord record, string asset, int line)
    {
        asset = asset.Replace("-", "", StringComparison.Ordinal);
        if (asset.Length > 0 && (!int.TryParse(asset, out var assetId) || assetId <= 0)) throw new InvalidDataException($"第 {line + 1} 行资产编号无效。");
        if (asset.Length > 0) record.Extras.AssetId = int.Parse(asset, CultureInfo.InvariantCulture);
        else if (record.Extras.AssetId == 0) record.Extras.AssetId = inventory.Gear().Max(item => item.Extras.AssetId) + 1;
    }

    private static void AddPendingParent(MergeBatch batch, GearRecord record, string parentRef)
    {
        if (parentRef.Length > 0) batch.Pending.Add((record.Id!, parentRef));
    }

    private static void UpdateGearLocation(InventoryDocument inventory, GearRecord record, string location)
    {
        if (location.Length > 0) record.Extras.ParentId = EnsureLocation(inventory, location);
        else if (!record.IsLocation) record.Extras.ParentId = null;
    }

    private static void ApplyParents(MergeBatch batch)
    {
        foreach (var (child, parentRef) in batch.Pending)
        {
            var parent = batch.Inventory.Gear().FirstOrDefault(item => item.Extras.ImportRef == parentRef) ?? throw new InvalidDataException("父级导入标识不存在：" + parentRef);
            var record = batch.Inventory.FindGear(child)!;
            if (!GearService.CanSetParent(batch.Inventory, child, parent.Id!)) throw new InvalidDataException("父子层级无效，未保存导入内容。");
            record.Extras.ParentId = parent.Id;
        }
    }

    private static void ValidateAssetIds(InventoryDocument inventory)
    {
        var ids = inventory.Gear().Select(item => item.Extras.AssetId).Where(id => id > 0).ToList();
        if (ids.Count != ids.Distinct().Count()) throw new InvalidDataException("资产编号重复，未修改任何记录。");
    }

    private static void AddMissingLabels(InventoryDocument inventory)
    {
        var tags = inventory.Gear().SelectMany(item => item.Tags.Split(',').Select(part => part.Trim()))
            .Where(tag => tag.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase);
        foreach (var tag in tags)
            if (!inventory.Labels.OfType<JsonObject>().Any(node => string.Equals(node["name"]?.ToString(), tag, StringComparison.OrdinalIgnoreCase)))
                inventory.Labels.Add(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["name"] = tag, ["color"] = "绿色", ["description"] = "" });
    }

    private sealed class MergeBatch(InventoryDocument inventory, IReadOnlyList<string> headers)
    {
        public InventoryDocument Inventory { get; } = inventory;
        public IReadOnlyList<string> Headers { get; } = headers;
        public List<(string Child, string ParentRef)> Pending { get; } = [];
        public List<string> Warnings { get; } = [];
        public int Added { get; set; }
        public int Updated { get; set; }
    }

    public static IReadOnlyList<IReadOnlyList<string>> Parse(string text, char delimiter = ',')
    {
        text = text.TrimStart('\uFEFF'); var rows = new List<IReadOnlyList<string>>(); var row = new List<string>(); var cell = new StringBuilder(); var quoted = false;
        for (var index = 0; index < text.Length; index++)
        {
            var ch = text[index];
            if (ch == '"')
            {
                if (quoted && index + 1 < text.Length && text[index + 1] == '"') { cell.Append('"'); index++; }
                else if (!quoted && cell.Length > 0) throw new InvalidDataException("CSV 引号位置无效。");
                else quoted = !quoted;
            }
            else if (ch == delimiter && !quoted) { row.Add(cell.ToString()); cell.Clear(); }
            else if ((ch == '\r' || ch == '\n') && !quoted)
            {
                FinishRow(); if (ch == '\r' && index + 1 < text.Length && text[index + 1] == '\n') index++;
            }
            else cell.Append(ch);
        }
        if (quoted) throw new InvalidDataException("CSV 文件存在未闭合的引号。"); FinishRow(); return rows;
        void FinishRow() { row.Add(cell.ToString()); if (row.Any(value => value.Length > 0)) rows.Add(row.ToArray()); row.Clear(); cell.Clear(); }
    }

    public static string Encode(IEnumerable<IReadOnlyList<string>> rows) => string.Join("\r\n", rows.Select(row => string.Join(',', row.Select(value => "\"" + value.Replace("\"", "\"\"", StringComparison.Ordinal) + "\""))));

    private static string EnsureLocation(InventoryDocument inventory, string path)
    {
        string? parentId = null;
        foreach (var name in path.Split('/').Select(part => part.Trim()).Where(part => part.Length > 0))
        {
            var match = inventory.Gear(false).FirstOrDefault(item => item.IsLocation && item.Name == name && InventoryDocument.IdEquals(item.Extras.ParentId, parentId));
            if (match is null) { match = GearService.Create(inventory, name, "位置", parentId); match.Extras.AssetId = inventory.Gear().Max(item => item.Extras.AssetId) + 1; match.Extras.ImportRef = match.Id!; }
            parentId = match.Id;
        }
        return parentId ?? "";
    }

    private static double Number(string text, double fallback, string field, int line)
    {
        if (string.IsNullOrWhiteSpace(text)) return fallback;
        var normalized = text.Trim().Replace("￥", "", StringComparison.Ordinal).Replace(",", "", StringComparison.Ordinal);
        if (normalized.EndsWith("kg", StringComparison.OrdinalIgnoreCase)) return Parse(normalized[..^2], field, line) * 1000;
        if (double.TryParse(normalized, NumberStyles.Float | NumberStyles.AllowCurrencySymbol, CultureInfo.InvariantCulture, out var value) && double.IsFinite(value)) return value;
        if (double.TryParse(normalized, NumberStyles.Float, CultureInfo.CurrentCulture, out value) && double.IsFinite(value)) return value;
        throw new InvalidDataException($"第 {line + 1} 行{field}不是有效数字。");
    }
    private static double Parse(string text, string field, int line) => double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) && double.IsFinite(value) ? value : throw new InvalidDataException($"第 {line + 1} 行{field}不是有效数字。");
    private static bool ParseFlag(string value) => value.Trim().ToLowerInvariant() is "true" or "yes" or "1" or "是" or "✓" or "☑";
}
