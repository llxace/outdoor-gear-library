using System.Globalization;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public sealed record ExcelImportResult(InventoryDocument Inventory, int Added, int Updated, int Skipped, IReadOnlyList<string> Names, IReadOnlyList<string> Warnings);

public static class ExcelImportService
{
    public static readonly string[] Fields = ["忽略", "名称", "装备ID", "分类", "品牌", "型号", "数量", "单件重量(g)", "购买价格", "购买渠道", "购买日期", "状态", "装备损坏", "备注"];
    private static readonly Dictionary<string, string> Destinations = new(StringComparer.Ordinal)
    {
        ["名称"] = "HB.name",
        ["装备ID"] = "HB.import_ref",
        ["分类"] = "Native.category",
        ["品牌"] = "HB.manufacturer",
        ["型号"] = "HB.model_number",
        ["数量"] = "HB.quantity",
        ["单件重量(g)"] = "Native.weight_g",
        ["购买价格"] = "HB.purchase_price",
        ["购买渠道"] = "HB.purchase_from",
        ["购买日期"] = "HB.purchase_time",
        ["状态"] = "Native.status",
        ["备注"] = "HB.notes"
    };
    private static readonly Dictionary<string, string[]> Aliases = new(StringComparer.Ordinal)
    {
        ["名称"] = ["名称", "装备名称", "物品名称", "商品名称", "hb.name"],
        ["装备ID"] = ["装备id", "装备编号", "hb.import_ref"],
        ["分类"] = ["分类", "子类", "类别", "native.category"],
        ["品牌"] = ["品牌", "制造商", "hb.manufacturer"],
        ["型号"] = ["型号", "型号/系列", "hb.model_number"],
        ["数量"] = ["数量", "件数", "hb.quantity"],
        ["单件重量(g)"] = ["重量（g）", "重量(g)", "单件重量(g)", "重量", "重量(kg)", "重量（kg）", "native.weight_g"],
        ["购买价格"] = ["购买价格", "购买价格(元)", "购买价格（元）", "价格", "净支出", "hb.purchase_price"],
        ["购买渠道"] = ["购买平台", "购买渠道", "hb.purchase_from"],
        ["购买日期"] = ["购买日期", "hb.purchase_time"],
        ["状态"] = ["状态", "native.status"],
        ["装备损坏"] = ["装备损坏", "是否损坏"],
        ["备注"] = ["备注", "使用/维护备注", "hb.notes"]
    };

    public static string Guess(string header)
    {
        var compact = header.Trim().ToLowerInvariant().Replace(" ", "", StringComparison.Ordinal);
        return Aliases.FirstOrDefault(entry => entry.Value.Contains(compact, StringComparer.Ordinal)).Key ?? "忽略";
    }

    public static int DetectHeaderRow(IReadOnlyList<IReadOnlyList<string>> rows) =>
        Math.Max(0, rows.Take(30).ToList().FindIndex(row => row.Any(header => Guess(header) == "名称")));

    public static string[] GuessMapping(IReadOnlyList<string> headers)
    {
        var used = new HashSet<string>(StringComparer.Ordinal);
        return headers.Select(header =>
        {
            if (header.Length == 0) return "忽略";
            var field = Guess(header);
            return field != "忽略" && !used.Add(field) ? "忽略" : field;
        }).ToArray();
    }

    public static ExcelImportResult Import(string path, string worksheetName, int headerRow, IReadOnlyList<string> mapping, InventoryDocument existing, bool update = true)
    {
        using var workbook = new ExcelWorkbook(path);
        var rows = ReadWorksheet(workbook, worksheetName);
        var headers = ValidateMapping(rows, headerRow, mapping);
        var batch = new ImportBatch(existing, rows, headerRow, mapping, headers, update);
        for (var sourceRow = headerRow + 1; sourceRow < rows.Count; sourceRow++) ImportRow(batch, sourceRow);
        return FinishImport(batch);
    }

    private static IReadOnlyList<IReadOnlyList<string>> ReadWorksheet(ExcelWorkbook workbook, string worksheetName)
    {
        var sheet = workbook.Sheets.FirstOrDefault(item => item.Name == worksheetName) ?? throw new InvalidDataException("所选工作表不存在。");
        return workbook.ReadRows(sheet);
    }

    private static IReadOnlyList<string> ValidateMapping(IReadOnlyList<IReadOnlyList<string>> rows, int headerRow, IReadOnlyList<string> mapping)
    {
        if (headerRow < 0 || headerRow >= rows.Count || mapping.Count == 0 || !mapping.Contains("名称")) throw new InvalidDataException("请选择有效表头，并将装备名称列映射到“名称”。");
        var headers = rows[headerRow];
        if (mapping.Count != headers.Count) throw new InvalidDataException("列映射和表头列数不一致。");
        var assigned = mapping.Where(field => field != "忽略").ToList();
        if (assigned.Distinct(StringComparer.Ordinal).Count() != assigned.Count) throw new InvalidDataException("同一个目标字段不能映射多列。");
        return headers;
    }

    private static void ImportRow(ImportBatch batch, int sourceRow)
    {
        var row = batch.Rows[sourceRow];
        var name = ReadMappedValue(batch.Mapping, row, "名称");
        if (name.Length == 0) { if (row.Any(cell => cell.Length > 0)) batch.Skipped++; return; }
        var reference = batch.Update ? ReadMappedValue(batch.Mapping, row, "装备ID") : "";
        var previous = FindPrevious(batch, reference);
        var values = CreatePreviousValues(batch, previous, reference);
        values["HB.name"] = name;
        values["HB.import_ref"] = reference;
        MapFields(batch, sourceRow, row, values);
        ApplyDamageFlag(batch, row, values);
        batch.OutputRows.Add(batch.CsvHeaders.Select(header => values.GetValueOrDefault(header, "")).ToArray());
        batch.Names.Add(name);
        if (previous is null) batch.Added++; else batch.Updated++;
    }

    private static string ReadMappedValue(IReadOnlyList<string> mapping, IReadOnlyList<string> row, string field)
    {
        var index = mapping.ToList().IndexOf(field);
        return index >= 0 && index < row.Count ? row[index].Trim() : "";
    }

    private static GearRecord? FindPrevious(ImportBatch batch, string reference) =>
        reference.Length == 0 ? null : batch.Existing.Gear(false).FirstOrDefault(item => item.Extras.ImportRef == reference);

    private static Dictionary<string, string> CreatePreviousValues(ImportBatch batch, GearRecord? previous, string reference)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        if (previous is null) return values;
        var idColumn = batch.CsvHeaders.ToList().IndexOf("Native.id");
        var refColumn = batch.CsvHeaders.ToList().IndexOf("HB.import_ref");
        var oldRow = batch.OldRows.Skip(1).FirstOrDefault(cells => MatchesPrevious(cells, idColumn, refColumn, previous, reference));
        if (oldRow is not null) foreach (var pair in batch.CsvHeaders.Zip(oldRow)) values[pair.First] = pair.Second;
        return values;
    }

    private static bool MatchesPrevious(IReadOnlyList<string> cells, int idColumn, int refColumn, GearRecord previous, string reference) =>
        cells.Count > 0 && ((idColumn >= 0 && idColumn < cells.Count && InventoryDocument.IdEquals(cells[idColumn], previous.Id)) ||
        (refColumn >= 0 && refColumn < cells.Count && cells[refColumn] == reference));

    private static void MapFields(ImportBatch batch, int sourceRow, IReadOnlyList<string> row, Dictionary<string, string> values)
    {
        for (var column = 0; column < batch.Mapping.Count && column < row.Count; column++)
            MapField(batch, sourceRow, row, column, values);
    }

    private static void MapField(ImportBatch batch, int sourceRow, IReadOnlyList<string> row, int column, Dictionary<string, string> values)
    {
        var field = batch.Mapping[column]; var raw = row[column].Trim();
        var header = column < batch.Headers.Count ? batch.Headers[column] : "";
        if (field == "忽略" || raw.Length == 0) return;
        if (field == "装备损坏") { if (IsChecked(raw)) values["Native.status"] = "损坏"; return; }
        if (field == "状态") { values["Native.status"] = NormalizeStatus(raw); return; }
        if (field is "数量" or "单件重量(g)" or "购买价格") { MapNumber(batch, sourceRow, field, header, raw, values); return; }
        if (Destinations.TryGetValue(field, out var destination)) values[destination] = raw;
    }

    private static string NormalizeStatus(string raw) => raw switch
    {
        "已购" or "已购买" or "正常" or "可用" => "可用",
        "待购" or "想买" or "待购买" => "想买",
        "借出" or "损坏" or "已出售" or "维修中" => raw,
        _ => raw
    };

    private static void MapNumber(ImportBatch batch, int sourceRow, string field, string header, string raw, Dictionary<string, string> values)
    {
        if (TryNumber(raw, field, header, out var numeric)) values[Destinations[field]] = numeric.ToString("G", CultureInfo.InvariantCulture);
        else batch.Warnings.Add($"第 {sourceRow + 1} 行“{header}”：{raw}；该数字未导入。");
    }

    private static void ApplyDamageFlag(ImportBatch batch, IReadOnlyList<string> row, Dictionary<string, string> values)
    {
        values["HB.import_ref"] = batch.Update ? ReadMappedValue(batch.Mapping, row, "装备ID") : "";
        if (values.TryGetValue("Native.status", out _) && IsChecked(ReadMappedValue(batch.Mapping, row, "装备损坏"))) values["Native.status"] = "损坏";
    }

    private static ExcelImportResult FinishImport(ImportBatch batch)
    {
        if (batch.Names.Count == 0) throw new InvalidDataException("没有发现可导入的装备名称，请确认工作表和表头映射。");
        var merged = CsvService.Merge(CsvService.Encode(batch.OutputRows), batch.Existing);
        return new ExcelImportResult(merged.Inventory, batch.Added, batch.Updated, batch.Skipped, batch.Names, batch.Warnings.Concat(merged.Warnings).ToArray());
    }

    private sealed class ImportBatch
    {
        public ImportBatch(InventoryDocument existing, IReadOnlyList<IReadOnlyList<string>> rows, int headerRow, IReadOnlyList<string> mapping, IReadOnlyList<string> headers, bool update)
        {
            Existing = existing; Rows = rows; HeaderRow = headerRow; Mapping = mapping; Headers = headers; Update = update;
            OldRows = CsvService.Parse(CsvService.Export(existing)); CsvHeaders = OldRows.First();
            OutputRows.Add(CsvHeaders);
        }

        public InventoryDocument Existing { get; }
        public IReadOnlyList<IReadOnlyList<string>> Rows { get; }
        public int HeaderRow { get; }
        public IReadOnlyList<string> Mapping { get; }
        public IReadOnlyList<string> Headers { get; }
        public bool Update { get; }
        public IReadOnlyList<IReadOnlyList<string>> OldRows { get; }
        public IReadOnlyList<string> CsvHeaders { get; }
        public List<IReadOnlyList<string>> OutputRows { get; } = [];
        public List<string> Names { get; } = [];
        public List<string> Warnings { get; } = [];
        public int Added { get; set; }
        public int Updated { get; set; }
        public int Skipped { get; set; }
    }

    private static bool IsChecked(string value) => value.Trim().ToLowerInvariant() is "☑" or "是" or "true" or "1" or "损坏" or "已损坏";

    private static bool TryNumber(string raw, string field, string header, out double result)
    {
        var numeric = raw.Replace(",", "", StringComparison.Ordinal).Replace("，", "", StringComparison.Ordinal).Replace(" ", "", StringComparison.Ordinal)
            .Replace("￥", "", StringComparison.Ordinal).Replace("¥", "", StringComparison.Ordinal).Replace("元", "", StringComparison.Ordinal)
            .Replace("约", "", StringComparison.Ordinal).Replace("≈", "", StringComparison.Ordinal);
        var kilograms = field == "单件重量(g)" && (numeric.EndsWith("kg", StringComparison.OrdinalIgnoreCase) || header.Contains("kg", StringComparison.OrdinalIgnoreCase));
        if (field == "单件重量(g)") numeric = numeric.Replace("kg", "", StringComparison.OrdinalIgnoreCase).Replace("g", "", StringComparison.OrdinalIgnoreCase).Replace("克", "", StringComparison.Ordinal);
        if (!double.TryParse(numeric, NumberStyles.Float, CultureInfo.InvariantCulture, out result) || !double.IsFinite(result) || result < 0 || field == "数量" && result == 0) return false;
        if (kilograms) result *= 1000;
        return true;
    }
}
