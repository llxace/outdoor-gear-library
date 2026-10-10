using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.Features.Shared.Presentation;

namespace OutdoorGear.Wpf.Features.Routes.Presentation;

public sealed class RouteSearchWindow : Window
{
    private readonly TripPlanningService trip;
    private readonly TextBox query = new() { Width = 300, Height = 34 };
    private readonly TextBox placeQuery = new() { Width = 230, Height = 32 };
    private readonly ComboBox radius = new() { Width = 88, ItemsSource = new[] { 10, 30, 60 }, SelectedIndex = 1 };
    private readonly ListBox namedRoutes = new() { DisplayMemberPath = nameof(RouteSummary.Name), SelectionMode = SelectionMode.Extended };
    private readonly ListBox places = new() { DisplayMemberPath = nameof(PlaceResult.Name), Height = 130 };
    private readonly ListBox nearbyRoutes = new() { DisplayMemberPath = nameof(RouteSummary.Name), SelectionMode = SelectionMode.Extended };
    private readonly TabControl tabs = new();
    private readonly TextBlock status = new() { Text = "可搜索离线路线库与在线路线。", TextWrapping = TextWrapping.Wrap };
    private readonly Button cancelSearchButton = new() { Content = "取消搜索", Margin = new Thickness(0, 0, 8, 8), Padding = new Thickness(12, 7, 12, 7), IsEnabled = false };
    private Button namedSearchButton = null!;
    private Button placeSearchButton = null!;
    private Button nearbySearchButton = null!;
    private CancellationTokenSource? searchCancellation;
    public RouteSummary? SelectedRoute { get; private set; }

    public RouteSearchWindow(TripPlanningService trip)
    {
        this.trip = trip; Title = "选择徒步路线"; Width = 720; Height = 620;
        cancelSearchButton.Click += CancelSearch;
        Closed += (_, _) => searchCancellation?.Cancel();
        WindowStartupLocation = WindowStartupLocation.CenterOwner; Content = BuildLayout();
    }

    private DockPanel BuildLayout()
    {
        var root = new DockPanel { Margin = new Thickness(18) };
        var footer = BuildFooter();
        DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        tabs.Items.Add(new TabItem { Header = "按路线名称搜索", Content = BuildNameTab() });
        tabs.Items.Add(new TabItem { Header = "按地点找附近路线", Content = BuildNearbyTab() });
        root.Children.Add(tabs);
        return root;
    }

    private DockPanel BuildNameTab()
    {
        var panel = new DockPanel { Margin = new Thickness(0, 12, 0, 0) };
        var search = new StackPanel { Orientation = Orientation.Horizontal };
        namedSearchButton = PageUi.Button("搜索", SearchNamed);
        search.Children.Add(query); search.Children.Add(namedSearchButton);
        DockPanel.SetDock(search, Dock.Top); panel.Children.Add(search); panel.Children.Add(namedRoutes);
        return panel;
    }

    private DockPanel BuildNearbyTab()
    {
        var panel = new DockPanel { Margin = new Thickness(0, 12, 0, 0) };
        var search = new StackPanel { Orientation = Orientation.Horizontal };
        placeSearchButton = PageUi.Button("搜索地点", SearchPlaces);
        search.Children.Add(placeQuery); search.Children.Add(radius); search.Children.Add(placeSearchButton);
        DockPanel.SetDock(search, Dock.Top); panel.Children.Add(search);
        var locationPanel = new DockPanel { Margin = new Thickness(0, 10, 0, 8) };
        nearbySearchButton = PageUi.Button("查找该地点附近路线", SearchNearby); DockPanel.SetDock(nearbySearchButton, Dock.Bottom);
        var weather = PageUi.Button("仅按此地点查看天气", UsePlaceForWeather); DockPanel.SetDock(weather, Dock.Bottom);
        locationPanel.Children.Add(nearbySearchButton); locationPanel.Children.Add(weather); locationPanel.Children.Add(places);
        DockPanel.SetDock(locationPanel, Dock.Top); panel.Children.Add(locationPanel); panel.Children.Add(nearbyRoutes);
        return panel;
    }

    private StackPanel BuildFooter()
    {
        var footer = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
        footer.Children.Add(new TextBlock { Text = "按住 Ctrl 可组合多段路线。在线路线数据由 Waymarked Trails / OpenStreetMap 提供。", Foreground = System.Windows.Media.Brushes.Gray, TextWrapping = TextWrapping.Wrap });
        footer.Children.Add(status);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 10, 0, 0) };
        actions.Children.Add(cancelSearchButton);
        actions.Children.Add(PageUi.Button("导入 GPX / KML", ImportTrack));
        actions.Children.Add(PageUi.Button("预览所选路线", PreviewRoute));
        actions.Children.Add(PageUi.Button("选择路线", SelectRoute)); footer.Children.Add(actions);
        return footer;
    }

    private async void SearchNamed(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(query.Text)) { status.Text = "请输入路线名称。"; return; }
        namedRoutes.ItemsSource = null;
        await RunSearch(async token => { namedRoutes.ItemsSource = await trip.SearchNamedRoutesAsync(query.Text, token); }, "路线搜索完成");
    }

    private async void SearchPlaces(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(placeQuery.Text)) { status.Text = "请输入城市、景区或山名。"; return; }
        places.ItemsSource = null; nearbyRoutes.ItemsSource = null;
        await RunSearch(async token => { places.ItemsSource = await trip.SearchPlacesAsync(placeQuery.Text, token); }, "地点搜索完成");
    }

    private async void SearchNearby(object sender, RoutedEventArgs e)
    {
        if (places.SelectedItem is not PlaceResult place) { status.Text = "请先搜索并选择一个地点。"; return; }
        var kilometers = radius.SelectedItem is int selected ? selected : 30;
        nearbyRoutes.ItemsSource = null;
        await RunSearch(async token => { nearbyRoutes.ItemsSource = await trip.SearchNearbyRoutesAsync(place, kilometers, token); }, "附近路线搜索完成");
    }

    private void UsePlaceForWeather(object sender, RoutedEventArgs e)
    {
        if (places.SelectedItem is not PlaceResult place) { status.Text = "请先搜索并选择一个地点。"; return; }
        SelectedRoute = new RouteSummary(DateTimeOffset.UtcNow.Ticks, place.Name, "天气目的地", place.Point, "", [], IsDestinationOnly: true);
        DialogResult = true;
    }

    private async Task RunSearch(Func<CancellationToken, Task> search, string success)
    {
        if (searchCancellation is not null) return;
        var cancellation = new CancellationTokenSource();
        searchCancellation = cancellation;
        SetSearchBusy(true);
        status.Text = "正在搜索…";
        try { await search(cancellation.Token); status.Text = success; }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { status.Text = "搜索已取消。"; }
        catch (Exception error) { status.Text = error.Message; }
        finally { searchCancellation = null; cancellation.Dispose(); SetSearchBusy(false); }
    }

    private void CancelSearch(object sender, RoutedEventArgs e)
    {
        if (searchCancellation is null) return;
        status.Text = "正在取消搜索…";
        searchCancellation.Cancel();
    }

    private void SetSearchBusy(bool busy)
    {
        namedSearchButton.IsEnabled = !busy;
        placeSearchButton.IsEnabled = !busy;
        nearbySearchButton.IsEnabled = !busy;
        cancelSearchButton.IsEnabled = busy;
    }

    private async void SelectRoute(object sender, RoutedEventArgs e)
    {
        var selected = CurrentSelection();
        if (selected.Count == 0) { status.Text = "请先选择一条路线。"; return; }
        try
        {
            SelectedRoute = await LoadSelection(selected);
            DialogResult = true;
        }
        catch (Exception error) { status.Text = "路线载入失败：" + error.Message; }
    }

    private async void PreviewRoute(object sender, RoutedEventArgs e)
    {
        var selected = CurrentSelection();
        if (selected.Count == 0) { status.Text = "请先选择一条路线。"; return; }
        try
        {
            var route = await LoadSelection(selected);
            var terrain = await trip.TerrainAsync(route);
            new RouteMapWindow(route, 11, terrain) { Owner = this }.ShowDialog();
        }
        catch (Exception error) { status.Text = "路线预览失败：" + error.Message; }
    }

    private List<RouteSummary> CurrentSelection() => tabs.SelectedIndex == 0
        ? namedRoutes.SelectedItems.OfType<RouteSummary>().ToList()
        : nearbyRoutes.SelectedItems.OfType<RouteSummary>().ToList();

    private async Task<RouteSummary> LoadSelection(IReadOnlyList<RouteSummary> selected)
    {
        var detailed = await Task.WhenAll(selected.Select(route => trip.LoadRouteAsync(route)));
        return detailed.Length == 1 ? detailed[0] : Combine(detailed);
    }

    private static RouteSummary Combine(IReadOnlyList<RouteSummary> routes)
    {
        var segments = routes.SelectMany(route => route.Segments).ToList();
        if (segments.Count == 0 || segments.Any(segment => segment.Count < 2)) throw new InvalidDataException("所选路线没有可组合的有效轨迹。");
        var points = segments.SelectMany(segment => segment).ToList();
        var center = new TrailCoordinate(points.Average(point => point.Latitude), points.Average(point => point.Longitude));
        var distance = TrailFileReader.DistanceMeters(segments) / 1000;
        var area = string.Join("、", routes.Select(route => route.Area).Where(value => !string.IsNullOrWhiteSpace(value)).Distinct());
        return new RouteSummary(DateTimeOffset.UtcNow.Ticks, $"自定义路线（{routes.Count} 段）", area, center, $"{distance:0.0} km（组合估算）", segments);
    }

    private void ImportTrack(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "GPX / KML 轨迹|*.gpx;*.kml" };
        if (dialog.ShowDialog() != true) return;
        try
        {
            using var stream = File.OpenRead(dialog.FileName);
            var trail = TrailFileReader.Read(dialog.FileName, stream);
            SelectedRoute = new RouteSummary(trail.Id, trail.Name, trail.Area, trail.Center, trail.Distance, trail.Segments, trail.ImportedFile);
            DialogResult = true;
        }
        catch (Exception error) { status.Text = "导入失败：" + error.Message; }
    }
}
