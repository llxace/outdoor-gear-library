using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using OutdoorGear.Core.Features.Dashboard.Business;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;

namespace OutdoorGear.Wpf.Features.Dashboard.Presentation;

public sealed class DashboardPage : UserControl
{
    private readonly LibrarySession session;
    private readonly Action<string> navigate;
    private readonly ComboBox statisticMode = new() { MinWidth = 160, Height = 32 };
    private readonly StackPanel chartRows = new();
    private readonly StackPanel chartFooter = new() { Orientation = Orientation.Horizontal };
    private readonly Button showAllButton = new() { Padding = new Thickness(8, 4, 8, 4) };
    private bool showAll;

    public DashboardPage(LibrarySession session, Action<string> navigate)
    {
        this.session = session;
        this.navigate = navigate;
        Content = BuildPage();
        statisticMode.ItemsSource = StatisticChoices();
        statisticMode.SelectedItem = StatisticChoices()[0];
        statisticMode.SelectionChanged += (_, _) => ModeChanged();
        showAllButton.Click += (_, _) => { showAll = !showAll; RefreshChart(); };
        RefreshChart();
        RefreshFavorites();
    }

    private UIElement BuildPage()
    {
        var root = new StackPanel { Margin = new Thickness(28) };
        root.Children.Add(BuildHeading());
        root.Children.Add(BuildSummaryCards());
        root.Children.Add(BuildOverviewPanels());
        return new ScrollViewer
        {
            Content = root,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
    }

    private static UIElement BuildHeading()
    {
        var heading = new StackPanel { Margin = new Thickness(0, 0, 0, 18) };
        heading.Children.Add(new TextBlock
        {
            Text = "装备概览",
            FontSize = 27,
            FontWeight = FontWeights.Bold
        });
        var subtitle = new TextBlock
        {
            Text = "本机个人资料库统计",
            Margin = new Thickness(0, 5, 0, 0)
        };
        UseMutedText(subtitle);
        heading.Children.Add(subtitle);
        return heading;
    }

    private UIElement BuildSummaryCards()
    {
        var cards = new UniformGrid { Columns = 2, Margin = new Thickness(0, 0, 0, 20) };
        cards.Children.Add(CreateSummaryCard(
            "在库装备", session.ActiveGearCount.ToString(), "🎒", "装备库"));
        cards.Children.Add(CreateSummaryCard(
            "购置支出", session.FormatMoney(session.TotalPurchaseValue), "￥", "装备库"));
        return cards;
    }

    private Button CreateSummaryCard(string title, string value, string symbol, string page)
    {
        var button = new Button
        {
            Content = SummaryCardContent(title, value, symbol),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Margin = new Thickness(0, 0, 14, 0),
            Padding = new Thickness(18),
            BorderThickness = new Thickness(1),
            ToolTip = "打开装备库"
        };
        button.SetResourceReference(Control.BackgroundProperty, "SurfaceAltBrush");
        button.SetResourceReference(Control.BorderBrushProperty, "LineBrush");
        button.Click += (_, _) => navigate(page);
        return button;
    }

    private static UIElement SummaryCardContent(string title, string value, string symbol)
    {
        var content = new DockPanel();
        var icon = new TextBlock { Text = symbol, FontSize = 20 };
        icon.SetResourceReference(TextBlock.ForegroundProperty, "AccentBrush");
        DockPanel.SetDock(icon, Dock.Right);
        content.Children.Add(icon);
        var text = new StackPanel();
        text.Children.Add(new TextBlock { Text = title });
        text.Children.Add(new TextBlock
        {
            Text = value,
            FontSize = 25,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 8, 0, 0)
        });
        content.Children.Add(text);
        return content;
    }

    private UIElement BuildOverviewPanels()
    {
        var panels = new Grid();
        panels.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3, GridUnitType.Star) });
        panels.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
        panels.Children.Add(BuildChartPanel());
        var favorites = BuildFavoritesPanel();
        Grid.SetColumn(favorites, 1);
        panels.Children.Add(favorites);
        return panels;
    }

    private Border BuildChartPanel()
    {
        var content = new StackPanel();
        content.Children.Add(BuildChartHeading());
        content.Children.Add(chartRows);
        content.Children.Add(chartFooter);
        return Panel("装备统计", content, new Thickness(0, 0, 14, 0));
    }

    private UIElement BuildChartHeading()
    {
        var heading = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
        DockPanel.SetDock(statisticMode, Dock.Right);
        heading.Children.Add(statisticMode);
        var label = new TextBlock
        {
            Text = "统计维度",
            VerticalAlignment = VerticalAlignment.Center
        };
        UseMutedText(label);
        heading.Children.Add(label);
        return heading;
    }

    private void RefreshChart()
    {
        chartRows.Children.Clear();
        var mode = SelectedMode();
        var groups = EquipmentStatistic.Calculate(session.Inventory.Gear(false), mode);
        AddChartBars(groups, mode);
        RefreshFooter(groups, mode);
    }

    private void ModeChanged()
    {
        showAll = false;
        RefreshChart();
    }

    private EquipmentStatisticMode SelectedMode() =>
        statisticMode.SelectedItem is StatisticChoice choice
            ? choice.Mode
            : EquipmentStatisticMode.CategoryQuantity;

    private void AddChartBars(
        IReadOnlyList<EquipmentDistribution> groups,
        EquipmentStatisticMode mode)
    {
        var visible = showAll ? groups : groups.Take(8).ToList();
        var maximum = Math.Max(1, groups.Select(group => group.Value).DefaultIfEmpty().Max());
        foreach (var group in visible)
            chartRows.Children.Add(CreateBarRow(group, maximum, mode));
        if (groups.Count == 0)
            chartRows.Children.Add(EmptyChartMessage());
    }

    private UIElement CreateBarRow(
        EquipmentDistribution group,
        double maximum,
        EquipmentStatisticMode mode)
    {
        var row = new Grid { Margin = new Thickness(0, 5, 0, 5) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(100) });
        row.Children.Add(GroupName(group.Name));
        row.Children.Add(BarTrack(group.Value, maximum));
        row.Children.Add(GroupValue(group.Value, mode));
        Grid.SetColumn(row.Children[1], 1);
        Grid.SetColumn(row.Children[2], 2);
        return row;
    }

    private static UIElement GroupName(string name) => new TextBlock
    {
        Text = name,
        TextTrimming = TextTrimming.CharacterEllipsis,
        VerticalAlignment = VerticalAlignment.Center,
        ToolTip = name
    };

    private static UIElement BarTrack(double value, double maximum)
    {
        var track = new Grid { Height = 18, Margin = new Thickness(8, 0, 8, 0) };
        var background = new Border
        {
            CornerRadius = new CornerRadius(4)
        };
        background.SetResourceReference(Border.BackgroundProperty, "DashboardTrackBrush");
        track.Children.Add(background);
        var bar = new Border
        {
            CornerRadius = new CornerRadius(4),
            HorizontalAlignment = HorizontalAlignment.Left
        };
        bar.SetResourceReference(Border.BackgroundProperty, "AccentBrush");
        track.Children.Add(bar);
        var ratio = Math.Clamp(value / maximum, 0, 1);
        void ResizeBar(double width) => bar.Width = Math.Max(4, width * ratio);
        track.SizeChanged += (_, eventArgs) => ResizeBar(eventArgs.NewSize.Width);
        track.Loaded += (_, _) => ResizeBar(track.ActualWidth);
        return track;
    }

    private UIElement GroupValue(double value, EquipmentStatisticMode mode)
    {
        var valueText = new TextBlock
        {
            Text = FormatStatistic(value, mode),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center
        };
        UseMutedText(valueText);
        return valueText;
    }

    private UIElement BuildFavoritesPanel()
    {
        var content = new StackPanel();
        content.Children.Add(new TextBlock
        {
            Text = "收藏装备速览",
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 12)
        });
        content.Children.Add(favoriteRows);
        var viewAll = new Button { Content = "查看装备库  →", HorizontalAlignment = HorizontalAlignment.Left };
        viewAll.Click += (_, _) => navigate("装备库");
        content.Children.Add(viewAll);
        return Panel("收藏", content, new Thickness(0));
    }

    private readonly StackPanel favoriteRows = new();

    private void RefreshFavorites()
    {
        favoriteRows.Children.Clear();
        var favorites = session.Inventory.Gear(false)
            .Where(item => !item.IsLocation && session.Inventory.IsFavorite(item.Id))
            .OrderBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
        foreach (var gear in favorites)
            favoriteRows.Children.Add(FavoriteRow(gear));
        if (favorites.Count == 0)
        {
            var empty = new TextBlock
            {
                Text = "暂无收藏。可在装备库打开装备详情并添加星标。",
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 12, 0, 20)
            };
            UseMutedText(empty);
            favoriteRows.Children.Add(empty);
        }
    }

    private UIElement FavoriteRow(GearRecord gear)
    {
        var row = new Button
        {
            Content = FavoriteRowContent(gear),
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(4),
            Margin = new Thickness(0, 0, 0, 4)
        };
        row.Click += (_, _) => navigate("装备库");
        return row;
    }

    private UIElement FavoriteRowContent(GearRecord gear)
    {
        var row = new DockPanel();
        var image = GearThumbnail(gear);
        DockPanel.SetDock(image, Dock.Left);
        row.Children.Add(image);
        var details = new StackPanel { Margin = new Thickness(12, 3, 0, 3) };
        details.Children.Add(new TextBlock { Text = gear.Name, TextWrapping = TextWrapping.Wrap });
        var subtitle = new TextBlock
        {
            Text = $"{gear.Category} · {gear.Status}",
            FontSize = 12,
            Margin = new Thickness(0, 4, 0, 0)
        };
        UseMutedText(subtitle);
        details.Children.Add(subtitle);
        row.Children.Add(details);
        return row;
    }

    private UIElement GearThumbnail(GearRecord gear)
    {
        var frame = new Border
        {
            Width = 52,
            Height = 52,
            Background = Brushes.White,
            CornerRadius = new CornerRadius(5)
        };
        if (string.IsNullOrWhiteSpace(gear.Photo))
            return frame;
        try
        {
            var path = GearAssetService.AssetPath(
                session.CurrentDataDirectory, "Photos", gear.Photo);
            frame.Child = LoadThumbnail(path);
        }
        catch { }
        return frame;
    }

    private static Image LoadThumbnail(string path)
    {
        using var stream = File.OpenRead(path);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.DecodePixelWidth = 104;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        return new Image { Source = image, Stretch = Stretch.Uniform };
    }

    private static Border Panel(string heading, UIElement content, Thickness margin)
    {
        var body = new StackPanel();
        body.Children.Add(new TextBlock
        {
            Text = heading,
            FontSize = 18,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 12)
        });
        body.Children.Add(content);
        var panel = new Border
        {
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(18),
            Margin = margin,
            Child = body
        };
        panel.SetResourceReference(Border.BackgroundProperty, "SurfaceBrush");
        panel.SetResourceReference(Border.BorderBrushProperty, "LineBrush");
        return panel;
    }

    private void RefreshFooter(
        IReadOnlyList<EquipmentDistribution> groups,
        EquipmentStatisticMode mode)
    {
        chartFooter.Children.Clear();
        var shown = showAll ? groups.Count : Math.Min(groups.Count, 8);
        var note = mode == EquipmentStatisticMode.CategoryWeight
            ? $" · {session.Inventory.Gear(false).Count(item => !item.IsLocation && item.Weight == 0)} 项未填重量"
            : "";
        var footer = new TextBlock
        {
            Text = $"显示 {shown} 组 · 共 {groups.Count} 组{note}",
            VerticalAlignment = VerticalAlignment.Center
        };
        UseMutedText(footer);
        chartFooter.Children.Add(footer);
        AddShowAllButton(groups);
        chartFooter.Children.Add(CreateLibraryButton());
    }

    private void AddShowAllButton(IReadOnlyList<EquipmentDistribution> groups)
    {
        if (groups.Count <= 8)
            return;
        showAllButton.Content = showAll ? "收起" : "显示全部";
        showAllButton.Margin = new Thickness(8, 0, 0, 0);
        chartFooter.Children.Add(showAllButton);
    }

    private Button CreateLibraryButton()
    {
        var button = new Button { Content = "装备库  →", Padding = new Thickness(8, 4, 8, 4) };
        button.Margin = new Thickness(8, 0, 0, 0);
        button.Click += (_, _) => navigate("装备库");
        return button;
    }

    private static IReadOnlyList<StatisticChoice> StatisticChoices() =>
    [
        new("分类数量", EquipmentStatisticMode.CategoryQuantity),
        new("品牌数量", EquipmentStatisticMode.BrandQuantity),
        new("分类重量", EquipmentStatisticMode.CategoryWeight),
        new("分类支出", EquipmentStatisticMode.CategoryCost),
        new("品牌支出", EquipmentStatisticMode.BrandCost)
    ];

    private sealed record StatisticChoice(string Name, EquipmentStatisticMode Mode)
    {
        public override string ToString() => Name;
    }

    private static TextBlock EmptyChartMessage()
    {
        var message = new TextBlock
        {
            Text = "添加或导入装备后，这里会显示统计图表。",
            Margin = new Thickness(0, 22, 0, 22)
        };
        UseMutedText(message);
        return message;
    }

    private string FormatStatistic(double value, EquipmentStatisticMode mode)
    {
        if (EquipmentStatistic.IsCost(mode))
            return session.FormatMoney(value);
        if (EquipmentStatistic.IsWeight(mode))
            return $"{value:0.###} kg";
        return $"{value:0.###} 件";
    }

    private static void UseMutedText(TextBlock text) =>
        text.SetResourceReference(TextBlock.ForegroundProperty, "MutedBrush");
}
