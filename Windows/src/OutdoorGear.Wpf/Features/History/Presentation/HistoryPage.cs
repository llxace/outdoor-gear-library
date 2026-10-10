using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using Microsoft.Win32;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;
using OutdoorGear.Wpf.Features.Shared.Presentation;

namespace OutdoorGear.Wpf.Features.History.Presentation;

public sealed class HistoryPage : UserControl
{
    private readonly LibrarySession session;
    private readonly TextBox search = new() { Width = 280, Height = 32, Margin = new Thickness(0, 0, 8, 0) };
    private readonly ComboBox yearFilter = new() { Width = 125, Margin = new Thickness(0, 0, 10, 0) };
    private readonly CheckBox showDeleted = new() { Content = "查看已删除记录", VerticalAlignment = VerticalAlignment.Center };
    private readonly ListBox entries = new() { MinWidth = 270 };
    private readonly TextBlock detail = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(8) };
    private readonly DataGrid equipment = new() { AutoGenerateColumns = false, IsReadOnly = true, CanUserAddRows = false, Height = 330 };
    private readonly TextBlock mealSummary = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) };
    private readonly HistoryRoutePreview routePreview = new() { Height = 220, Margin = new Thickness(0, 10, 0, 0) };
    private bool updatingYearFilter;

    public HistoryPage(LibrarySession session)
    {
        this.session = session;
        Content = BuildLayout();
        Refresh();
    }

    private DockPanel BuildLayout()
    {
        var root = new DockPanel { Margin = new Thickness(14) };
        var header = BuildHeader();
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);
        root.Children.Add(BuildRecordView());
        return root;
    }

    private StackPanel BuildHeader()
    {
        var header = new StackPanel();
        header.Children.Add(new TextBlock
        {
            Text = "个人专栏",
            FontSize = 22,
            FontWeight = FontWeights.SemiBold
        });
        var actions = new WrapPanel { Margin = new Thickness(0, 10, 0, 8) };
        actions.Children.Add(PageUi.Button("＋ 手动补录", (_, _) => Edit(null)));
        actions.Children.Add(PageUi.Button("保存当前打包", (_, _) => SavePackingSnapshot()));
        actions.Children.Add(PageUi.Button("导入 GPX/KML", (_, _) => Import()));
        actions.Children.Add(PageUi.Button("编辑所选", (_, _) => Edit(Selected)));
        actions.Children.Add(PageUi.Button("删除 / 恢复", (_, _) => ToggleDeleted()));
        actions.Children.Add(PageUi.Button("导出全部记录 JSON", (_, _) => Export()));
        header.Children.Add(actions);
        var filter = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
        search.ToolTip = "搜索标题、路线或游记";
        filter.Children.Add(search);
        filter.Children.Add(yearFilter);
        filter.Children.Add(showDeleted);
        header.Children.Add(filter);
        search.TextChanged += (_, _) => Refresh();
        yearFilter.SelectionChanged += (_, _) => { if (!updatingYearFilter) Refresh(); };
        showDeleted.Checked += (_, _) => Refresh();
        showDeleted.Unchecked += (_, _) => Refresh();
        return header;
    }

    private Grid BuildRecordView()
    {
        entries.SelectionChanged += (_, _) => ShowSelected();
        var split = new Grid();
        split.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(1, GridUnitType.Star),
            MinWidth = 260
        });
        split.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(2, GridUnitType.Star),
            MinWidth = 400
        });
        Grid.SetColumn(entries, 0);
        split.Children.Add(entries);
        var right = BuildRecordDetails();
        Grid.SetColumn(right, 1);
        split.Children.Add(right);
        return split;
    }

    private DockPanel BuildRecordDetails()
    {
        var right = new DockPanel { Margin = new Thickness(16, 0, 0, 0) };
        right.Children.Add(detail);
        var routePanel = new StackPanel();
        routePanel.Children.Add(routePreview);
        routePanel.Children.Add(mealSummary);
        DockPanel.SetDock(routePanel, Dock.Bottom);
        right.Children.Add(routePanel);
        right.Children.Add(BuildEquipmentPanel());
        return right;
    }

    private StackPanel BuildEquipmentPanel()
    {
        var gearPanel = new StackPanel();
        gearPanel.Children.Add(new TextBlock
        {
            Text = "当次携带装备快照",
            FontSize = 17,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 12, 0, 8)
        });
        ConfigureEquipmentColumns();
        gearPanel.Children.Add(equipment);
        return gearPanel;
    }
    private void ConfigureEquipmentColumns()
    {
        AddEquipmentColumn("名称", nameof(HistoryGearRow.Name), 2);
        AddEquipmentColumn("品牌 / 型号", nameof(HistoryGearRow.Description), 1.5);
        equipment.Columns.Add(new DataGridTextColumn
        {
            Header = "重量 g",
            Binding = new Binding(nameof(HistoryGearRow.Weight)),
            Width = 90
        });
        equipment.Columns.Add(new DataGridTextColumn
        {
            Header = "数量",
            Binding = new Binding(nameof(HistoryGearRow.Quantity)),
            Width = 75
        });
    }
    private void AddEquipmentColumn(string title, string property, double starWidth)
    {
        equipment.Columns.Add(new DataGridTextColumn
        {
            Header = title,
            Binding = new Binding(property),
            Width = new DataGridLength(starWidth, DataGridLengthUnitType.Star)
        });
    }

    private JsonObject? Selected => (entries.SelectedItem as HistoryChoice)?.Record;
    private IEnumerable<JsonObject> Filtered => session.Inventory.HikeNodes.OfType<JsonObject>()
        .Where(item => InventoryDocument.Bool(item["deleted"]) == (showDeleted.IsChecked == true))
        .Where(item => !int.TryParse(yearFilter.SelectedItem?.ToString(), out var year) || HistoryService.FromSwiftDate(item["date"]).Year == year)
        .Where(item => string.IsNullOrWhiteSpace(search.Text) || string.Join(" ", item["title"], item["routeName"], item["notes"]).Contains(search.Text.Trim(), StringComparison.CurrentCultureIgnoreCase))
        .OrderByDescending(item => HistoryService.FromSwiftDate(item["date"]));

    private void Refresh()
    {
        var selectedId = Selected?["id"]?.ToString();
        UpdateYearFilter();
        var choices = Filtered.Select(item => new HistoryChoice(item)).ToList();
        entries.ItemsSource = choices;
        entries.DisplayMemberPath = nameof(HistoryChoice.Label);
        entries.SelectedItem = choices.FirstOrDefault(item => InventoryDocument.IdEquals(item.Record["id"]?.ToString(), selectedId)) ?? choices.FirstOrDefault();
        ShowSelected();
    }

    private void UpdateYearFilter()
    {
        var selected = yearFilter.SelectedItem?.ToString();
        var years = new[] { "全部年份" }.Concat(session.Inventory.HikeNodes.OfType<JsonObject>()
            .Select(item => HistoryService.FromSwiftDate(item["date"]).Year.ToString(CultureInfo.InvariantCulture))
            .Distinct().OrderByDescending(value => value, StringComparer.Ordinal)).ToList();
        updatingYearFilter = true;
        yearFilter.ItemsSource = years;
        yearFilter.SelectedItem = years.Contains(selected ?? "全部年份") ? selected ?? "全部年份" : years[0];
        updatingYearFilter = false;
    }

    private void ShowSelected()
    {
        if (Selected is not { } record)
        {
            ClearSelection();
            return;
        }
        ShowRecordDetails(record);
        routePreview.Route = record["route"] as JsonObject;
        UpdateMealSummary(record);
        equipment.ItemsSource = ReadGearRows(record);
    }
    private void ClearSelection()
    {
        detail.Text = "选择一条记录查看详情。";
        equipment.ItemsSource = null;
        routePreview.Route = null;
        mealSummary.Text = "";
    }
    private void ShowRecordDetails(JsonObject record)
    {
        var date = HistoryService.FromSwiftDate(record["date"]);
        var gear = ReadGearRows(record);
        var totalWeight = gear.Sum(item => item.Weight * item.Quantity);
        detail.Text = $"{record["title"]}\n{date:yyyy年M月d日} · {record["routeName"]}\n里程：{record["distance"]}\n装备：{gear.Count} 项 · {totalWeight / 1000:0.000} kg\n\n{record["notes"]}";
    }
    private static List<HistoryGearRow> ReadGearRows(JsonObject record)
    {
        return (record["gear"] as JsonArray)?
            .OfType<JsonObject>()
            .Select(item => new HistoryGearRow(item))
            .ToList() ?? [];
    }
    private void UpdateMealSummary(JsonObject record)
    {
        var mealPlan = record["mealPlan"];
        var foods = (mealPlan?["foods"] as JsonArray)?.OfType<JsonObject>().ToList() ?? [];
        var foodWeight = foods.Sum(item =>
            InventoryDocument.Number(item["quantity"]) * InventoryDocument.Number(item["grams"]));
        var foodCalories = foods.Sum(item =>
            InventoryDocument.Number(item["quantity"]) * InventoryDocument.Number(item["calories"]));
        var water = InventoryDocument.Number(mealPlan?["waterLiters"]);
        mealSummary.Text = FormatMealSummary(foods.Count, foodWeight, foodCalories, water);
    }
    private static string FormatMealSummary(int foodCount, double weight, double calories, double water)
    {
        return foodCount == 0 && water == 0
            ? "当次未保存路餐快照。"
            : $"当次路餐快照：{foodCount} 项 · 食物 {weight:0} g · 热量 {calories:0} kcal · 携水 {water:0.##} L";
    }

    private void Edit(JsonObject? source)
    {
        var window = new HikeEditorWindow(session, source) { Owner = Window.GetWindow(this) };
        if (window.ShowDialog() != true)
            return;
        try
        {
            HistoryService.Save(session.Inventory, window.Record);
            session.Save();
            Refresh();
        }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void SavePackingSnapshot()
    {
        var record = HistoryService.FromPacking(session.Inventory);
        var window = new HikeEditorWindow(session, record) { Owner = Window.GetWindow(this) };
        if (window.ShowDialog() != true)
            return;
        try
        {
            HistoryService.Save(session.Inventory, window.Record);
            session.Save();
            Refresh();
        }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void Import()
    {
        var dialog = new OpenFileDialog { Filter = "GPX/KML 轨迹|*.gpx;*.kml" };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            using var stream = File.OpenRead(dialog.FileName);
            var route = TrailFileReader.Read(dialog.FileName, stream);
            Edit(CreateHikeFromRoute(route));
        }
        catch (Exception error) { PageUi.Error(error); }
    }
    private static JsonObject CreateHikeFromRoute(ImportedTrail route)
    {
        return new JsonObject
        {
            ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(),
            ["title"] = route.Name,
            ["date"] = HistoryService.ToSwiftDate(DateTime.Today),
            ["routeName"] = route.Name,
            ["distance"] = route.Distance,
            ["notes"] = "",
            ["deleted"] = false,
            ["route"] = TrailFileReader.ToJson(route),
            ["gear"] = new JsonArray()
        };
    }

    private void ToggleDeleted()
    {
        if (Selected is not { } record)
            return;
        try
        {
            HistoryService.SetDeleted(session.Inventory, record["id"]!.ToString(), !InventoryDocument.Bool(record["deleted"]));
            session.Save();
            Refresh();
        }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void Export()
    {
        var dialog = new SaveFileDialog { Filter = "JSON 文件|*.json", FileName = "徒步记录.json" };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            var json = session.Inventory.HikeNodes.ToJsonString(
                new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(dialog.FileName, json);
        }
        catch (Exception error) { PageUi.Error(error); }
    }
}

internal sealed class HistoryRoutePreview : Canvas
{
    private JsonObject? route;
    public JsonObject? Route { get => route; set { route = value; DrawRoute(); } }
    public HistoryRoutePreview() { Background = System.Windows.Media.Brushes.DimGray; SizeChanged += (_, _) => DrawRoute(); }
    private void DrawRoute()
    {
        Children.Clear();
        if (Route?["segments"] is not JsonArray segments) return;
        var paths = segments.OfType<JsonArray>().Select(segment => segment.OfType<JsonObject>().Select(item => (Lat: InventoryDocument.Number(item["lat"], double.NaN), Lon: InventoryDocument.Number(item["lon"], double.NaN))).Where(point => double.IsFinite(point.Lat) && double.IsFinite(point.Lon)).ToList()).Where(points => points.Count > 1).ToList();
        var points = paths.SelectMany(segment => segment).ToList();
        if (points.Count < 2) return;
        var minLat = points.Min(point => point.Lat); var maxLat = points.Max(point => point.Lat); var minLon = points.Min(point => point.Lon); var maxLon = points.Max(point => point.Lon);
        var sx = Math.Max(1, ActualWidth - 24) / Math.Max(0.00001, maxLon - minLon); var sy = Math.Max(1, ActualHeight - 24) / Math.Max(0.00001, maxLat - minLat); var scale = Math.Min(sx, sy);
        var width = (maxLon - minLon) * scale; var height = (maxLat - minLat) * scale; var left = (ActualWidth - width) / 2; var top = (ActualHeight - height) / 2;
        foreach (var segment in paths)
            Children.Add(new System.Windows.Shapes.Polyline { Stroke = System.Windows.Media.Brushes.DeepSkyBlue, StrokeThickness = 3, Points = new System.Windows.Media.PointCollection(segment.Select(point => new Point(left + (point.Lon - minLon) * scale, ActualHeight - top - (point.Lat - minLat) * scale))) });
        Children.Add(new TextBlock { Text = Route["name"]?.ToString() ?? "轨迹预览", Foreground = System.Windows.Media.Brushes.White, Margin = new Thickness(8) });
    }
}

internal sealed class HistoryChoice(JsonObject record)
{
    public JsonObject Record { get; } = record;
    public string Label => $"{HistoryService.FromSwiftDate(Record["date"]):yyyy-MM-dd} · {Record["title"]}" + (InventoryDocument.Bool(Record["deleted"]) ? "（已删除）" : "");
}

internal sealed class HistoryGearRow(JsonObject item)
{
    public string Name => item["gear"]?["name"]?.ToString() ?? "";
    public string Description => string.Join(" / ", new[] { item["gear"]?["brand"]?.ToString(), item["gear"]?["model"]?.ToString() }.Where(value => !string.IsNullOrWhiteSpace(value)));
    public double Weight => InventoryDocument.Number(item["gear"]?["weight"]);
    public double Quantity => InventoryDocument.Number(item["quantity"], 1);
}

public sealed class HikeEditorWindow : Window
{
    private readonly LibrarySession session;
    private readonly TextBox title = new(), routeName = new(), distance = new(), notes = new();
    private readonly DatePicker date = new() { SelectedDate = DateTime.Today };
    private readonly DataGrid gearGrid = new() { AutoGenerateColumns = false, CanUserAddRows = false, Height = 270 };
    private readonly ObservableCollection<HikeGearEditRow> gearRows = [];
    private JsonObject? route;
    public JsonObject Record { get; }

    public HikeEditorWindow(LibrarySession session, JsonObject? source)
    {
        this.session = session;
        Record = source is null
            ? new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["title"] = "", ["date"] = HistoryService.ToSwiftDate(DateTime.Today), ["routeName"] = "", ["distance"] = "", ["notes"] = "", ["gear"] = new JsonArray(), ["deleted"] = false }
            : (JsonObject)source.DeepClone();
        Title = "徒步记录"; Width = 850; Height = 760; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        title.Text = Record["title"]?.ToString() ?? ""; routeName.Text = Record["routeName"]?.ToString() ?? ""; distance.Text = Record["distance"]?.ToString() ?? ""; notes.Text = Record["notes"]?.ToString() ?? ""; date.SelectedDate = HistoryService.FromSwiftDate(Record["date"]);
        route = Record["route"] is JsonObject savedRoute ? (JsonObject)savedRoute.DeepClone() : null;
        if (Record["gear"] is JsonArray gear) foreach (var item in gear.OfType<JsonObject>()) gearRows.Add(new HikeGearEditRow(item));
        var panel = new StackPanel { Margin = new Thickness(20) };
        AddField("记录标题", title); AddField("徒步日期", date); AddField("路线 / 地点", routeName); AddField("里程", distance);
        var routeBar = new StackPanel { Orientation = Orientation.Horizontal }; routeBar.Children.Add(PageUi.Button("导入 / 更换 GPX、KML", (_, _) => ImportRoute())); routeBar.Children.Add(PageUi.Button("移除轨迹", (_, _) => { route = null; })); panel.Children.Add(routeBar);
        panel.Children.Add(new TextBlock { Text = "当次装备快照（只保存本次记录，不会修改装备库）", FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 6) });
        AddGearColumn("装备名称", nameof(HikeGearEditRow.Name), 150);
        AddGearColumn("分类", nameof(HikeGearEditRow.Category), 110);
        AddGearColumn("品牌", nameof(HikeGearEditRow.Brand), 100);
        AddGearColumn("型号", nameof(HikeGearEditRow.Model), 110);
        AddGearColumn("重量 g", nameof(HikeGearEditRow.Weight), 85);
        AddGearColumn("数量", nameof(HikeGearEditRow.Quantity), 75);
        AddGearColumn("使用感受", nameof(HikeGearEditRow.Feeling), 190);
        gearGrid.ItemsSource = gearRows; panel.Children.Add(gearGrid);
        var gearActions = new WrapPanel(); gearActions.Children.Add(PageUi.Button("从装备库添加", (_, _) => AddFromLibrary())); gearActions.Children.Add(PageUi.Button("手动添加快照", (_, _) => AddManual())); gearActions.Children.Add(PageUi.Button("移除所选快照", (_, _) => { if (gearGrid.SelectedItem is HikeGearEditRow selected) gearRows.Remove(selected); })); panel.Children.Add(gearActions);
        AddField("徒步回忆、天气和装备感受", notes); notes.AcceptsReturn = true; notes.TextWrapping = TextWrapping.Wrap; notes.Height = 115; notes.VerticalContentAlignment = VerticalAlignment.Top;
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 10, 0, 0) };
        var cancel = new Button { Content = "取消", Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(0, 0, 8, 0) }; cancel.Click += (_, _) => DialogResult = false;
        var save = new Button { Content = "保存记录", Padding = new Thickness(14, 7, 14, 7) }; save.Click += (_, _) => Save(); buttons.Children.Add(cancel); buttons.Children.Add(save); panel.Children.Add(buttons);
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        void AddField(string label, Control control) { panel.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, 4, 0, 3), Foreground = System.Windows.Media.Brushes.Gray }); control.Height = control is DatePicker ? 32 : control.Height; control.Margin = new Thickness(0, 0, 0, 3); panel.Children.Add(control); }
    }

    private void ImportRoute()
    {
        var dialog = new OpenFileDialog { Filter = "GPX/KML 轨迹|*.gpx;*.kml" };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            using var stream = File.OpenRead(dialog.FileName);
            var imported = TrailFileReader.Read(dialog.FileName, stream);
            route = TrailFileReader.ToJson(imported); routeName.Text = imported.Name; distance.Text = imported.Distance;
            if (string.IsNullOrWhiteSpace(title.Text)) title.Text = imported.Name;
        }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void AddFromLibrary()
    {
        var existingOwnIds = gearRows.Where(row => row.OwnerName is null)
            .Select(row => row.Gear["id"]?.ToString()).OfType<string>().ToHashSet(StringComparer.OrdinalIgnoreCase);
        var picker = new HikeGearPickerWindow(
            session.AllRecords().Where(item => !item.IsLocation && !item.Trashed).ToList(), existingOwnIds) { Owner = this };
        if (picker.ShowDialog() != true) return;
        foreach (var item in picker.SelectedGear)
            if (!gearRows.Any(row => row.OwnerName is null && InventoryDocument.IdEquals(row.Gear["id"]?.ToString(), item.Id)))
                gearRows.Add(new HikeGearEditRow(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["gear"] = item.Node.DeepClone(), ["quantity"] = 1 }));
    }

    private void AddGearColumn(string title, string property, double width)
    {
        gearGrid.Columns.Add(new DataGridTextColumn
        {
            Header = title,
            Binding = new Binding(property) { UpdateSourceTrigger = UpdateSourceTrigger.PropertyChanged },
            Width = width
        });
    }

    private void AddManual()
    {
        var dialog = new ManualHikeGearWindow { Owner = this };
        if (dialog.ShowDialog() != true) return;
        gearRows.Add(new HikeGearEditRow(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["gear"] = new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["name"] = dialog.NameValue, ["category"] = dialog.CategoryValue, ["brand"] = "", ["model"] = "", ["weight"] = dialog.WeightValue, ["quantity"] = dialog.QuantityValue, ["status"] = "可用", ["purchasePrice"] = 0 }, ["quantity"] = dialog.QuantityValue }));
    }

    private void Save()
    {
        try
        {
            gearGrid.CommitEdit(DataGridEditingUnit.Cell, true);
            gearGrid.CommitEdit(DataGridEditingUnit.Row, true);
            if (date.SelectedDate is null) throw new InvalidDataException("请选择徒步日期。");
            Record["title"] = title.Text.Trim(); Record["date"] = HistoryService.ToSwiftDate(date.SelectedDate.Value); Record["routeName"] = routeName.Text.Trim(); Record["distance"] = distance.Text.Trim(); Record["notes"] = notes.Text; Record["route"] = route?.DeepClone();
            Record["gear"] = new JsonArray(gearRows.Select(row => (JsonNode?)row.ToJson()).ToArray());
            DialogResult = true;
        }
        catch (Exception error) { PageUi.Error(error); }
    }
}

internal sealed class HikeGearEditRow : INotifyPropertyChanged
{
    private readonly JsonObject item;
    private double weight, quantity;
    public JsonObject Gear => (JsonObject)item["gear"]!;
    public string? OwnerName => item["ownerName"]?.ToString();
    public string Name { get => Gear["name"]?.ToString() ?? ""; set => SetGearValue("name", value); }
    public string Category { get => Gear["category"]?.ToString() ?? ""; set => SetGearValue("category", value); }
    public string Brand { get => Gear["brand"]?.ToString() ?? ""; set => SetGearValue("brand", value); }
    public string Model { get => Gear["model"]?.ToString() ?? ""; set => SetGearValue("model", value); }
    public string Feeling { get => Gear["notes"]?.ToString() ?? ""; set => SetGearValue("notes", value); }
    public double Weight { get => weight; set { weight = value; Changed(nameof(Weight)); } }
    public double Quantity { get => quantity; set { quantity = value; Changed(nameof(Quantity)); } }
    public event PropertyChangedEventHandler? PropertyChanged;
    public HikeGearEditRow(JsonObject item)
    {
        this.item = (JsonObject)item.DeepClone();
        this.item["gear"] ??= new JsonObject();
        weight = InventoryDocument.Number(Gear["weight"]);
        quantity = InventoryDocument.Number(item["quantity"], 1);
    }
    public JsonObject ToJson()
    {
        var result = (JsonObject)item.DeepClone();
        var gear = (JsonObject)Gear.DeepClone();
        gear["weight"] = Weight;
        result["gear"] = gear;
        result["quantity"] = Quantity;
        return result;
    }
    private void SetGearValue(string key, string value) { Gear[key] = value; Changed(key); }
    private void Changed(string property) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
}

internal sealed class HikeGearPickerWindow : Window
{
    private readonly ListBox list = new() { SelectionMode = SelectionMode.Extended };
    private readonly TextBox search = new() { Height = 32, MinWidth = 250 };
    private readonly ComboBox category = new() { MinWidth = 170 };
    private readonly TextBlock selectionCount = new() { VerticalAlignment = VerticalAlignment.Center, Foreground = System.Windows.Media.Brushes.Gray };
    private readonly Button addSelectionButton = new() { Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(8, 0, 0, 0), IsEnabled = false };
    private readonly IReadOnlyList<GearRecord> records;
    private readonly HashSet<string> existingIds;
    private readonly HashSet<string> selectedIds = new(StringComparer.OrdinalIgnoreCase);
    private IReadOnlyList<HikeGearChoice> visible = [];
    private bool restoringSelection;

    public IReadOnlyList<GearRecord> SelectedGear => records
        .Where(gear => gear.Id is { } id && selectedIds.Contains(id) && !existingIds.Contains(id))
        .ToList();

    public HikeGearPickerWindow(IReadOnlyList<GearRecord> records, IReadOnlySet<string> existingIds)
    {
        this.records = records;
        this.existingIds = new HashSet<string>(existingIds, StringComparer.OrdinalIgnoreCase);
        Title = "从装备库添加历史快照"; Width = 500; Height = 550; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        MinWidth = 680; MinHeight = 520; Width = 760; Height = 600;
        Content = BuildLayout();
        list.SelectionChanged += List_SelectionChanged;
        search.TextChanged += (_, _) => RefreshResults();
        category.SelectionChanged += (_, _) => RefreshResults();
        RefreshResults();
    }

    private UIElement BuildLayout()
    {
        var root = new DockPanel { Margin = new Thickness(18) };
        var header = new StackPanel();
        header.Children.Add(new TextBlock { Text = "从装备库补充历史装备", FontSize = 20, FontWeight = FontWeights.SemiBold });
        header.Children.Add(new TextBlock { Text = "选择当时携带的装备，添加后可编辑历史数量、重量和使用感受；不会修改装备库。", Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(0, 4, 0, 10) });
        header.Children.Add(BuildFilters());
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);
        var footer = BuildFooter();
        DockPanel.SetDock(footer, Dock.Bottom);
        root.Children.Add(footer);
        root.Children.Add(list);
        return root;
    }

    private UIElement BuildFilters()
    {
        var filters = new WrapPanel { Margin = new Thickness(0, 0, 0, 8) };
        search.ToolTip = "搜索名称、品牌、型号、分类、标签或备注";
        filters.Children.Add(search);
        category.ItemsSource = new[] { "全部分类" }.Concat(records.Select(item => item.Category).Distinct().Order()).ToList();
        category.SelectedIndex = 0;
        category.Margin = new Thickness(8, 0, 8, 0);
        filters.Children.Add(category);
        var selectFiltered = new Button { Content = "选择筛选结果", Padding = new Thickness(8, 4, 8, 4) };
        selectFiltered.Click += (_, _) => SelectVisible();
        filters.Children.Add(selectFiltered);
        var clear = new Button { Content = "清空选择", Padding = new Thickness(8, 4, 8, 4), Margin = new Thickness(6, 0, 0, 0) };
        clear.Click += (_, _) => ClearSelection();
        filters.Children.Add(clear);
        filters.Children.Add(selectionCount);
        return filters;
    }

    private UIElement BuildFooter()
    {
        var footer = new DockPanel { Margin = new Thickness(0, 10, 0, 0), LastChildFill = false };
        var note = new TextBlock { Text = "同一用户已记录的装备不会重复加入。", VerticalAlignment = VerticalAlignment.Center, Foreground = System.Windows.Media.Brushes.Gray };
        footer.Children.Add(note);
        addSelectionButton.Content = "添加所选";
        addSelectionButton.HorizontalAlignment = HorizontalAlignment.Right;
        addSelectionButton.Click += (_, _) => { CaptureVisibleSelection(); if (SelectedGear.Count > 0) DialogResult = true; };
        DockPanel.SetDock(addSelectionButton, Dock.Right);
        footer.Children.Add(addSelectionButton);
        var cancel = new Button { Content = "取消", Padding = new Thickness(14, 7, 14, 7) };
        cancel.Click += (_, _) => DialogResult = false;
        DockPanel.SetDock(cancel, Dock.Right);
        footer.Children.Add(cancel);
        return footer;
    }

    private void RefreshResults()
    {
        CaptureVisibleSelection();
        var query = search.Text.Trim();
        var selectedCategory = category.SelectedItem?.ToString() ?? "全部分类";
        visible = records.Where(gear =>
                (selectedCategory == "全部分类" || gear.Category == selectedCategory) &&
                (query.Length == 0 || gear.SearchText.Contains(query, StringComparison.CurrentCultureIgnoreCase)))
            .OrderBy(gear => gear.Name, StringComparer.CurrentCultureIgnoreCase)
            .Select(gear => new HikeGearChoice(gear, existingIds.Contains(gear.Id ?? "")))
            .ToList();
        RestoreVisibleSelection();
    }

    private void CaptureVisibleSelection()
    {
        if (restoringSelection) return;
        foreach (var row in visible)
            if (row.Gear.Id is { } id) selectedIds.Remove(id);
        foreach (var row in list.SelectedItems.OfType<HikeGearChoice>())
            if (!row.AlreadyRecorded && row.Gear.Id is { } id) selectedIds.Add(id);
    }

    private void RestoreVisibleSelection()
    {
        restoringSelection = true;
        list.ItemsSource = visible;
        foreach (var row in visible)
            if (!row.AlreadyRecorded && row.Gear.Id is { } id && selectedIds.Contains(id)) list.SelectedItems.Add(row);
        restoringSelection = false;
        UpdateSelectionCount();
    }

    private void List_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (restoringSelection) return;
        CaptureVisibleSelection();
        UpdateSelectionCount();
    }

    private void SelectVisible()
    {
        CaptureVisibleSelection();
        foreach (var row in visible)
            if (!row.AlreadyRecorded && row.Gear.Id is { } id) selectedIds.Add(id);
        RestoreVisibleSelection();
    }

    private void ClearSelection()
    {
        selectedIds.Clear();
        RestoreVisibleSelection();
    }

    private void UpdateSelectionCount()
    {
        selectionCount.Text = $"已选 {selectedIds.Count} 项";
        addSelectionButton.Content = $"添加 {selectedIds.Count} 项";
        addSelectionButton.IsEnabled = selectedIds.Count > 0;
    }
}

internal sealed class HikeGearChoice(GearRecord gear, bool alreadyRecorded)
{
    public GearRecord Gear { get; } = gear;
    public bool AlreadyRecorded { get; } = alreadyRecorded;
    public string Name => $"{Gear.Name} · {Gear.Category} · {Gear.Brand} {Gear.Model} · {Gear.Weight:0} g" + (AlreadyRecorded ? "（已记录）" : "");
}

internal sealed class ManualHikeGearWindow : Window
{
    private readonly TextBox name = new(), category = new() { Text = "未分类" }, weight = new() { Text = "0" }, quantity = new() { Text = "1" };
    public string NameValue => name.Text.Trim(); public string CategoryValue => category.Text.Trim(); public double WeightValue => double.Parse(weight.Text, CultureInfo.CurrentCulture); public double QuantityValue => double.Parse(quantity.Text, CultureInfo.CurrentCulture);
    public ManualHikeGearWindow()
    {
        Title = "手动添加历史装备"; Width = 420; Height = 370; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new StackPanel { Margin = new Thickness(20) }; Field("名称", name); Field("分类", category); Field("重量 g", weight); Field("携带数量", quantity);
        var save = new Button { Content = "添加到当次快照", Padding = new Thickness(14, 7, 14, 7), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 8, 0, 0) }; save.Click += (_, _) => { try { if (NameValue.Length == 0 || WeightValue < 0 || QuantityValue <= 0) throw new InvalidDataException("请检查装备名称、重量和数量。"); DialogResult = true; } catch (Exception error) { PageUi.Error(error); } }; root.Children.Add(save); Content = root;
        void Field(string label, TextBox box) { root.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, 7, 0, 3) }); box.Height = 32; root.Children.Add(box); }
    }
}
