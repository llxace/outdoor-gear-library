using System.IO;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Input;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;

namespace OutdoorGear.Wpf.Features.Routes.Presentation;

public sealed class RouteMapWindow : Window
{
    private static readonly HttpClient TileClient = CreateTileClient();
    private readonly RouteSummary route;
    private readonly Canvas canvas = new() { Background = new SolidColorBrush(Color.FromRgb(24, 58, 55)), ClipToBounds = true };
    private readonly TextBlock status = new() { Text = "OpenStreetMap", Foreground = Brushes.White, Background = new SolidColorBrush(Color.FromArgb(180, 20, 35, 33)), Padding = new Thickness(8) };
    private readonly List<Polyline> routeLines = [];
    private readonly TerrainSummary? terrain;
    private Ellipse? routeMarker;
    private int zoom;
    private Point panOffset;
    private Point lastMapPointer;
    private bool draggingMap;
    private bool satelliteMap;
    private Button mapModeButton = null!;

    public RouteMapWindow(RouteSummary route, int initialZoom, TerrainSummary? terrain = null)
    {
        this.route = route;
        this.terrain = terrain;
        zoom = Math.Clamp(initialZoom, 4, 18);
        Title = $"路线地图 · {route.Name}";
        Width = 1100;
        Height = 760;
        MinWidth = 600;
        MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = CreateLayout();
        Loaded += async (_, _) => await RefreshMapAsync();
        canvas.SizeChanged += async (_, _) => await RefreshMapAsync();
        canvas.MouseLeftButtonDown += Canvas_MouseLeftButtonDown;
        canvas.MouseMove += Canvas_MouseMove;
        canvas.MouseLeftButtonUp += Canvas_MouseLeftButtonUp;
    }

    private UIElement CreateLayout()
    {
        var root = new Grid { Margin = new Thickness(12) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 220 });
        root.Children.Add(canvas);
        var metrics = new StackPanel { Margin = new Thickness(16, 34, 8, 8) };
        metrics.Children.Add(new TextBlock { Text = "路线概览", FontSize = 18, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 14) });
        metrics.Children.Add(new TextBlock { Text = $"路线长度\n{route.Distance}", Margin = new Thickness(0, 0, 0, 12) });
        metrics.Children.Add(new TextBlock { Text = terrain is null ? "海拔数据暂不可用" : $"最低海拔\n{terrain.Low:0} m", Margin = new Thickness(0, 0, 0, 12) });
        if (terrain is not null)
        {
            metrics.Children.Add(new TextBlock { Text = $"最高海拔\n{terrain.High:0} m\n\n平均海拔\n{(terrain.Average is { } average ? $"{average:0} m" : "—")}\n\n累计爬升 / 下降\n{(terrain.Ascent is { } ascent ? $"{ascent:0} m" : "—")} / {(terrain.Descent is { } descent ? $"{descent:0} m" : "—")}", Margin = new Thickness(0, 0, 0, 12) });
            metrics.Children.Add(new TextBlock { Text = terrain.Source, TextWrapping = TextWrapping.Wrap, Foreground = Brushes.Gray, FontSize = 12 });
        }
        Grid.SetColumn(metrics, 1); root.Children.Add(metrics);
        var toolbar = new DockPanel { LastChildFill = false, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(10) };
        toolbar.Children.Add(status);
        var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        mapModeButton = new Button { Content = "卫星地图", Height = 44, Margin = new Thickness(4, 0, 0, 0), Padding = new Thickness(10, 0, 10, 0) };
        mapModeButton.Click += async (_, _) => { satelliteMap = !satelliteMap; mapModeButton.Content = satelliteMap ? "标准地图" : "卫星地图"; await RefreshMapAsync(); };
        controls.Children.Add(mapModeButton);
        controls.Children.Add(MapButton("−", -1));
        controls.Children.Add(MapButton("+", 1));
        DockPanel.SetDock(controls, Dock.Right);
        toolbar.Children.Add(controls);
        Grid.SetColumnSpan(toolbar, 2); root.Children.Add(toolbar);
        return root;
    }

    private Button MapButton(string label, int delta)
    {
        var button = new Button { Content = label, FontSize = 22, Width = 48, Height = 44, Margin = new Thickness(4, 0, 0, 0) };
        button.Click += async (_, _) => { zoom = Math.Clamp(zoom + delta, 4, 18); await RefreshMapAsync(); };
        return button;
    }

    private async Task RefreshMapAsync()
    {
        if (canvas.ActualWidth < 2 || canvas.ActualHeight < 2) return;
        var center = TileCoordinates(route.Center, zoom);
        var visibleCenter = new Point(center.X - panOffset.X / 256, center.Y - panOffset.Y / 256);
        var firstX = (int)Math.Floor(visibleCenter.X - canvas.ActualWidth / 512);
        var lastX = (int)Math.Floor(visibleCenter.X + canvas.ActualWidth / 512);
        var firstY = (int)Math.Floor(visibleCenter.Y - canvas.ActualHeight / 512);
        var lastY = (int)Math.Floor(visibleCenter.Y + canvas.ActualHeight / 512);
        if ((lastX - firstX) * (lastY - firstY) > 100) return;
        canvas.Children.Clear(); routeLines.Clear(); routeMarker = null;
        status.Text = $"正在加载地图 · 缩放 {zoom}";
        try
        {
            await DrawTilesAsync(center, firstX, lastX, firstY, lastY);
            DrawRoute();
            foreach (var line in routeLines) canvas.Children.Add(line);
            status.Text = MapTileService.Attribution(satelliteMap);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or TaskCanceledException)
        {
            DrawRoute();
            foreach (var line in routeLines) canvas.Children.Add(line);
            status.Text = "底图暂不可用，仍显示路线 · " + MapTileService.Attribution(satelliteMap);
        }
    }

    private async Task DrawTilesAsync(Point center, int firstX, int lastX, int firstY, int lastY)
    {
        var count = 1 << zoom;
        for (var x = firstX; x <= lastX; x++)
            for (var y = firstY; y <= lastY; y++)
            {
                if (y < 0 || y >= count) continue;
                var canonicalX = (x % count + count) % count;
                var bytes = await MapTileService.LoadAsync(TileClient, zoom, canonicalX, y, satelliteMap);
                var image = new Image { Source = CreateBitmap(bytes), Width = 256, Height = 256, IsHitTestVisible = false, Tag = new Point(x, y) };
                Canvas.SetLeft(image, canvas.ActualWidth / 2 + panOffset.X + (x - center.X) * 256);
                Canvas.SetTop(image, canvas.ActualHeight / 2 + panOffset.Y + (y - center.Y) * 256);
                canvas.Children.Add(image);
            }
    }

    private void DrawRoute()
    {
        var mapCenter = TileCoordinates(route.Center, zoom);
        var segments = route.Segments.Where(points => points.Count > 1).ToList();
        foreach (var segment in segments)
        {
            var line = new Polyline { Stroke = new SolidColorBrush(Color.FromRgb(14, 155, 255)), StrokeThickness = 4, StrokeLineJoin = PenLineJoin.Round };
            line.Points = new PointCollection(segment.Select(point =>
            {
                var projected = TileCoordinates(point, zoom);
                return new Point(canvas.ActualWidth / 2 + panOffset.X + (projected.X - mapCenter.X) * 256, canvas.ActualHeight / 2 + panOffset.Y + (projected.Y - mapCenter.Y) * 256);
            }));
            routeLines.Add(line);
        }
        if (segments.Count == 0)
        {
            routeMarker = new Ellipse { Width = 16, Height = 16, Fill = Brushes.Gold, Stroke = Brushes.White, StrokeThickness = 2, ToolTip = route.Name };
            Canvas.SetLeft(routeMarker, canvas.ActualWidth / 2 + panOffset.X - routeMarker.Width / 2);
            Canvas.SetTop(routeMarker, canvas.ActualHeight / 2 + panOffset.Y - routeMarker.Height / 2);
            canvas.Children.Add(routeMarker);
        }
    }

    private void Canvas_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        draggingMap = true;
        lastMapPointer = e.GetPosition(canvas);
        canvas.CaptureMouse();
        canvas.Cursor = Cursors.SizeAll;
        e.Handled = true;
    }

    private void Canvas_MouseMove(object sender, MouseEventArgs e)
    {
        if (!draggingMap) return;
        var pointer = e.GetPosition(canvas);
        panOffset += pointer - lastMapPointer;
        lastMapPointer = pointer;
        PositionMapElements();
    }

    private async void Canvas_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!draggingMap) return;
        draggingMap = false;
        canvas.ReleaseMouseCapture();
        canvas.Cursor = null;
        await RefreshMapAsync();
    }

    private void PositionMapElements()
    {
        var center = TileCoordinates(route.Center, zoom);
        foreach (var image in canvas.Children.OfType<Image>())
        {
            if (image.Tag is not Point tile) continue;
            Canvas.SetLeft(image, canvas.ActualWidth / 2 + panOffset.X + (tile.X - center.X) * 256);
            Canvas.SetTop(image, canvas.ActualHeight / 2 + panOffset.Y + (tile.Y - center.Y) * 256);
        }
        var segments = route.Segments.Where(points => points.Count > 1).ToList();
        for (var index = 0; index < Math.Min(segments.Count, routeLines.Count); index++)
        {
            routeLines[index].Points = new PointCollection(segments[index].Select(point =>
            {
                var projected = TileCoordinates(point, zoom);
                return new Point(canvas.ActualWidth / 2 + panOffset.X + (projected.X - center.X) * 256, canvas.ActualHeight / 2 + panOffset.Y + (projected.Y - center.Y) * 256);
            }));
        }
        if (routeMarker is not null)
        {
            Canvas.SetLeft(routeMarker, canvas.ActualWidth / 2 + panOffset.X - routeMarker.Width / 2);
            Canvas.SetTop(routeMarker, canvas.ActualHeight / 2 + panOffset.Y - routeMarker.Height / 2);
        }
    }

    private static Point TileCoordinates(TrailCoordinate coordinate, int level)
    {
        var count = 1 << level;
        var latitude = Math.Clamp(coordinate.Latitude, -85.0511, 85.0511) * Math.PI / 180;
        return new Point((coordinate.Longitude + 180) / 360 * count, (1 - Math.Log(Math.Tan(latitude) + 1 / Math.Cos(latitude)) / Math.PI) / 2 * count);
    }

    private static BitmapImage CreateBitmap(byte[] bytes)
    {
        using var stream = new MemoryStream(bytes);
        var bitmap = new BitmapImage();
        bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze();
        return bitmap;
    }

    private static HttpClient CreateTileClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("OutdoorGearLibraryWindows/0.20.4 (personal offline-first hiking app)");
        return client;
    }
}
