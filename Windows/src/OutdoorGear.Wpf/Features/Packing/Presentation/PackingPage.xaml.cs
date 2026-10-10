using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Input;
using System.IO;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;
using OutdoorGear.Wpf.Features.Meals.Presentation;
using OutdoorGear.Wpf.Features.Routes.Presentation;
using OutdoorGear.Wpf.Features.Shared.Presentation;
using OutdoorGear.Wpf.Features.Weather.Presentation;

namespace OutdoorGear.Wpf.Features.Packing.Presentation;

public partial class PackingPage : UserControl
{
    private readonly LibrarySession session;
    private ICollectionView? gearView;
    private RouteSummary? route;
    private int zoom = 11;
    private Point panOffset;
    private Point lastMapPointer;
    private bool draggingMap;
    private bool satelliteMap;
    private bool detailedWeather;
    private bool changingDeparture;
    private Border? borrowedSection;
    private readonly StackPanel borrowedRows = new();
    private static readonly string[] Times = Enumerable.Range(0, 24 * 60).Select(minute => $"{minute / 60:00}:{minute % 60:00}").ToArray();
    private static readonly HttpClient TileClient = CreateTileClient();

    public PackingPage(LibrarySession session)
    {
        InitializeComponent(); this.session = session; DataContext = session;
        session.RefreshBorrowedPackingItems();
        AttachBorrowedSection();
        Loaded += (_, _) => session.PropertyChanged += Session_PropertyChanged;
        Unloaded += (_, _) => session.PropertyChanged -= Session_PropertyChanged;
        PackingGrid.ItemsSource = CollectionViewSource.GetDefaultView(session.Rows);
        RefreshDepartureControls();
        gearView = CollectionViewSource.GetDefaultView(PackingGrid.ItemsSource); if (gearView is not null) gearView.Filter = FilterGear;
        CategoryList.SelectedValue = session.SelectedCategory;
        route = session.SelectedRoute; RefreshRoute(); RefreshPackingSummary();
        if (route is not null) _ = LoadWeatherAsync();
    }

    private void RefreshRoute()
    {
        RouteNameText.Text = route?.Name ?? "未选择路线"; RouteDistanceText.Text = route?.Distance ?? "搜索或导入路线后查看联动天气与轨迹";
        MapCaption.Text = route is null ? "选择路线以显示轨迹" : route.Area;
        RouteStats.Text = session.Terrain is { } terrain ? $"{route?.Distance} · 海拔 {terrain.Low:0}–{terrain.High:0} m · 平均 {terrain.Average:0} m" : route?.Distance ?? "路线距离与海拔将在选择路线后显示";
        DrawRoute(); if (route is not null) _ = LoadTilesAsync();
    }

    private async Task LoadWeatherAsync()
    {
        await session.LoadWeatherAsync();
        DisplayWeather();
    }

    private void DisplayWeather()
    {
        UpdateWeatherControls();
        if (session.ForecastOutOfRange) DisplayOutlookWeather();
        else DisplayDailyWeather();
        DisplayTerrain();
        RefreshPackingSummary();
    }

    private void UpdateWeatherControls()
    {
        WeatherStatus.Text = session.WeatherMessage;
        OutlookButton.IsEnabled = route is not null && session.Departure >= DateTime.Now;
        DetailedWeatherButton.Visibility = session.Forecast is null ? Visibility.Collapsed : Visibility.Visible;
        DetailedWeatherButton.Content = detailedWeather ? "收起详情" : "详细天气";
        DepartureWeatherTime.Visibility = Visibility.Collapsed;
        DepartureDayRange.Visibility = Visibility.Collapsed;
    }

    private void DisplayOutlookWeather()
    {
        ForecastList.Visibility = Visibility.Collapsed;
        WeatherTrendSummary.Visibility = Visibility.Visible;
        if (session.DepartureTrend is { } trend) DisplayTrend(trend);
        else DisplayUnavailableTrend();
    }

    private void DisplayTrend(WeatherTrend trend)
    {
        var period = trend.Monthly ? trend.Start[..7] : $"{trend.Start[5..]}–{trend.End[5..]}";
        var wind = trend.Wind is { } speed ? $" · 平均风速 {speed:0.#} km/h" : "";
        var cloud = trend.CloudCover is { } cover ? $" · 平均云量 {cover:0}%" : "";
        CurrentCondition.Text = $"{period} · {(trend.Monthly ? "月" : "周")}趋势";
        CurrentTemperature.Text = $"{trend.Temperature:0}°";
        FeelsLike.Text = $"气温较常年 {trend.TemperatureAnomaly:+0.0;-0.0;0}°";
        ElevationText.Text = "区域均值 · 不是出发当天预报";
        WeatherTrendSummary.Text = $"降水较常年 {trend.PrecipitationAnomaly:+0.0;-0.0;0} mm{wind}{cloud}\n远期趋势不能判断某天晴雨；临近出发时请重新查询逐日预报。";
    }

    private void DisplayUnavailableTrend()
    {
        CurrentCondition.Text = "远期趋势";
        CurrentTemperature.Text = "—°";
        FeelsLike.Text = "暂无对应趋势";
        ElevationText.Text = "区域趋势数据不可用";
        WeatherTrendSummary.Text = string.IsNullOrWhiteSpace(session.OutlookError) ? "所选日期不在当前季节趋势数据范围内。" : "远期趋势查询失败：" + session.OutlookError;
    }

    private void DisplayDailyWeather()
    {
        WeatherTrendSummary.Visibility = Visibility.Collapsed;
        ForecastList.Visibility = Visibility.Visible;
        if (session.Forecast is { } forecast) DisplayForecast(forecast);
        else DisplayUnavailableForecast();
    }

    private void DisplayForecast(WeatherForecast forecast)
    {
        CurrentCondition.Text = TripPlanningService.WeatherText(forecast.Departure.Code);
        CurrentTemperature.Text = $"{forecast.Departure.Temperature:0}°";
        FeelsLike.Text = $"体感 {forecast.Departure.FeelsLike:0}°";
        if (detailedWeather) DisplayDetailedForecastTime(forecast);
        ElevationText.Text = forecast.Elevation is { } elevation ? $"路线中心附近 · 网格海拔 {elevation:0} m" : "路线中心附近天气预报";
        ForecastList.ItemsSource = forecast.Days.Select(day => new ForecastCard(day, detailedWeather)).ToList();
    }

    private void DisplayDetailedForecastTime(WeatherForecast forecast)
    {
        DepartureWeatherTime.Text = "当地 " + forecast.Departure.Time.Replace('T', ' ');
        DepartureWeatherTime.Visibility = Visibility.Visible;
        if (forecast.Days.FirstOrDefault() is not { } today) return;
        DepartureDayRange.Text = $"最高 {today.High:0}° · 最低 {today.Low:0}°";
        DepartureDayRange.Visibility = Visibility.Visible;
    }

    private void DisplayUnavailableForecast()
    {
        CurrentCondition.Text = "—";
        CurrentTemperature.Text = "—°";
        FeelsLike.Text = "体感 —°";
        ElevationText.Text = route is null ? "路线网格海拔 —" : "路线中心附近天气预报";
        ForecastList.ItemsSource = null;
    }

    private void DisplayTerrain()
    {
        if (session.Terrain is { } terrain)
        {
            RouteStats.Text = $"{route?.Distance} · 海拔 {terrain.Low:0}–{terrain.High:0} m" + (terrain.Average is { } average ? $" · 平均 {average:0} m" : "");
            ElevationText.Text = $"路线海拔 {terrain.Low:0}–{terrain.High:0} m";
        }
    }

    private void RefreshPackingSummary()
    {
        var summary = session.Packing; TotalWeight.Text = $"{summary.WeightGrams / 1000:0.000} kg"; WeightGrams.Text = $"{summary.WeightGrams:0.##} g";
        PackValue.Text = $"{(summary.MissingPriceCount == 0 ? "装备价值" : "已知装备价值")} {session.FormatMoney(summary.GearCost)}"; SelectedCount.Text = $"已选 {summary.ItemCount} 项装备";
        PackValue.ToolTip = "按购买总价 ÷ 库内数量 × 携带数量计算，包含借用装备；未填价格的装备不计入。";
        PackSubSummary.Text = $"装备 {summary.WeightGrams - MealService.Summarize(session.Inventory).TotalWeightGrams:0} g · 路餐与水 {MealService.Summarize(session.Inventory).TotalWeightGrams:0} g";
        RefreshBorrowedRows();
    }

    private void Session_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(LibrarySession.Packing)) RefreshPackingSummary();
    }

    private void AttachBorrowedSection()
    {
        if (PackingGrid.Parent is not DockPanel parent) return;
        borrowedSection = new Border
        {
            Padding = new Thickness(10, 6, 10, 4),
            BorderBrush = (Brush)FindResource("LineBrush"),
            BorderThickness = new Thickness(0, 1, 0, 0),
            Child = BuildBorrowedPanel()
        };
        DockPanel.SetDock(borrowedSection, Dock.Bottom);
        parent.Children.Insert(parent.Children.IndexOf(PackingGrid), borrowedSection);
    }

    private UIElement BuildBorrowedPanel()
    {
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock { Text = "别人的装备", FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 4) });
        panel.Children.Add(new ScrollViewer { Content = borrowedRows, MaxHeight = 132, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        return panel;
    }

    private void RefreshBorrowedRows()
    {
        borrowedRows.Children.Clear();
        if (borrowedSection is null) return;
        var items = session.Inventory.BorrowedNodes.OfType<System.Text.Json.Nodes.JsonObject>().Where(MatchesBorrowedCategory).ToList();
        borrowedSection.Visibility = items.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        foreach (var item in items) borrowedRows.Children.Add(BuildBorrowedRow(item));
    }

    private bool MatchesBorrowedCategory(System.Text.Json.Nodes.JsonObject item)
    {
        var path = CategoryList.SelectedValue?.ToString() ?? "全部分类";
        var gear = item["gear"] as System.Text.Json.Nodes.JsonObject;
        if (path == "全部分类") return true;
        if (path == "已损坏") return gear?["status"]?.ToString() == "损坏";
        var parts = path.Split('/');
        return gear?["category"]?.ToString() == parts[0] &&
            (parts.Length == 1 || item["subcategory"]?.ToString() == parts[1]);
    }

    private UIElement BuildBorrowedRow(System.Text.Json.Nodes.JsonObject item)
    {
        var gear = item["gear"] as System.Text.Json.Nodes.JsonObject;
        var ownerId = item["ownerID"]?.ToString() ?? "";
        var gearId = gear?["id"]?.ToString() ?? "";
        var quantity = InventoryDocument.Number(item["quantity"]);
        var stock = InventoryDocument.Number(gear?["quantity"]);
        var weight = InventoryDocument.Number(gear?["weight"]);
        var unavailable = InventoryDocument.Bool(item["unavailable"]);
        var row = new DockPanel { Margin = new Thickness(0, 2, 0, 2) };
        var remove = PageUi.Button("移除", (_, _) => UpdateBorrowedQuantity(ownerId, gearId, null));
        DockPanel.SetDock(remove, Dock.Right);
        row.Children.Add(remove);
        var controls = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var decrease = PageUi.Button("−", (_, _) => UpdateBorrowedQuantity(ownerId, gearId, quantity - 1));
        decrease.IsEnabled = !unavailable && quantity > 1;
        controls.Children.Add(decrease);
        controls.Children.Add(new TextBlock { Text = $" {quantity:0.##} ", VerticalAlignment = VerticalAlignment.Center });
        var increase = PageUi.Button("＋", (_, _) => UpdateBorrowedQuantity(ownerId, gearId, Math.Min(stock, quantity + 1)));
        increase.IsEnabled = !unavailable && quantity < stock;
        controls.Children.Add(increase);
        DockPanel.SetDock(controls, Dock.Right);
        row.Children.Add(controls);
        var owner = item["ownerName"]?.ToString() ?? "其他用户";
        var name = gear?["name"]?.ToString() ?? "未命名装备";
        var message = unavailable ? "来源不可用 · 不计入重量" : $"{owner} · {weight * quantity:0.##} g";
        row.Children.Add(new TextBlock { Text = $"{name}  ·  {message}", VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis });
        return row;
    }

    private void UpdateBorrowedQuantity(string ownerId, string gearId, double? quantity)
    {
        try { session.SetBorrowedGearQuantity(ownerId, gearId, quantity); RefreshPackingSummary(); }
        catch (Exception error) { MessageBox.Show(error.Message, "借用装备", MessageBoxButton.OK, MessageBoxImage.Information); }
    }

    private bool FilterGear(object item)
    {
        if (item is not GearRowViewModel gear) return false;
        return SelectedOnly.IsChecked != true || gear.IsPacking;
    }

    private void Category_Selected(object sender, SelectionChangedEventArgs e)
    {
        if (CategoryList.SelectedValue is string path) { session.SetCategory(path); gearView?.Refresh(); RefreshBorrowedRows(); }
    }
    private void GearSearch_TextChanged(object sender, TextChangedEventArgs e) { if (session is not null) session.SetSearch(GearSearch.Text); gearView?.Refresh(); }
    private void SelectedOnly_Changed(object sender, RoutedEventArgs e) => gearView?.Refresh();

    private async void SearchRoute_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new RouteSearchWindow(session.Trip) { Owner = Window.GetWindow(this) };
        if (dialog.ShowDialog() == true && dialog.SelectedRoute is { } selection) { await session.SelectRouteAsync(selection); route = session.SelectedRoute; panOffset = new Point(0, 0); RefreshRoute(); DisplayWeather(); }
        RefreshPackingSummary();
    }

    private void RemoveRoute_Click(object sender, RoutedEventArgs e) { session.RemoveRoute(); route = null; RefreshRoute(); DisplayWeather(); }
    private async void RefreshWeather_Click(object sender, RoutedEventArgs e) => await LoadWeatherAsync();
    private void ToggleDetailedWeather_Click(object sender, RoutedEventArgs e) { detailedWeather = !detailedWeather; DisplayWeather(); }
    private async void DepartureChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded || changingDeparture || DepartureDate.SelectedDate is not { } date) return;
        if (UpdateDeparture(date, null)) await LoadWeatherAsync();
    }
    private async void DepartureTime_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded || changingDeparture || DepartureTime.SelectedItem is not string time) return;
        if (UpdateDeparture(DepartureDate.SelectedDate ?? DateTime.Today, time)) await LoadWeatherAsync();
    }
    private bool UpdateDeparture(DateTime date, string? time)
    {
        var chosen = time is null ? session.Departure.TimeOfDay : TimeSpan.Parse(time);
        var departure = DateTime.SpecifyKind(date.Date + chosen, DateTimeKind.Local);
        var now = DateTime.Now;
        var earliestSelectable = now.Date.AddHours(now.Hour).AddMinutes(now.Minute + 1);
        if (departure < earliestSelectable) departure = earliestSelectable;
        try { session.Departure = departure; }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "出发时间", MessageBoxButton.OK, MessageBoxImage.Information);
            RefreshDepartureControls();
            return false;
        }
        RefreshDepartureControls();
        return true;
    }

    private void RefreshDepartureControls()
    {
        changingDeparture = true;
        try
        {
            DepartureDate.SelectedDate = session.Departure.Date;
            DepartureTime.ItemsSource = Times;
            DepartureTime.SelectedItem = $"{session.Departure.Hour:00}:{session.Departure.Minute:00}";
        }
        finally { changingDeparture = false; }
    }

    public void RefreshPackingAfterMealPlanChange()
    {
        var departureChanged = session.RefreshDepartureFromMealPlan();
        if (departureChanged) RefreshDepartureControls();
        RefreshPackingSummary();
        if (departureChanged && route is not null) _ = LoadWeatherAsync();
    }

    private async void Outlook_Click(object sender, RoutedEventArgs e)
    {
        if (session.Departure < DateTime.Now) return;
        try
        {
            await session.LoadOutlookAsync();
            var dialog = new SeasonalOutlookWindow(session.Outlook!, session.Departure) { Owner = Window.GetWindow(this) }; dialog.ShowDialog();
        }
        catch (Exception error) { MessageBox.Show(error.Message, "远期趋势", MessageBoxButton.OK, MessageBoxImage.Information); }
    }

    private void ClearPacking_Click(object sender, RoutedEventArgs e)
    {
        if (session.Packing.ItemCount == 0) return;
        session.ClearPacking(); RefreshPackingSummary(); gearView?.Refresh();
    }
    private void UndoClear_Click(object sender, RoutedEventArgs e) { session.UndoClearPacking(); RefreshPackingSummary(); gearView?.Refresh(); }
    private void IncreaseQuantity_Click(object sender, RoutedEventArgs e) => ChangeQuantity(sender, 1);
    private void DecreaseQuantity_Click(object sender, RoutedEventArgs e) => ChangeQuantity(sender, -1);
    private void ChangeQuantity(object sender, double delta)
    {
        if (sender is Button { Tag: GearRowViewModel row })
        {
            try { if (!row.IsPacking) row.IsPacking = true; row.PackQuantity = Math.Clamp(row.PackQuantity + delta, 1, row.Quantity); RefreshPackingSummary(); }
            catch (Exception error) { MessageBox.Show(error.Message, "打包数量", MessageBoxButton.OK, MessageBoxImage.Information); }
        }
    }

    private void Tab_Checked(object sender, RoutedEventArgs e)
    {
        if (EquipmentContent is null || MealContent is null || EquipmentTab is null) return;
        var equipment = EquipmentTab.IsChecked == true; EquipmentContent.Visibility = equipment ? Visibility.Visible : Visibility.Collapsed; MealContent.Visibility = equipment ? Visibility.Collapsed : Visibility.Visible;
        if (!equipment) MealContent.Content = new MealPlannerPage(session, RefreshPackingAfterMealPlanChange);
    }

    private void RouteCanvas_SizeChanged(object sender, SizeChangedEventArgs e) { DrawRoute(); if (route is not null) _ = LoadTilesAsync(); }
    private void DrawRoute()
    {
        if (RouteCanvas is null || RouteLine is null) return;
        foreach (var line in RouteCanvas.Children.OfType<Polyline>().Where(line => !ReferenceEquals(line, RouteLine)).ToList()) RouteCanvas.Children.Remove(line);
        foreach (var marker in RouteCanvas.Children.OfType<Ellipse>().Where(marker => marker.Tag?.ToString() == "route-marker").ToList()) RouteCanvas.Children.Remove(marker);
        RouteLine.Points = [];
        if (route is null || RouteCanvas.ActualWidth < 2 || RouteCanvas.ActualHeight < 2) return;
        var center = TileCoordinates(route.Center, zoom);
        var tileCenter = new Point(center.X * 256, center.Y * 256);
        var canvasCenter = new Point(RouteCanvas.ActualWidth / 2, RouteCanvas.ActualHeight / 2);
        var segments = route.Segments.Where(segment => segment.Count > 1).ToList();
        for (var index = 0; index < segments.Count; index++)
        {
            var line = index == 0 ? RouteLine : new Polyline { Stroke = RouteLine.Stroke, StrokeThickness = RouteLine.StrokeThickness, IsHitTestVisible = false };
            line.Points = new PointCollection(segments[index].Select(point =>
            {
                var projected = TileCoordinates(point, zoom);
                return new Point(canvasCenter.X + panOffset.X + projected.X * 256 - tileCenter.X, canvasCenter.Y + panOffset.Y + projected.Y * 256 - tileCenter.Y);
            }));
            if (index > 0) { RouteCanvas.Children.Add(line); Panel.SetZIndex(line, 1); }
        }
        if (segments.Count == 0)
        {
            var marker = new Ellipse { Width = 16, Height = 16, Fill = Brushes.Gold, Stroke = Brushes.White, StrokeThickness = 2, ToolTip = route.Name, Tag = "route-marker" };
            Canvas.SetLeft(marker, canvasCenter.X + panOffset.X - marker.Width / 2);
            Canvas.SetTop(marker, canvasCenter.Y + panOffset.Y - marker.Height / 2);
            RouteCanvas.Children.Add(marker);
            Panel.SetZIndex(marker, 2);
        }
    }

    private void ZoomIn_Click(object sender, RoutedEventArgs e) { zoom = Math.Min(16, zoom + 1); DrawRoute(); _ = LoadTilesAsync(); }
    private void ZoomOut_Click(object sender, RoutedEventArgs e) { zoom = Math.Max(4, zoom - 1); DrawRoute(); _ = LoadTilesAsync(); }

    private void RouteCanvas_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (route is null || e.OriginalSource is not Canvas) return;
        draggingMap = true;
        lastMapPointer = e.GetPosition(RouteCanvas);
        RouteCanvas.CaptureMouse();
        RouteCanvas.Cursor = Cursors.SizeAll;
        e.Handled = true;
    }

    private void RouteCanvas_MouseMove(object sender, MouseEventArgs e)
    {
        if (!draggingMap) return;
        var pointer = e.GetPosition(RouteCanvas);
        var movement = pointer - lastMapPointer;
        lastMapPointer = pointer;
        panOffset += movement;
        foreach (var tile in RouteCanvas.Children.OfType<System.Windows.Controls.Image>().Where(image => image.Tag?.ToString() == "map-tile"))
        {
            Canvas.SetLeft(tile, Canvas.GetLeft(tile) + movement.X);
            Canvas.SetTop(tile, Canvas.GetTop(tile) + movement.Y);
        }
        DrawRoute();
    }

    private async void RouteCanvas_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!draggingMap) return;
        draggingMap = false;
        RouteCanvas.ReleaseMouseCapture();
        RouteCanvas.Cursor = null;
        await LoadTilesAsync();
    }
    private void ExpandMap_Click(object sender, RoutedEventArgs e)
    {
        if (route is null) return;
        var window = new RouteMapWindow(route, zoom, session.Terrain) { Owner = Window.GetWindow(this) }; window.ShowDialog();
    }

    private async Task LoadTilesAsync()
    {
        if (route is null || RouteCanvas.ActualWidth < 2 || RouteCanvas.ActualHeight < 2) return;
        foreach (var oldTile in RouteCanvas.Children.OfType<System.Windows.Controls.Image>().Where(image => image.Tag?.ToString() == "map-tile").ToList()) RouteCanvas.Children.Remove(oldTile);
        var center = TileCoordinates(route.Center, zoom); var tileSize = 256d; var centerX = RouteCanvas.ActualWidth / 2; var centerY = RouteCanvas.ActualHeight / 2;
        var visibleCenterX = center.X - panOffset.X / tileSize; var visibleCenterY = center.Y - panOffset.Y / tileSize;
        var firstX = (int)Math.Floor(visibleCenterX - centerX / tileSize); var firstY = (int)Math.Floor(visibleCenterY - centerY / tileSize);
        var lastX = (int)Math.Floor(visibleCenterX + centerX / tileSize); var lastY = (int)Math.Floor(visibleCenterY + centerY / tileSize);
        try
        {
            for (var x = firstX; x <= lastX; x++) for (var y = firstY; y <= lastY; y++)
            {
                if (y < 0 || y >= (1 << zoom)) continue;
                var canonicalX = (x % (1 << zoom) + (1 << zoom)) % (1 << zoom); var bytes = await MapTileService.LoadAsync(TileClient, zoom, canonicalX, y, satelliteMap);
                var image = new System.Windows.Controls.Image { Source = Bitmap(bytes), Width = tileSize, Height = tileSize, IsHitTestVisible = false, Opacity = 0.82, Tag = "map-tile" };
                Canvas.SetLeft(image, centerX + panOffset.X + (x - center.X) * tileSize); Canvas.SetTop(image, centerY + panOffset.Y + (y - center.Y) * tileSize); RouteCanvas.Children.Insert(0, image);
            }
            Panel.SetZIndex(RouteLine, 1); MapCaption.Text = MapTileService.Attribution(satelliteMap);
            RouteCanvas.Background = new SolidColorBrush(Color.FromRgb(24, 58, 55));
        }
        catch { MapCaption.Text = "地图暂不可用 · 线路仍显示在本机"; }
    }

    private static Point TileCoordinates(TrailCoordinate point, int zoom)
    {
        var count = 1 << zoom; var lat = Math.Clamp(point.Latitude, -85.0511, 85.0511) * Math.PI / 180;
        return new Point((point.Longitude + 180) / 360 * count, (1 - Math.Log(Math.Tan(lat) + 1 / Math.Cos(lat)) / Math.PI) / 2 * count);
    }
    private void MapType_Click(object sender, RoutedEventArgs e) { satelliteMap = !satelliteMap; MapModeButton.Content = satelliteMap ? "标准地图" : "卫星地图"; DrawRoute(); _ = LoadTilesAsync(); }
    private static BitmapImage Bitmap(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes); var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze(); return bitmap;
    }
    private static HttpClient CreateTileClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) }; client.DefaultRequestHeaders.UserAgent.ParseAdd("OutdoorGearLibraryWindows/0.20.4 (personal offline-first hiking app)"); return client;
    }

    private sealed class ForecastCard(WeatherDay day, bool detailed)
    {
        public string DayLabel => DateTime.TryParse(day.Id, out var value) ? value.ToString("MM-dd") : day.Id;
        public string Condition => TripPlanningService.WeatherText(day.Code);
        public string TemperatureLabel => $"{day.Low:0}–{day.High:0}°";
        public string RainLabel => $"降水 {day.RainChance:0}%";
        public string WindLabel => detailed ? $"风速 {day.Wind:0} km/h" : "";
    }
}
