using System.Globalization;
using System.IO;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Core.Features.Meals.Business;
using OutdoorGear.Core.Features.Meals.Domain;
using OutdoorGear.Wpf.ViewModels;
using OutdoorGear.Wpf.Features.Shared.Presentation;

namespace OutdoorGear.Wpf.Features.Meals.Presentation;

public sealed class MealPlannerPage : UserControl
{
    private readonly LibrarySession session;
    private readonly Action refreshPacking;
    private readonly DataGrid grid = new() { AutoGenerateColumns = false, CanUserAddRows = false, RowHeight = 48 };
    private readonly ComboBox dayFilter = new() { Width = 160 };
    private readonly TextBlock summary = new() { FontSize = 16, Margin = new Thickness(0, 8, 0, 10) };
    private readonly StackPanel dailyEnergy = new() { Orientation = Orientation.Horizontal };
    private bool updating;

    public MealPlannerPage(LibrarySession session, Action refreshPacking)
    {
        this.session = session;
        this.refreshPacking = refreshPacking;
        var root = new DockPanel { Margin = new Thickness(14) };
        var header = BuildHeader();
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);
        root.Children.Add(BuildPlanningNote());
        ConfigureGridColumns();
        Content = root;
        Refresh();
        grid.RowEditEnding += RowEditEnding;
    }
    private StackPanel BuildHeader()
    {
        var header = new StackPanel();
        header.Children.Add(new TextBlock
        {
            Text = "路餐与饮水",
            FontSize = 21,
            FontWeight = FontWeights.SemiBold
        });
        header.Children.Add(BuildActions());
        header.Children.Add(summary);
        header.Children.Add(dailyEnergy);
        header.Children.Add(BuildMealGrid());
        return header;
    }
    private UIElement BuildActions()
    {
        var actions = new WrapPanel { Margin = new Thickness(0, 10, 0, 8) };
        actions.Children.Add(PageUi.Button("行程与目标", (_, _) => Configure()));
        actions.Children.Add(PageUi.Button("添加食物", (_, _) => AddFood()));
        actions.Children.Add(PageUi.Button("包装 OCR", (_, _) => ScanFoodLabel()));
        actions.Children.Add(PageUi.Button("路餐推荐", (_, _) => Recommend()));
        actions.Children.Add(PageUi.Button("复制采购清单", (_, _) => CopyShoppingList()));
        actions.Children.Add(PageUi.Button("删除所选", (_, _) => DeleteSelected()));
        return actions;
    }
    private UIElement BuildMealGrid()
    {
        var body = new DockPanel();
        var filter = BuildDayFilter();
        DockPanel.SetDock(filter, Dock.Bottom);
        body.Children.Add(filter);
        body.Children.Add(grid);
        return body;
    }
    private UIElement BuildDayFilter()
    {
        var filter = new DockPanel { Margin = new Thickness(0, 8, 0, 6) };
        filter.Children.Add(new TextBlock
        {
            Text = "筛选日期",
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(0, 0, 8, 0)
        });
        filter.Children.Add(dayFilter);
        dayFilter.SelectionChanged += (_, _) => RefreshGrid();
        return filter;
    }
    private static UIElement BuildPlanningNote()
    {
        return new TextBlock
        {
            Text = "备用粮计入携带重量和总热量，但不计入每日计划热量。包装重量包含在食物重量中；饮水按 1 L ≈ 1 kg 计入负重。未填写重量或热量的食物按 0 统计。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = System.Windows.Media.Brushes.Gray,
            Margin = new Thickness(0, 8, 0, 0)
        };
    }
    private void ConfigureGridColumns()
    {
        AddTextColumn("食物名称", nameof(MealFoodRow.Name), 190);
        AddTextColumn("日期", nameof(MealFoodRow.Day), 58);
        AddTextColumn("餐次", nameof(MealFoodRow.Meal), 100);
        AddTextColumn("总份数", nameof(MealFoodRow.Quantity), 72);
        AddTextColumn("每份克数", nameof(MealFoodRow.Grams), 86);
        AddTextColumn("每份 kcal", nameof(MealFoodRow.Calories), 86);
        AddTextColumn("每份价格 ¥", nameof(MealFoodRow.Price), 86);
        AddTextColumn("准备方式", nameof(MealFoodRow.Preparation), 96);
        AddCheckBoxColumn("已购", nameof(MealFoodRow.Purchased), 55);
        AddCheckBoxColumn("已装包", nameof(MealFoodRow.Packed), 64);
        AddTextColumn("备注", nameof(MealFoodRow.Notes), 180);
    }
    private void AddTextColumn(string title, string property, double width)
    {
        grid.Columns.Add(new DataGridTextColumn
        {
            Header = title,
            Binding = new Binding(property),
            Width = width
        });
    }
    private void AddCheckBoxColumn(string title, string property, double width)
    {
        var binding = new Binding(property) { UpdateSourceTrigger = UpdateSourceTrigger.PropertyChanged };
        grid.Columns.Add(new DataGridCheckBoxColumn
        {
            Header = title,
            Binding = binding,
            Width = width
        });
    }
    private void Refresh()
    {
        updating = true;
        var plan = session.Inventory.MealPlan;
        UpdateSummary(plan);
        UpdateDailyEnergy(plan);
        UpdateDayFilter(plan);
        updating = false;
        RefreshGrid();
    }
    private void UpdateSummary(JsonObject plan)
    {
        var meals = MealService.Summarize(session.Inventory);
        var startDate = MealService.FromSwiftDate(plan["startDate"]);
        var days = InventoryDocument.Int(plan["days"], 1);
        var people = InventoryDocument.Int(plan["people"], 1);
        summary.Text = $"{startDate:yyyy-MM-dd} · {days} 天 · {people} 人    食物 {meals.FoodWeightGrams:0} g · 携带总重 {meals.TotalWeightGrams:0} g · 热量 {meals.Calories:0} kcal · 预算 ¥{meals.TotalCost:0.00} · 水 {meals.WaterLiters:0.##} L";
    }
    private void UpdateDailyEnergy(JsonObject plan)
    {
        dailyEnergy.Children.Clear();
        var days = InventoryDocument.Int(plan["days"], 1);
        var people = Math.Max(1, InventoryDocument.Int(plan["people"], 1));
        var goal = InventoryDocument.Number(plan["dailyGoal"]);
        for (var day = 1; day <= days; day++)
            dailyEnergy.Children.Add(CreateEnergyCard(day, people, goal));
    }
    private UIElement CreateEnergyCard(int day, int people, double goal)
    {
        var energy = MealService.EnergyForDay(session.Inventory, day);
        var goalText = goal > 0 ? $" / 目标 {goal:0}" : "";
        return new Border
        {
            Background = System.Windows.Media.Brushes.DimGray,
            CornerRadius = new CornerRadius(7),
            Padding = new Thickness(10, 7, 10, 7),
            Margin = new Thickness(0, 0, 7, 4),
            Child = new TextBlock
            {
                Text = $"第{day}天 · {energy / people:0} kcal/人{goalText}",
                FontSize = 12
            }
        };
    }
    private void UpdateDayFilter(JsonObject plan)
    {
        var days = InventoryDocument.Int(plan["days"], 1);
        var options = new[] { new MealDayOption(0, "全部天数") }
            .Concat(Enumerable.Range(1, days).Select(day => new MealDayOption(day, $"第{day}天")))
            .ToList();
        dayFilter.ItemsSource = options;
        dayFilter.DisplayMemberPath = nameof(MealDayOption.Name);
        dayFilter.SelectedValuePath = nameof(MealDayOption.Day);
        dayFilter.SelectedValue = 0;
    }

    private void RefreshGrid()
    {
        if (updating)
            return;
        var day = dayFilter.SelectedValue is int value ? value : 0;
        grid.ItemsSource = session.Inventory.MealPlan["foods"] is JsonArray foods
            ? foods.OfType<JsonObject>().Where(item => day == 0 || InventoryDocument.Int(item["day"], 1) == day).Select(item => new MealFoodRow(item)).ToList()
            : [];
    }

    private void RowEditEnding(object? sender, DataGridRowEditEndingEventArgs e)
    {
        if (e.EditAction != DataGridEditAction.Commit || e.Row.Item is not MealFoodRow row)
            return;
        Dispatcher.BeginInvoke(() =>
        {
            PersistRow(row);
        }, System.Windows.Threading.DispatcherPriority.Background);
    }
    private void PersistRow(MealFoodRow row)
    {
        try
        {
            MealService.AddOrUpdateFood(session.Inventory, row.ToJson());
            session.Save();
            Refresh();
            refreshPacking();
        }
        catch (Exception error)
        {
            PageUi.Error(error);
            Refresh();
        }
    }

    private void Configure()
    {
        var dialog = new MealSettingsWindow(session.Inventory.MealPlan, session.Departure) { Owner = Window.GetWindow(this) };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            MealService.Configure(session.Inventory, dialog.Departure, dialog.Days, dialog.People, dialog.DailyGoal, dialog.WaterLiters);
            SavePlanAndRefresh();
        }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void AddFood()
    {
        var dialog = new MealFoodWindow(null, InventoryDocument.Int(session.Inventory.MealPlan["days"], 1)) { Owner = Window.GetWindow(this) };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            MealService.AddOrUpdateFood(session.Inventory, dialog.Food);
            SavePlanAndRefresh();
        }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void ScanFoodLabel()
    {
        var scan = new FoodLabelScannerWindow { Owner = Window.GetWindow(this) };
        if (scan.ShowDialog() != true || scan.Result is not { } result)
            return;
        var draft = new MealFoodWindow(null, InventoryDocument.Int(session.Inventory.MealPlan["days"], 1)) { Owner = Window.GetWindow(this) };
        draft.ApplyLabelResult(result);
        if (draft.ShowDialog() != true)
            return;
        try
        {
            MealService.AddOrUpdateFood(session.Inventory, draft.Food);
            SavePlanAndRefresh();
        }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void Recommend()
    {
        var dialog = new MealRecommendationWindow(session.Inventory.MealPlan) { Owner = Window.GetWindow(this) };
        if (dialog.ShowDialog() != true) return;
        try
        {
            var plan = session.Inventory.MealPlan;
            plan["days"] = Math.Max(InventoryDocument.Int(plan["days"], 1), dialog.Days);
            plan["people"] = dialog.People;
            plan["dailyGoal"] = dialog.DailyCalories;
            foreach (var food in MealService.Recommend(dialog.Options)) MealService.AddOrUpdateFood(session.Inventory, food);
            SavePlanAndRefresh();
        }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void CopyShoppingList()
    {
        try { Clipboard.SetText(MealService.ShoppingList(session.Inventory)); }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void DeleteSelected()
    {
        if (grid.SelectedItem is not MealFoodRow selected)
            return;
        MealService.RemoveFood(session.Inventory, selected.Id);
        SavePlanAndRefresh();
    }
    private void SavePlanAndRefresh()
    {
        session.Save();
        Refresh();
        refreshPacking();
    }
}

public sealed record MealDayOption(int Day, string Name);

public sealed class MealFoodRow(JsonObject source)
{
    public string Id => source["id"]?.ToString() ?? "";
    public string Name { get; set; } = source["name"]?.ToString() ?? "";
    public int Day { get; set; } = InventoryDocument.Int(source["day"], 1);
    public string Meal { get; set; } = source["meal"]?.ToString() ?? "行进零食";
    public double Quantity { get; set; } = InventoryDocument.Number(source["quantity"], 1);
    public double Grams { get; set; } = InventoryDocument.Number(source["grams"]);
    public double Calories { get; set; } = InventoryDocument.Number(source["calories"]);
    public double Price { get; set; } = InventoryDocument.Number(source["price"]);
    public string Preparation { get; set; } = source["preparation"]?.ToString() ?? "即食";
    public string Notes { get; set; } = source["notes"]?.ToString() ?? "";
    public bool Purchased { get; set; } = InventoryDocument.Bool(source["purchased"]);
    public bool Packed { get; set; } = InventoryDocument.Bool(source["packed"]);
    public JsonObject ToJson()
    {
        var result = (JsonObject)source.DeepClone(); result["name"] = Name; result["day"] = Day; result["meal"] = Meal; result["quantity"] = Quantity; result["grams"] = Grams; result["calories"] = Calories; result["price"] = Price; result["preparation"] = Preparation; result["notes"] = Notes; result["purchased"] = Purchased; result["packed"] = Packed; return result;
    }
}

public sealed class MealSettingsWindow : Window
{
    private readonly DatePicker departure = new() { SelectedDate = DateTime.Today, Width = 200 };
    private readonly TextBox days = new(), people = new(), goal = new(), water = new();
    private readonly TimeSpan departureTime;
    public DateTime Departure => DateTime.SpecifyKind((departure.SelectedDate ?? DateTime.Today).Date + departureTime, DateTimeKind.Local);
    public int Days => int.Parse(days.Text, CultureInfo.InvariantCulture);
    public int People => int.Parse(people.Text, CultureInfo.InvariantCulture);
    public double DailyGoal => double.Parse(goal.Text, CultureInfo.CurrentCulture);
    public double WaterLiters => double.Parse(water.Text, CultureInfo.CurrentCulture);
    public MealSettingsWindow(JsonObject plan, DateTime defaultDeparture)
    {
        Title = "路餐行程与目标"; Width = 480; Height = 510; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var storedDeparture = plan["startDate"] is null ? defaultDeparture : MealService.FromSwiftDate(plan["startDate"]);
        departureTime = storedDeparture.TimeOfDay;
        departure.SelectedDate = storedDeparture.Date;
        days.Text = InventoryDocument.Int(plan["days"], 1).ToString(CultureInfo.InvariantCulture); people.Text = InventoryDocument.Int(plan["people"], 1).ToString(CultureInfo.InvariantCulture); goal.Text = InventoryDocument.Number(plan["dailyGoal"]).ToString("0.##", CultureInfo.CurrentCulture); water.Text = InventoryDocument.Number(plan["waterLiters"]).ToString("0.##", CultureInfo.CurrentCulture);
        var panel = new StackPanel { Margin = new Thickness(22) }; Add("出发日期", departure); Add("行程天数（1–60）", days); Add("人数（1–100）", people); Add("每人每日热量目标 kcal（0 表示不设）", goal); Add("全队出发携水 L", water);
        panel.Children.Add(new TextBlock { Text = "饮水按约 1 kg/L 计入打包重量；水瓶重量仍作为装备填写。减少天数前需先调整较晚日期的食物。", TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(0, 8, 0, 10) });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right }; var cancel = new Button { Content = "取消", Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(14, 7, 14, 7) }; cancel.Click += (_, _) => DialogResult = false; var save = new Button { Content = "保存行程", Padding = new Thickness(14, 7, 14, 7) }; save.Click += (_, _) => Save(); buttons.Children.Add(cancel); buttons.Children.Add(save); panel.Children.Add(buttons); Content = new ScrollViewer { Content = panel };
        void Add(string label, Control control) { panel.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, 5, 0, 3), Foreground = System.Windows.Media.Brushes.Gray }); control.Height = 32; control.Margin = new Thickness(0, 0, 0, 3); panel.Children.Add(control); }
    }
    private void Save() { try { if (Days is < 1 or > 60 || People is < 1 or > 100 || DailyGoal < 0 || WaterLiters < 0) throw new InvalidDataException("请检查天数、人数、热量和携水量。"); DialogResult = true; } catch (Exception error) { PageUi.Error(error); } }
}

public sealed class MealFoodWindow : Window
{
    private readonly TextBox name = new(), day = new(), quantity = new(), grams = new(), calories = new(), price = new(), notes = new();
    private readonly ComboBox meal = new(), preparation = new();
    public JsonObject Food { get; }
    public MealFoodWindow(JsonObject? existing, int maxDays)
    {
        Food = existing is null ? new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["quantity"] = 1, ["day"] = 1, ["meal"] = "行进零食", ["preparation"] = "即食", ["purchased"] = false, ["packed"] = false } : (JsonObject)existing.DeepClone();
        Title = existing is null ? "添加路餐" : "编辑路餐"; Width = 520; Height = 680; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        meal.ItemsSource = MealService.Meals; preparation.ItemsSource = MealService.Preparations;
        name.Text = Food["name"]?.ToString() ?? ""; day.Text = InventoryDocument.Int(Food["day"], 1).ToString(); quantity.Text = InventoryDocument.Number(Food["quantity"], 1).ToString("0.##"); grams.Text = InventoryDocument.Number(Food["grams"]).ToString("0.##"); calories.Text = InventoryDocument.Number(Food["calories"]).ToString("0.##"); price.Text = InventoryDocument.Number(Food["price"]).ToString("0.##"); notes.Text = Food["notes"]?.ToString() ?? ""; meal.SelectedItem = Food["meal"]?.ToString() ?? "行进零食"; preparation.SelectedItem = Food["preparation"]?.ToString() ?? "即食";
        var panel = new StackPanel { Margin = new Thickness(22) }; Add("食物名称", name); Add("第几天", day); Add("餐次", meal); Add("全队携带总份数", quantity); Add("每份包装重量 g", grams); Add("每份热量 kcal", calories); Add("每份价格 ¥", price); Add("准备方式", preparation); Add("备注、过敏原或补给点", notes);
        panel.Children.Add(new TextBlock { Text = $"本计划目前为 {maxDays} 天。重量、热量和价格按每份录入；份数填写全队总份数。若包装标示 kJ，先除以 4.184 转换为 kcal。", TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(0, 6, 0, 10) });
        var bar = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right }; var cancel = new Button { Content = "取消", Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(14, 7, 14, 7) }; cancel.Click += (_, _) => DialogResult = false; var save = new Button { Content = "保存食物", Padding = new Thickness(14, 7, 14, 7) }; save.Click += (_, _) => Save(); bar.Children.Add(cancel); bar.Children.Add(save); panel.Children.Add(bar); Content = new ScrollViewer { Content = panel };
        void Add(string label, Control control) { panel.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, 4, 0, 3), Foreground = System.Windows.Media.Brushes.Gray }); control.Height = 32; control.Margin = new Thickness(0, 0, 0, 3); panel.Children.Add(control); }
    }
    public void ApplyLabelResult(FoodLabelResult result)
    {
        if (!string.IsNullOrWhiteSpace(result.Name)) name.Text = result.Name;
        if (result.Grams is { } mass) grams.Text = mass.ToString("0.##", CultureInfo.CurrentCulture);
        if (result.Calories is { } energy) calories.Text = energy.ToString("0.##", CultureInfo.CurrentCulture);
        notes.Text = string.Join(" · ", new[] { "包装识别，请核对每份重量与热量", result.Message }.Where(value => !string.IsNullOrWhiteSpace(value)));
    }
    private void Save()
    {
        try
        {
            Food["name"] = name.Text.Trim(); Food["day"] = int.Parse(day.Text, CultureInfo.InvariantCulture); Food["meal"] = meal.SelectedItem?.ToString() ?? "行进零食"; Food["quantity"] = double.Parse(quantity.Text, CultureInfo.CurrentCulture); Food["grams"] = double.Parse(grams.Text, CultureInfo.CurrentCulture); Food["calories"] = double.Parse(calories.Text, CultureInfo.CurrentCulture); Food["price"] = double.Parse(price.Text, CultureInfo.CurrentCulture); Food["preparation"] = preparation.SelectedItem?.ToString() ?? "即食"; Food["notes"] = notes.Text;
            var copy = (JsonObject)Food.DeepClone();
            var validation = InventoryDocument.Empty();
            MealService.Configure(validation, DateTime.Today, Math.Max(1, InventoryDocument.Int(Food["day"], 1)), 1, 0, 0);
            MealService.AddOrUpdateFood(validation, copy);
            DialogResult = true;
        }
        catch (Exception error) { PageUi.Error(error); }
    }
}

public sealed class MealRecommendationWindow : Window
{
    private readonly TextBox days = new(), people = new(), start = new(), carry = new(), calories = new(); private readonly CheckBox resupply = new() { Content = "途中有已确认补给点" }, heat = new() { Content = "可以烧热水" }, reserve = new() { Content = "加 1 天备用粮", IsChecked = true };
    public int Days => int.Parse(days.Text); public int People => int.Parse(people.Text); public double DailyCalories => double.Parse(calories.Text, CultureInfo.CurrentCulture);
    public MealRecommendationOptions Options => new(Days, People, false, heat.IsChecked == true, resupply.IsChecked == true, int.Parse(carry.Text), int.Parse(start.Text), DailyCalories, reserve.IsChecked == true);
    public MealRecommendationWindow(JsonObject plan)
    {
        Title = "路餐推荐"; Width = 560; Height = 560; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        days.Text = InventoryDocument.Int(plan["days"], 1).ToString(); people.Text = InventoryDocument.Int(plan["people"], 1).ToString(); start.Text = "1"; carry.Text = Math.Min(5, InventoryDocument.Int(plan["days"], 1)).ToString(); calories.Text = (InventoryDocument.Number(plan["dailyGoal"]) > 0 ? InventoryDocument.Number(plan["dailyGoal"]) : 2500).ToString("0", CultureInfo.CurrentCulture);
        var panel = new StackPanel { Margin = new Thickness(22) }; Add("全程天数（1–60）", days); Add("人数（1–100）", people); Add("从第几天开始携带", start); Add("补给段携带天数", carry); Add("每人每日热量 kcal（1000–10000）", calories); panel.Children.Add(resupply); panel.Children.Add(heat); panel.Children.Add(reserve);
        panel.Children.Add(new TextBlock { Text = "推荐食物组合是可编辑的估值示例。请核对实际包装、口味与过敏原；补给点需要自行确认。", TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(0, 12, 0, 12) });
        var bar = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right }; var cancel = new Button { Content = "取消", Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(14, 7, 14, 7) }; cancel.Click += (_, _) => DialogResult = false; var add = new Button { Content = "生成并加入计划", Padding = new Thickness(14, 7, 14, 7) }; add.Click += (_, _) => Save(); bar.Children.Add(cancel); bar.Children.Add(add); panel.Children.Add(bar); Content = new ScrollViewer { Content = panel };
        resupply.Checked += (_, _) => start.IsEnabled = carry.IsEnabled = true; resupply.Unchecked += (_, _) => { start.IsEnabled = false; carry.IsEnabled = false; start.Text = "1"; };
        start.IsEnabled = carry.IsEnabled = false;
        void Add(string label, Control control) { panel.Children.Add(new TextBlock { Text = label, Margin = new Thickness(0, 5, 0, 3), Foreground = System.Windows.Media.Brushes.Gray }); control.Height = 32; control.Margin = new Thickness(0, 0, 0, 3); panel.Children.Add(control); }
    }
    private void Save() { try { _ = MealService.Recommend(Options); DialogResult = true; } catch (Exception error) { PageUi.Error(error); } }
}
