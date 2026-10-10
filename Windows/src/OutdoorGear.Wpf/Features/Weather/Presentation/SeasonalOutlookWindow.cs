using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using OutdoorGear.Core.Services;

namespace OutdoorGear.Wpf.Features.Weather.Presentation;

public sealed class SeasonalOutlookWindow : Window
{
    private static readonly Curve[] Curves =
    [
        new("平均气温", "°C", Colors.Orange, trend => trend.Temperature),
        new("气温较常年差值", "°C", Colors.Red, trend => trend.TemperatureAnomaly, true),
        new("降水较常年差值", "mm", Colors.DodgerBlue, trend => trend.PrecipitationAnomaly, true),
        new("平均风速", "km/h", Colors.MediumAquamarine, trend => trend.Wind),
        new("平均云量", "%", Colors.MediumPurple, trend => trend.CloudCover)
    ];

    private readonly SeasonalOutlook outlook;
    private readonly DateTime departure;
    private readonly TabControl periods = new();
    private readonly CheckBox[] choices =
    [
        new() { Content = "平均气温", IsChecked = true },
        new() { Content = "气温较常年差值" },
        new() { Content = "降水较常年差值", IsChecked = true },
        new() { Content = "平均风速" },
        new() { Content = "平均云量" }
    ];

    public SeasonalOutlookWindow(SeasonalOutlook outlook, DateTime? departure = null)
    {
        this.outlook = outlook; this.departure = departure ?? DateTime.Today;
        Title = "远期天气趋势"; Width = 900; Height = 760; MinWidth = 720; MinHeight = 580;
        WindowStartupLocation = WindowStartupLocation.CenterOwner; Content = BuildLayout();
        SelectDeparturePeriod(); RefreshCharts();
    }

    private DockPanel BuildLayout()
    {
        var root = new DockPanel { Margin = new Thickness(20) };
        var header = new StackPanel();
        header.Children.Add(new TextBlock { Text = "远期天气趋势", FontSize = 24, FontWeight = FontWeights.SemiBold });
        var note = new TextBlock { Text = "周／月均值用于远期规划；气温差与降水差的正值表示较常年偏暖、偏湿。", Margin = new Thickness(0, 4, 0, 12) };
        UseMutedText(note);
        header.Children.Add(note);
        var toggles = new WrapPanel();
        foreach (var choice in choices) { choice.Margin = new Thickness(0, 0, 18, 8); choice.Checked += (_, _) => RefreshCharts(); choice.Unchecked += (_, _) => RefreshCharts(); toggles.Children.Add(choice); }
        header.Children.Add(toggles); DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);
        var footer = BuildDisclosure(); DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        periods.Items.Add(new TabItem { Header = "周趋势 · 约 6 周", Tag = outlook.Weeks });
        periods.Items.Add(new TabItem { Header = "月趋势 · 最多 7 个月", Tag = outlook.Months });
        periods.SelectionChanged += (_, _) => RefreshCharts(); root.Children.Add(periods);
        return root;
    }

    private StackPanel BuildDisclosure()
    {
        var footer = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
        var details = new Expander { Header = "查看具体数值" };
        details.Content = new TextBlock { Text = string.Join(Environment.NewLine, outlook.Weeks.Concat(outlook.Months).Select(FormatTrend)), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(8) };
        footer.Children.Add(details);
        var note = new TextBlock { Text = "ECMWF 集合平均与约 36 km 区域网格，未作偏差订正。远期趋势不能判断某天晴雨或山顶天气，临近出发请复查逐日预报。", FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) };
        UseMutedText(note);
        footer.Children.Add(note);
        return footer;
    }

    private void SelectDeparturePeriod()
    {
        var date = TimeZoneInfo.ConvertTime(new DateTimeOffset(departure), FindZone(outlook.Timezone)).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        periods.SelectedIndex = outlook.Months.Any(trend => trend.Start.CompareTo(date) <= 0 && trend.End.CompareTo(date) >= 0) ? 1 : 0;
    }

    private static TimeZoneInfo FindZone(string name)
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById(name); }
        catch { return TimeZoneInfo.TryConvertIanaIdToWindowsId(name, out var windowsId) && TimeZoneInfo.TryFindSystemTimeZoneById(windowsId, out var zone) ? zone : TimeZoneInfo.Utc; }
    }

    private void RefreshCharts()
    {
        if (periods.SelectedItem is not TabItem { Tag: IReadOnlyList<WeatherTrend> trends } tab) return;
        tab.Content = BuildTrendView(trends);
    }

    private ScrollViewer BuildTrendView(IReadOnlyList<WeatherTrend> trends)
    {
        var selected = Curves.Where(curve => choices.Any(choice => choice.Content?.ToString() == curve.Name && choice.IsChecked == true)).ToArray();
        var content = new StackPanel();
        if (selected.Length == 0) content.Children.Add(new TextBlock { Text = "勾选上方至少一种要素以显示曲线。", MinHeight = 220, VerticalAlignment = VerticalAlignment.Center });
        foreach (var group in selected.GroupBy(curve => curve.Unit)) content.Children.Add(BuildChartCard(group.ToArray(), trends));
        return new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    private Border BuildChartCard(IReadOnlyList<Curve> curves, IReadOnlyList<WeatherTrend> trends)
    {
        var panel = new DockPanel();
        var legend = new WrapPanel();
        foreach (var curve in curves) legend.Children.Add(BuildLegend(curve));
        DockPanel.SetDock(legend, Dock.Top); panel.Children.Add(legend);
        var chart = new Canvas { Height = 230, MinWidth = Math.Max(650, trends.Count * 105), Margin = new Thickness(0, 10, 0, 0) };
        chart.SizeChanged += (_, _) => DrawChart(chart, curves, trends); panel.Children.Add(chart);
        var card = new Border { BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10), Padding = new Thickness(14), Margin = new Thickness(0, 0, 0, 12), Child = panel };
        card.SetResourceReference(Border.BackgroundProperty, "SurfaceBrush");
        card.SetResourceReference(Border.BorderBrushProperty, "LineBrush");
        card.Loaded += (_, _) => DrawChart(chart, curves, trends);
        return card;
    }

    private static UIElement BuildLegend(Curve curve)
    {
        var line = new Rectangle { Width = 18, Height = 3, Fill = new SolidColorBrush(curve.Color), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 16, 0) };
        row.Children.Add(line); row.Children.Add(new TextBlock { Text = curve.Name, FontSize = 12 });
        return row;
    }

    private void DrawChart(Canvas canvas, IReadOnlyList<Curve> curves, IReadOnlyList<WeatherTrend> trends)
    {
        canvas.Children.Clear();
        var values = curves.SelectMany(curve => trends.Select(curve.Read)).Where(value => value.HasValue).Select(value => value!.Value).ToArray();
        if (values.Length == 0)
        {
            var empty = new TextBlock { Text = "当前时段暂无此要素的数据。" };
            UseMutedText(empty);
            canvas.Children.Add(empty);
            return;
        }
        var bounds = ChartBounds(values); var plot = new Rect(48, 12, Math.Max(100, canvas.ActualWidth - 62), Math.Max(100, canvas.ActualHeight - 44));
        DrawGrid(canvas, bounds, plot, trends); DrawDepartureMarker(canvas, trends, plot); DrawSeries(canvas, curves, trends, bounds, plot);
    }

    private static (double Min, double Max) ChartBounds(IReadOnlyList<double> values)
    {
        var min = values.Min(); var max = values.Max(); var padding = Math.Max((max - min) * 0.12, 0.5);
        return (min - padding, max + padding);
    }

    private static void DrawGrid(Canvas canvas, (double Min, double Max) bounds, Rect plot, IReadOnlyList<WeatherTrend> trends)
    {
        for (var row = 0; row <= 4; row++)
        {
            var y = plot.Top + row * plot.Height / 4;
            var gridline = new Line { X1 = plot.Left, X2 = plot.Right, Y1 = y, Y2 = y, StrokeThickness = 1 };
            gridline.SetResourceReference(Shape.StrokeProperty, "LineBrush");
            canvas.Children.Add(gridline);
            AddLabel(canvas, (bounds.Max - row * (bounds.Max - bounds.Min) / 4).ToString("0.#", CultureInfo.InvariantCulture), 0, y - 9);
        }
        for (var index = 0; index < trends.Count; index++)
            AddLabel(canvas, trends[index].Start[5..], plot.Left + (trends.Count == 1 ? 0.5 : (double)index / (trends.Count - 1)) * plot.Width - 16, plot.Bottom + 8);
    }

    private void DrawDepartureMarker(Canvas canvas, IReadOnlyList<WeatherTrend> trends, Rect plot)
    {
        var localDate = TimeZoneInfo.ConvertTime(new DateTimeOffset(departure), FindZone(outlook.Timezone)).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var index = trends.ToList().FindIndex(trend => trend.Start.CompareTo(localDate) <= 0 && trend.End.CompareTo(localDate) >= 0);
        if (index < 0) return;
        var x = plot.Left + (trends.Count == 1 ? 0.5 : (double)index / (trends.Count - 1)) * plot.Width;
        var marker = new Line { X1 = x, X2 = x, Y1 = plot.Top, Y2 = plot.Bottom, StrokeThickness = 1, StrokeDashArray = [3, 3] };
        marker.SetResourceReference(Shape.StrokeProperty, "TextBrush");
        canvas.Children.Add(marker);
    }

    private void DrawSeries(Canvas canvas, IReadOnlyList<Curve> curves, IReadOnlyList<WeatherTrend> trends, (double Min, double Max) bounds, Rect plot)
    {
        foreach (var curve in curves)
        {
            var samples = TrendsToPoints(curve, trends, bounds, plot);
            if (samples.Count > 1) canvas.Children.Add(new Polyline { Points = new PointCollection(samples.Select(sample => sample.Point)), Stroke = new SolidColorBrush(curve.Color), StrokeThickness = 2, StrokeDashArray = curve.Dashed ? [4, 3] : null });
            AddSeriesMarkers(canvas, curve, samples);
        }
    }

    private static List<TrendPoint> TrendsToPoints(Curve curve, IReadOnlyList<WeatherTrend> trends, (double Min, double Max) bounds, Rect plot)
    {
        var points = new List<TrendPoint>();
        for (var index = 0; index < trends.Count; index++)
        {
            if (curve.Read(trends[index]) is not { } value) continue;
            var x = plot.Left + (trends.Count == 1 ? 0.5 : (double)index / (trends.Count - 1)) * plot.Width;
            var y = plot.Bottom - (value - bounds.Min) / (bounds.Max - bounds.Min) * plot.Height;
            points.Add(new TrendPoint(new Point(x, y), trends[index], value));
        }
        return points;
    }

    private static void AddSeriesMarkers(Canvas canvas, Curve curve, IReadOnlyList<TrendPoint> samples)
    {
        foreach (var sample in samples)
        {
            var marker = new Ellipse { Width = 7, Height = 7, Fill = new SolidColorBrush(curve.Color), ToolTip = $"{curve.Name} · {sample.Trend.Start}: {sample.Value:0.##} {curve.Unit}" };
            canvas.Children.Add(marker); Canvas.SetLeft(marker, sample.Point.X - 3.5); Canvas.SetTop(marker, sample.Point.Y - 3.5);
        }
    }

    private static void AddLabel(Canvas canvas, string text, double left, double top)
    {
        var label = new TextBlock { Text = text, FontSize = 10 };
        UseMutedText(label);
        canvas.Children.Add(label); Canvas.SetLeft(label, left); Canvas.SetTop(label, top);
    }

    private static void UseMutedText(TextBlock text) =>
        text.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush");

    private static string FormatTrend(WeatherTrend trend) =>
        $"{trend.Start}–{trend.End} · 均温 {trend.Temperature:0.#}°C · 温差 {trend.TemperatureAnomaly:+0.#;-0.#;0}°C · 降水差 {trend.PrecipitationAnomaly:+0.#;-0.#;0} mm · 风速 {trend.Wind:0.#} km/h · 云量 {trend.CloudCover:0.#}%";

    private sealed record TrendPoint(Point Point, WeatherTrend Trend, double Value);
    private sealed record Curve(string Name, string Unit, Color Color, Func<WeatherTrend, double?> Read, bool Dashed = false);
}
