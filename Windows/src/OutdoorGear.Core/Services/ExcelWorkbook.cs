using System.Globalization;
using System.IO.Compression;
using System.Xml;
using System.Xml.Linq;

namespace OutdoorGear.Core.Services;

public sealed record ExcelWorksheet(string Name, string Path);

public sealed class ExcelWorkbook : IDisposable
{
    public const int MaximumWorksheetXmlBytes = 32_000_000;
    public const int MaximumRows = 50_000;
    public const int MaximumColumns = 512;
    private readonly FileStream file;
    private readonly ZipArchive archive;
    private readonly string[] sharedStrings;
    private readonly HashSet<int> dateStyles;
    private readonly bool date1904;
    public IReadOnlyList<ExcelWorksheet> Sheets { get; }

    public ExcelWorkbook(string filename)
    {
        var path = Path.GetFullPath(filename);
        var info = new FileInfo(path);
        if (!info.Exists) throw new FileNotFoundException("找不到 Excel 文件。", path);
        if (info.Length > 150_000_000) throw new InvalidDataException("Excel 文件超过 150 MB，请先拆分。 ");
        file = File.OpenRead(path);
        try
        {
            archive = new ZipArchive(file, ZipArchiveMode.Read, leaveOpen: false);
            var workbook = ReadXml("xl/workbook.xml");
            var relationships = ReadXml("xl/_rels/workbook.xml.rels");
            var paths = ResolveWorksheetPaths(relationships);
            var sheets = ReadWorksheets(workbook, paths);
            if (sheets.Count == 0) throw new InvalidDataException("工作簿中没有可读取的工作表。");
            Sheets = sheets;
            date1904 = workbook.Root?.Elements().FirstOrDefault(element => element.Name.LocalName == "workbookPr")?.Attribute("date1904")?.Value is "1" or "true";
            sharedStrings = ReadSharedStrings();
            dateStyles = ReadDateStyles();
        }
        catch { file.Dispose(); throw; }
    }

    private static Dictionary<string, string> ResolveWorksheetPaths(XDocument relationships)
    {
        var paths = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var relation in relationships.Root?.Elements().Where(element => element.Name.LocalName == "Relationship") ?? [])
        {
            var id = (string?)relation.Attribute("Id");
            var target = (string?)relation.Attribute("Target");
            if (id is null || target is null || string.Equals((string?)relation.Attribute("TargetMode"), "External", StringComparison.OrdinalIgnoreCase)) continue;
            if (target.StartsWith('/') || target.Contains('\\')) continue;
            var normalized = NormalizeWorksheetPath(target);
            if (normalized is not null) paths[id] = normalized;
        }
        return paths;
    }

    private static string? NormalizeWorksheetPath(string target)
    {
        var segments = new List<string> { "xl" };
        foreach (var segment in target.Split('/'))
        {
            if (segment is "" or ".") continue;
            if (segment == "..") { if (segments.Count <= 1) return null; segments.RemoveAt(segments.Count - 1); }
            else segments.Add(segment);
        }
        var normalized = string.Join('/', segments);
        return normalized.StartsWith("xl/worksheets/", StringComparison.Ordinal) ? normalized : null;
    }

    private List<ExcelWorksheet> ReadWorksheets(XDocument workbook, IReadOnlyDictionary<string, string> paths)
    {
        var sheets = new List<ExcelWorksheet>();
        foreach (var sheet in workbook.Root?.Elements().FirstOrDefault(element => element.Name.LocalName == "sheets")?.Elements() ?? [])
        {
            var name = (string?)sheet.Attribute("name");
            var relationshipId = sheet.Attributes().FirstOrDefault(attribute => attribute.Name.LocalName == "id")?.Value;
            if (name is not null && relationshipId is not null && paths.TryGetValue(relationshipId, out var part) && archive.GetEntry(part) is not null)
                sheets.Add(new ExcelWorksheet(name, part));
        }
        return sheets;
    }

    public IReadOnlyList<IReadOnlyList<string>> ReadRows(ExcelWorksheet sheet)
    {
        if (!Sheets.Contains(sheet)) throw new InvalidOperationException("工作表不属于当前工作簿。");
        var xml = ReadXml(sheet.Path);
        var output = new List<IReadOnlyList<string>>();
        var data = xml.Root?.Elements().FirstOrDefault(element => element.Name.LocalName == "sheetData");
        foreach (var row in data?.Elements().Where(element => element.Name.LocalName == "row") ?? [])
        {
            if (!int.TryParse((string?)row.Attribute("r"), NumberStyles.None, CultureInfo.InvariantCulture, out var rowNumber)) rowNumber = output.Count + 1;
            if (rowNumber < 1 || rowNumber > MaximumRows) throw new InvalidDataException($"工作表超过 {MaximumRows:N0} 行。");
            while (output.Count < rowNumber) output.Add(Array.Empty<string>());
            var cells = new List<string>();
            foreach (var cell in row.Elements().Where(element => element.Name.LocalName == "c"))
            {
                var address = (string?)cell.Attribute("r") ?? "";
                var column = ColumnNumber(address);
                if (column is < 1 or > MaximumColumns) throw new InvalidDataException($"单元格 {address} 超出 {MaximumColumns} 列限制。");
                while (cells.Count < column) cells.Add("");
                cells[column - 1] = ReadCell(cell, address);
            }
            output[rowNumber - 1] = cells;
        }
        return output;
    }

    private string ReadCell(XElement cell, string address)
    {
        var type = (string?)cell.Attribute("t");
        var value = cell.Elements().FirstOrDefault(element => element.Name.LocalName == "v")?.Value ?? "";
        if (type == "s")
        {
            if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var index) || index < 0 || index >= sharedStrings.Length)
                throw new InvalidDataException($"{address} 的共享文本索引无效。");
            return sharedStrings[index].Trim();
        }
        if (type == "inlineStr") return string.Concat(cell.Descendants().Where(element => element.Name.LocalName == "t").Select(element => element.Value)).Trim();
        if (type == "b") return value == "1" ? "是" : "否";
        if (type == "e") throw new InvalidDataException($"{address} 包含公式错误 {value}。");
        if (cell.Elements().Any(element => element.Name.LocalName == "f") && cell.Elements().All(element => element.Name.LocalName != "v"))
            throw new InvalidDataException($"{address} 的公式没有缓存计算结果，请在 Excel/WPS 中重新计算并保存。");
        if (int.TryParse((string?)cell.Attribute("s"), NumberStyles.None, CultureInfo.InvariantCulture, out var style) && dateStyles.Contains(style) && double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var serial))
        {
            var epoch = date1904 ? new DateTime(1904, 1, 1, 0, 0, 0, DateTimeKind.Utc) : new DateTime(1899, 12, 30, 0, 0, 0, DateTimeKind.Utc);
            return epoch.AddDays(serial).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }
        return value.Trim();
    }

    private string[] ReadSharedStrings()
    {
        var entry = archive.GetEntry("xl/sharedStrings.xml");
        if (entry is null) return [];
        var xml = ReadXml(entry);
        return (xml.Root?.Elements().Where(element => element.Name.LocalName == "si") ?? [])
            .Select(item => string.Concat(item.Descendants().Where(element => element.Name.LocalName == "t").Select(element => element.Value))).ToArray();
    }

    private HashSet<int> ReadDateStyles()
    {
        var entry = archive.GetEntry("xl/styles.xml");
        if (entry is null) return [];
        var xml = ReadXml(entry);
        var dateFormats = new HashSet<int> { 14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47 };
        foreach (var format in xml.Root?.Elements().FirstOrDefault(element => element.Name.LocalName == "numFmts")?.Elements() ?? [])
        {
            if (!int.TryParse((string?)format.Attribute("numFmtId"), out var id)) continue;
            var code = (string?)format.Attribute("formatCode") ?? "";
            var stripped = System.Text.RegularExpressions.Regex.Replace(code, "\"[^\"]*\"|\\[[^\\]]*\\]|\\\\.", "").ToLowerInvariant();
            if (stripped.Contains("yy") || stripped.Contains("dd") || stripped.Contains("h:")) dateFormats.Add(id);
        }
        var indexes = new HashSet<int>();
        var styles = xml.Root?.Elements().FirstOrDefault(element => element.Name.LocalName == "cellXfs")?.Elements() ?? [];
        var index = 0;
        foreach (var style in styles)
        {
            if (int.TryParse((string?)style.Attribute("numFmtId"), out var format) && dateFormats.Contains(format)) indexes.Add(index);
            index++;
        }
        return indexes;
    }

    private XDocument ReadXml(string name) => ReadXml(archive.GetEntry(name) ?? throw new InvalidDataException($"Excel 缺少必要部件：{name}"));
    private static XDocument ReadXml(ZipArchiveEntry entry)
    {
        if (entry.Length > MaximumWorksheetXmlBytes) throw new InvalidDataException("Excel XML 部件超过 32 MB，请先拆分工作簿。");
        using var stream = entry.Open();
        using var reader = XmlReader.Create(stream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = MaximumWorksheetXmlBytes });
        return XDocument.Load(reader, LoadOptions.None);
    }

    private static int ColumnNumber(string address)
    {
        var column = 0;
        foreach (var character in address)
        {
            if (character is < 'A' or > 'Z' && character is < 'a' or > 'z') break;
            var upper = char.ToUpperInvariant(character);
            column = checked(column * 26 + upper - 'A' + 1);
        }
        return column;
    }

    public void Dispose() => archive.Dispose();
}
