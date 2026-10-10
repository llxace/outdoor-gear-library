using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.Features.Shared.Presentation;
using OutdoorGear.Wpf.ViewModels;

namespace OutdoorGear.Wpf.Features.Packing.Presentation;

public sealed class BorrowGearWindow : Window
{
    private readonly LibrarySession session;
    private readonly ComboBox ownerPicker = new() { MinWidth = 180 };
    private readonly ComboBox categoryPicker = new() { MinWidth = 190 };
    private readonly TextBox search = new() { MinWidth = 220, Height = 32 };
    private readonly StackPanel results = new();
    private readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) };
    private IReadOnlyList<BorrowableGearRecord> available = [];

    public BorrowGearWindow(LibrarySession session)
    {
        this.session = session;
        Title = "添加别人的装备";
        Width = 900;
        Height = 650;
        MinWidth = 700;
        MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildLayout();
        LoadOwners();
    }

    private UIElement BuildLayout()
    {
        var root = new DockPanel { Margin = new Thickness(20) };
        var header = new StackPanel();
        header.Children.Add(new TextBlock { Text = "添加别人的装备", FontSize = 22, FontWeight = FontWeights.SemiBold });
        header.Children.Add(new TextBlock
        {
            Text = "从其他用户的装备库浏览并加入本次打包。来源资料只读；选中后会在当前资料库保存装备快照和照片副本。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = Brushes.Gray,
            Margin = new Thickness(0, 4, 0, 12)
        });
        header.Children.Add(BuildFilters());
        header.Children.Add(status);
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);
        root.Children.Add(new ScrollViewer
        {
            Content = results,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Margin = new Thickness(0, 12, 0, 0)
        });
        return root;
    }

    private UIElement BuildFilters()
    {
        var filters = new WrapPanel { VerticalAlignment = VerticalAlignment.Center };
        filters.Children.Add(new TextBlock { Text = "来源用户", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) });
        filters.Children.Add(ownerPicker);
        filters.Children.Add(new TextBlock { Text = "分类", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(14, 0, 6, 0) });
        filters.Children.Add(categoryPicker);
        search.ToolTip = "搜索装备名称、品牌或型号";
        search.Margin = new Thickness(14, 0, 0, 0);
        filters.Children.Add(search);
        ownerPicker.DisplayMemberPath = nameof(LibraryUserRecord.Name);
        ownerPicker.SelectionChanged += (_, _) => LoadSelectedOwner();
        categoryPicker.SelectionChanged += (_, _) => RefreshResults();
        search.TextChanged += (_, _) => RefreshResults();
        return filters;
    }

    private void LoadOwners()
    {
        var owners = session.Users.Where(user => !InventoryDocument.IdEquals(user.Id, session.SelectedUserId)).ToList();
        ownerPicker.ItemsSource = owners;
        ownerPicker.SelectedItem = owners.FirstOrDefault();
        if (owners.Count == 0) status.Text = "当前没有其他用户资料库。可先在设置中创建或切换用户。";
    }

    private void LoadSelectedOwner()
    {
        if (ownerPicker.SelectedItem is not LibraryUserRecord owner) return;
        try
        {
            available = session.ReadBorrowableGear(owner.Id);
            var categories = new[] { "全部分类" }.Concat(available.Select(CategoryPath).Distinct().Order()).ToList();
            categoryPicker.ItemsSource = categories;
            categoryPicker.SelectedIndex = 0;
            search.Clear();
            status.Text = $"来源：{owner.Name} · {available.Count} 件装备。损坏、位置和回收站项目不可借用。";
            RefreshResults();
        }
        catch (Exception error)
        {
            available = [];
            results.Children.Clear();
            status.Text = "无法读取来源装备库：" + error.Message;
        }
    }

    private void RefreshResults()
    {
        if (results is null) return;
        results.Children.Clear();
        var category = categoryPicker.SelectedItem?.ToString() ?? "全部分类";
        var query = search.Text.Trim();
        var rows = available.Where(item =>
                MatchesCategory(item, category) &&
                (query.Length == 0 || string.Join(" ", item.Gear.Name, item.Gear.Brand, item.Gear.Model).Contains(query, StringComparison.CurrentCultureIgnoreCase)))
            .OrderBy(item => item.Gear.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
        foreach (var row in rows) results.Children.Add(BuildGearRow(row));
        if (rows.Count == 0)
            results.Children.Add(new TextBlock { Text = "没有符合条件的装备。", Margin = new Thickness(8, 20, 8, 8), Foreground = Brushes.Gray });
    }

    private UIElement BuildGearRow(BorrowableGearRecord row)
    {
        var gear = row.Gear;
        var damaged = gear.Status == "损坏";
        var alreadyAdded = session.Inventory.BorrowedNodes.OfType<System.Text.Json.Nodes.JsonObject>().Any(item =>
            InventoryDocument.IdEquals(item["ownerID"]?.ToString(), row.Owner.Id) &&
            InventoryDocument.IdEquals(item["gear"]?["id"]?.ToString(), gear.Id));
        var panel = new DockPanel();
        var button = PageUi.Button(alreadyAdded ? "已加入" : "加入清单", (_, _) => Add(row));
        button.IsEnabled = !damaged && !alreadyAdded;
        DockPanel.SetDock(button, Dock.Right);
        panel.Children.Add(button);
        panel.Children.Add(BuildGearDescription(row, damaged));
        return new Border
        {
            BorderBrush = Brushes.Gray,
            BorderThickness = new Thickness(0, 0, 0, 1),
            Padding = new Thickness(8),
            Opacity = damaged ? 0.5 : 1,
            Child = panel
        };
    }

    private static string CategoryPath(BorrowableGearRecord item) =>
        string.IsNullOrWhiteSpace(item.Subcategory) ? item.Gear.Category : $"{item.Gear.Category}/{item.Subcategory}";

    private static bool MatchesCategory(BorrowableGearRecord item, string category)
    {
        if (category == "全部分类") return true;
        var parts = category.Split('/');
        return item.Gear.Category == parts[0] &&
            (parts.Length == 1 || item.Subcategory == parts[1]);
    }

    private UIElement BuildGearDescription(BorrowableGearRecord row, bool damaged)
    {
        var layout = new StackPanel { Orientation = Orientation.Horizontal };
        layout.Children.Add(BuildPhoto(row));
        var details = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 8, 0) };
        details.Children.Add(new TextBlock { Text = row.Gear.Name, FontWeight = FontWeights.SemiBold });
        var brand = string.Join(" ", new[] { row.Gear.Brand, row.Gear.Model }.Where(value => !string.IsNullOrWhiteSpace(value)));
        var state = damaged ? " · 已损坏，不能借用" : "";
        details.Children.Add(new TextBlock
        {
            Text = $"{row.Gear.Category}{(string.IsNullOrWhiteSpace(row.Subcategory) ? "" : " / " + row.Subcategory)} · {brand} · {row.Gear.Weight:0.##} g / 件 · 库存 {row.Gear.Quantity:0.##} 件{state}",
            Foreground = Brushes.Gray,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        layout.Children.Add(details);
        return layout;
    }

    private static Border BuildPhoto(BorrowableGearRecord row)
    {
        var image = new Image { Width = 52, Height = 52, Stretch = Stretch.UniformToFill };
        if (!string.IsNullOrWhiteSpace(row.Gear.Photo))
        {
            try
            {
                var path = GearAssetService.AssetPath(row.SourceDirectory, "Photos", row.Gear.Photo);
                using var stream = File.OpenRead(path);
                var bitmap = new BitmapImage();
                bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.StreamSource = stream; bitmap.EndInit();
                image.Source = bitmap;
            }
            catch { }
        }
        return new Border
        {
            Width = 56,
            Height = 56,
            Background = Brushes.White,
            CornerRadius = new CornerRadius(6),
            Child = image
        };
    }

    private void Add(BorrowableGearRecord row)
    {
        try
        {
            session.AddBorrowedGear(row.Owner.Id, row.Gear.Id ?? "");
            status.Text = $"已将“{row.Gear.Name}”加入 {row.Owner.Name} 的打包快照。";
            RefreshResults();
        }
        catch (Exception error) { PageUi.Error(error); }
    }
}
