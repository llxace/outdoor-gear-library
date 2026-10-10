using System.Globalization;
using System.IO;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using Microsoft.Win32;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;

using OutdoorGear.Wpf.Features.Photos.Presentation;
using OutdoorGear.Wpf.Features.Shared.Presentation;

namespace OutdoorGear.Wpf.Features.Equipment.Presentation;

public sealed class GearLibraryPage : UserControl
{
    private readonly LibrarySession session;
    private readonly ListBox categoryList = new() { SelectedValuePath = "Path" };
    private readonly TextBox search = new() { Height = 36, MinWidth = 280, VerticalContentAlignment = VerticalAlignment.Center, ToolTip = "搜索名称、编号、品牌、型号、备注、分类、位置、标签和描述" };
    private readonly ComboBox statusFilter = new() { Width = 112, Margin = new Thickness(8, 0, 0, 0), ItemsSource = new[] { "全部状态", "可用", "想买", "借出", "损坏", "已出售" } };
    private readonly ComboBox sortBy = new() { Width = 105, Margin = new Thickness(8, 0, 0, 0), ItemsSource = new[] { "名称", "资产编号", "价格", "重量", "购买时间" } };
    private readonly CheckBox sortAscending = new() { Content = "升序", IsChecked = true, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) };
    private readonly TextBlock resultCount = new() { Foreground = System.Windows.Media.Brushes.Gray, VerticalAlignment = VerticalAlignment.Center };
    private readonly DataGrid grid = new() { AutoGenerateColumns = false, CanUserAddRows = false, IsReadOnly = true, Height = 560, SelectionMode = DataGridSelectionMode.Extended, SelectionUnit = DataGridSelectionUnit.FullRow };
    private readonly StackPanel details = new() { Margin = new Thickness(0, 10, 0, 0) };
    private bool loadingCategories;
    public GearLibraryPage(LibrarySession session)
    {
        this.session = session;
        var root = PageUi.Root("装备库", "管理装备资料、照片关联、状态和分类");
        root.Children.Add(BuildActions());
        ConfigureGrid();
        search.Text = session.SearchText;
        root.Children.Add(BuildWorkspace());
        ConfigureEvents();
        Content = root;
        Refresh();
    }
    private UIElement BuildActions()
    {
        var actions = new WrapPanel();
        actions.Children.Add(PageUi.Button("＋ 新增装备", (_, _) => AddGear()));
        actions.Children.Add(PageUi.Button("新增子装备", (_, _) => AddChildGear()));
        actions.Children.Add(PageUi.Button("标签 / 模板", (_, _) => ManageMetadata()));
        actions.Children.Add(PageUi.Button("批量操作", (_, _) => BatchSelected()));
        actions.Children.Add(PageUi.Button("编辑所选", (_, _) => EditGear()));
        actions.Children.Add(PageUi.Button("照片 / 附件", (_, _) => ViewPhotos()));
        actions.Children.Add(PageUi.Button("复制", (_, _) => Duplicate()));
        actions.Children.Add(PageUi.Button("收藏 / 取消收藏", (_, _) => Favorite()));
        actions.Children.Add(PageUi.Button("移入回收站", (_, _) => Trash()));
        actions.Children.Add(PageUi.Button("导入 Excel", (_, _) => ImportExcel()));
        actions.Children.Add(PageUi.Button("导入 CSV/TSV", (_, _) => Import()));
        actions.Children.Add(PageUi.Button("导出 CSV", (_, _) => Export()));
        actions.Children.Add(PageUi.Button("导入 GPX/KML", (_, _) => ImportTrail()));
        return actions;
    }
    private void ConfigureGrid()
    {
        AddPhotoColumn();
        AddGridColumn("装备名称", "Name", 2);
        AddGridColumn("分类", "Category", 1.3);
        AddGridColumn("品牌", "Brand", 1);
        AddGridColumn("型号", "Model", 1);
        AddGridColumn("状态", "Status", 0.8);
        grid.Columns.Add(new DataGridTextColumn { Header = "重量 g", Binding = new Binding("Weight"), Width = 90 });
        grid.Columns.Add(new DataGridTextColumn { Header = "数量", Binding = new Binding("Quantity"), Width = 70 });
        grid.Columns.Add(new DataGridTextColumn { Header = "价格", Binding = new Binding(nameof(GearRowViewModel.PurchasePriceLabel)), Width = 120 });
    }

    private void AddPhotoColumn()
    {
        var image = new FrameworkElementFactory(typeof(Image));
        image.SetBinding(Image.SourceProperty, new Binding(nameof(GearRowViewModel.PhotoPath)) { Converter = new GearPhotoPathConverter() });
        image.SetValue(FrameworkElement.WidthProperty, 46d);
        image.SetValue(FrameworkElement.HeightProperty, 46d);
        image.SetValue(Image.StretchProperty, System.Windows.Media.Stretch.UniformToFill);
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(FrameworkElement.WidthProperty, 50d);
        border.SetValue(FrameworkElement.HeightProperty, 50d);
        border.SetValue(Border.BackgroundProperty, System.Windows.Media.Brushes.White);
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(6));
        border.AppendChild(image);
        grid.Columns.Add(new DataGridTemplateColumn { Header = "照片", CellTemplate = new DataTemplate { VisualTree = border }, Width = 62 });
    }
    private void AddGridColumn(string header, string binding, double starWidth)
    {
        grid.Columns.Add(new DataGridTextColumn
        {
            Header = header,
            Binding = new Binding(binding),
            Width = new DataGridLength(starWidth, DataGridLengthUnitType.Star)
        });
    }
    private void ConfigureEvents()
    {
        grid.SelectionChanged += (_, _) => ShowDetails();
        grid.MouseDoubleClick += (_, _) => EditGear();
        categoryList.SelectionChanged += Category_Selected;
        search.TextChanged += (_, _) =>
        {
            session.SetSearch(search.Text);
            UpdateCount();
        };
        statusFilter.SelectionChanged += (_, _) => { if (statusFilter.SelectedItem is string value) session.StatusFilter = value; UpdateCount(); };
        sortBy.SelectionChanged += (_, _) => { if (sortBy.SelectedItem is string value) session.SortBy = value; UpdateCount(); };
        sortAscending.Checked += (_, _) => session.SortAscending = true;
        sortAscending.Unchecked += (_, _) => session.SortAscending = false;
    }
    private GearRowViewModel? Selected => grid.SelectedItem as GearRowViewModel;
    private UIElement BuildWorkspace()
    {
        var workspace = CreateWorkspaceGrid();
        workspace.Children.Add(BuildCategorySidebar());
        workspace.Children.Add(BuildGearContent());
        return workspace;
    }
    private static Grid CreateWorkspaceGrid()
    {
        var workspace = new Grid { Height = 760 };
        workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        workspace.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        return workspace;
    }
    private UIElement BuildCategorySidebar()
    {
        var title = new TextBlock
        {
            Text = "装备分类",
            FontSize = 16,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(14)
        };
        var sidebar = new DockPanel();
        DockPanel.SetDock(title, Dock.Top);
        sidebar.Children.Add(title);
        categoryList.ItemTemplate = CategoryTemplate();
        sidebar.Children.Add(categoryList);
        var border = new Border
        {
            BorderBrush = System.Windows.Media.Brushes.Gray,
            BorderThickness = new Thickness(1),
            Margin = new Thickness(0, 0, 12, 0),
            Child = sidebar
        };
        Grid.SetColumn(border, 0);
        return border;
    }
    private UIElement BuildGearContent()
    {
        var content = new DockPanel();
        var toolbar = BuildSearchToolbar();
        DockPanel.SetDock(toolbar, Dock.Top);
        content.Children.Add(toolbar);
        content.Children.Add(grid);
        DockPanel.SetDock(details, Dock.Bottom);
        content.Children.Add(details);
        Grid.SetColumn(content, 1);
        return content;
    }
    private UIElement BuildSearchToolbar()
    {
        var toolbar = new Grid { Margin = new Thickness(0, 0, 0, 8) };
        toolbar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        toolbar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        toolbar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        resultCount.Text = "0 项装备";
        Grid.SetColumn(search, 0);
        Grid.SetColumn(resultCount, 2);
        toolbar.Children.Add(search);
        toolbar.Children.Add(resultCount);
        var filters = new StackPanel { Orientation = Orientation.Horizontal };
        statusFilter.SelectedItem = session.StatusFilter;
        sortBy.SelectedItem = session.SortBy;
        filters.Children.Add(statusFilter);
        filters.Children.Add(sortBy);
        filters.Children.Add(sortAscending);
        Grid.SetColumn(filters, 1);
        toolbar.Children.Add(filters);
        return toolbar;
    }
    private static DataTemplate CategoryTemplate()
    {
        var row = new FrameworkElementFactory(typeof(StackPanel));
        row.SetValue(StackPanel.OrientationProperty, Orientation.Horizontal);
        row.SetValue(FrameworkElement.MarginProperty, new Thickness(2, 5, 2, 5));
        row.AppendChild(CreateCategoryIcon());
        row.AppendChild(CreateCategoryName());
        row.AppendChild(CreateCategoryCount());
        return new DataTemplate(typeof(CategoryFolderViewModel)) { VisualTree = row };
    }
    private static FrameworkElementFactory CreateCategoryIcon()
    {
        var icon = new FrameworkElementFactory(typeof(System.Windows.Shapes.Path));
        icon.SetBinding(System.Windows.Shapes.Path.DataProperty, new Binding(nameof(CategoryFolderViewModel.Glyph))
        {
            Converter = GearCategoryIconConverter.Instance
        });
        icon.SetBinding(AutomationProperties.NameProperty, new Binding(nameof(CategoryFolderViewModel.Name)));
        icon.SetValue(FrameworkElement.WidthProperty, 26d);
        icon.SetValue(FrameworkElement.HeightProperty, 26d);
        icon.SetValue(FrameworkElement.MarginProperty, new Thickness(2, 0, 8, 0));
        icon.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        icon.SetValue(System.Windows.Shapes.Shape.StretchProperty, System.Windows.Media.Stretch.Uniform);
        icon.SetValue(System.Windows.Shapes.Shape.StrokeProperty, System.Windows.Media.Brushes.SeaGreen);
        icon.SetValue(System.Windows.Shapes.Shape.StrokeThicknessProperty, 2d);
        icon.SetValue(System.Windows.Shapes.Shape.StrokeStartLineCapProperty, System.Windows.Media.PenLineCap.Round);
        icon.SetValue(System.Windows.Shapes.Shape.StrokeEndLineCapProperty, System.Windows.Media.PenLineCap.Round);
        icon.SetValue(System.Windows.Shapes.Shape.StrokeLineJoinProperty, System.Windows.Media.PenLineJoin.Round);
        return icon;
    }
    private static FrameworkElementFactory CreateCategoryText(
        string binding,
        double width,
        System.Windows.Media.Brush? foreground = null)
    {
        var text = new FrameworkElementFactory(typeof(TextBlock));
        text.SetBinding(TextBlock.TextProperty, new Binding(binding));
        text.SetValue(FrameworkElement.WidthProperty, width);
        text.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        if (foreground is not null)
            text.SetValue(TextBlock.ForegroundProperty, foreground);
        return text;
    }
    private static FrameworkElementFactory CreateCategoryName()
    {
        var name = CreateCategoryText(nameof(CategoryFolderViewModel.Name), 170);
        name.SetValue(TextBlock.TextTrimmingProperty, TextTrimming.CharacterEllipsis);
        return name;
    }
    private static FrameworkElementFactory CreateCategoryCount()
    {
        var count = CreateCategoryText(nameof(CategoryFolderViewModel.Count), 32);
        count.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Right);
        return count;
    }
    private void Category_Selected(object sender, SelectionChangedEventArgs e)
    {
        if (loadingCategories || categoryList.SelectedValue is not string path)
            return;

        session.SetCategory(path);
        Refresh();
    }
    private void Refresh()
    {
        session.RefreshCategories();
        session.RefreshRows();
        grid.ItemsSource = session.Rows;
        UpdateCategoryList();
        UpdateCount();
    }
    private void UpdateCategoryList()
    {
        loadingCategories = true;
        categoryList.ItemsSource = session.Categories;
        categoryList.SelectedValue = session.SelectedCategory;
        loadingCategories = false;
    }
    private void UpdateCount() => resultCount.Text = $"{session.Rows.Count} 项装备";
    private void AddGear(string? parentId = null)
    {
        while (true)
        {
            var dialog = new GearEditorWindow(null, session, parentId) { Owner = Window.GetWindow(this) };
            if (dialog.ShowDialog() != true)
                return;

            try
            {
                SaveNewGear(dialog);
            }
            catch (Exception error)
            {
                PageUi.Error(error);
                return;
            }

            Refresh();
            if (!dialog.ContinueAdding) return;
            parentId = InventoryDocument.IdEquals(dialog.DestinationUserId, session.SelectedUserId)
                ? dialog.ParentIdValue
                : null;
        }
    }
    private void SaveNewGear(GearEditorWindow dialog)
    {
        var destinationId = dialog.DestinationUserId;
        if (InventoryDocument.IdEquals(destinationId, session.SelectedUserId))
        {
            var gear = GearService.Create(session.Inventory, dialog.NameValue, dialog.CategoryValue, dialog.ParentIdValue);
            ApplyEditor(gear, dialog);
            session.SaveGear(gear);
            return;
        }

        var inventory = session.ReadUserInventory(destinationId);
        var newGear = GearService.Create(inventory, dialog.NameValue, dialog.CategoryValue, dialog.ParentIdValue);
        ApplyEditor(newGear, dialog);
        session.SaveGearForUser(destinationId, inventory, newGear);
    }
    private void AddChildGear()
    {
        if (Selected is { } row)
            AddGear(row.Id);
    }
    private void ManageMetadata()
    {
        var window = new GearMetadataWindow(session, Selected?.Gear) { Owner = Window.GetWindow(this) };
        if (window.ShowDialog() != true || window.AppliedTemplateId is not { } templateId)
            return;

        try
        {
            var created = GearMetadataService.CreateFromTemplate(session.Inventory, templateId);
            GearService.Save(session.Inventory, created);
            session.Save();
            Refresh();
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void BatchSelected()
    {
        var ids = grid.SelectedItems.Cast<GearRowViewModel>().Select(row => row.Id).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (ids.Length < 2)
        {
            PageUi.Error(new InvalidOperationException("请使用 Command/Ctrl 多选至少两件装备后再进行批量操作。"));
            return;
        }
        var dialog = new BatchGearWindow(ids.Length) { Owner = Window.GetWindow(this) };
        if (dialog.ShowDialog() != true) return;
        try
        {
            GearService.ChangeRecords(session.Inventory, ids, dialog.StatusValue, dialog.TrashedValue);
            session.Save(); Refresh();
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void ApplyEditor(GearRecord gear, GearEditorWindow dialog)
    {
        gear.Brand = dialog.BrandValue;
        gear.Model = dialog.ModelValue;
        gear.Status = dialog.StatusValue;
        gear.Weight = dialog.WeightValue;
        gear.Quantity = dialog.QuantityValue;
        gear.PurchasePrice = dialog.PriceValue;
        gear.PurchaseFrom = dialog.PurchaseFromValue;
        gear.PurchaseDate = dialog.PurchaseDateValue;
        gear.Location = dialog.LocationValue;
        gear.Tags = dialog.TagsValue;
        gear.Notes = dialog.NotesValue;
        gear.Photo = dialog.PhotoFile;
        gear.Extras.Description = dialog.DescriptionValue;
        gear.Extras.Subcategory = dialog.SubcategoryValue;
        gear.Extras.AssetId = dialog.AssetIdValue;
        gear.Extras.ParentId = dialog.ParentIdValue;
        gear.Extras.LocationOverrideId = dialog.LocationOverrideIdValue;
        gear.Extras.Node["attachments"] = dialog.Attachments.DeepClone();
    }
    private void EditGear()
    {
        if (Selected is not { } row)
            return;

        var dialog = new GearEditorWindow(row.Gear, session) { Owner = Window.GetWindow(this) };
        if (dialog.ShowDialog() != true)
            return;

        try
        {
            row.Name = dialog.NameValue;
            row.Category = dialog.CategoryValue;
            ApplyEditor(row.Gear, dialog);
            GearService.Save(session.Inventory, row.Gear);
            session.Save();
            Refresh();
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void ViewPhotos()
    {
        if (Selected is not { } row)
            return;

        new GearPhotosWindow(session, row.Gear) { Owner = Window.GetWindow(this) }.ShowDialog();
        ShowDetails();
    }
    private void ShowDetails()
    {
        if (Selected is not { } row)
        {
            details.Children.Clear();
            details.Children.Add(new TextBlock { Text = "选择装备查看完整资料。" });
            return;
        }

        details.Children.Clear();
        details.Children.Add(new TextBlock { Text = FormatDetails(row.Gear, row.Id), TextWrapping = TextWrapping.Wrap });
        AddRelatedGearNavigation(row.Gear, row.Id);
        AddMarkdownSection("描述", row.Gear.Extras.Description);
        AddMarkdownSection("笔记", row.Gear.Notes);
    }

    private void AddRelatedGearNavigation(GearRecord gear, string gearId)
    {
        if (gear.Extras.ParentId is { } parentId && session.Inventory.FindGear(parentId) is { Trashed: false, IsLocation: false } parent)
            details.Children.Add(PageUi.Button($"父级装备：{parent.Name}", (_, _) => NavigateToGear(parent.Id!)));
        var children = GearService.Children(session.Inventory, gearId)
            .Where(child => !child.Trashed && !child.IsLocation).ToArray();
        if (children.Length == 0) return;
        details.Children.Add(new TextBlock { Text = "包含的装备", FontSize = 15, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 2) });
        foreach (var child in children)
            details.Children.Add(PageUi.Button(child.Name, (_, _) => NavigateToGear(child.Id!)));
    }

    private void NavigateToGear(string id)
    {
        var row = session.Rows.FirstOrDefault(item => InventoryDocument.IdEquals(item.Id, id));
        if (row is null)
        {
            session.SetCategory("全部分类");
            categoryList.SelectedValue = "全部分类";
            search.Text = "";
            session.StatusFilter = "全部状态";
            statusFilter.SelectedItem = "全部状态";
            Refresh();
            row = session.Rows.FirstOrDefault(item => InventoryDocument.IdEquals(item.Id, id));
        }
        if (row is null) return;
        grid.SelectedItem = row;
        grid.ScrollIntoView(row);
    }

    private void AddMarkdownSection(string title, string markdown)
    {
        if (string.IsNullOrWhiteSpace(markdown)) return;
        details.Children.Add(new TextBlock { Text = title, FontSize = 15, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 2) });
        details.Children.Add(MarkdownTextViewBuilder.Build(markdown));
    }
    private string FormatDetails(GearRecord gear, string id)
    {
        var locationName = GetLocationName(gear);
        var children = GearService.Children(session.Inventory, id).Where(child => !child.IsLocation).Select(child => child.Name).ToArray();
        var subcategory = string.IsNullOrWhiteSpace(gear.Extras.Subcategory)
            ? ""
            : " / " + GearService.Subcategory(gear);
        var childNames = children.Length == 0 ? "无" : string.Join("、", children);
        return $"{gear.Name} · 资产 #{gear.Extras.AssetId} · {gear.Status}\n" +
            $"{gear.Category}{subcategory} · {gear.Brand} {gear.Model}\n" +
            $"数量 {gear.Quantity:0.##} · 单件 {gear.Weight:0.##} g · 购买 {session.FormatMoney(gear.PurchasePrice)}\n" +
            $"渠道/日期：{gear.PurchaseFrom} · {gear.PurchaseDate} · 标签：{gear.Tags}\n" +
            $"存放位置：{locationName}\n" +
            $"附件：{gear.Extras.Attachments.Count} · 子装备：{childNames}";
    }
    private string GetLocationName(GearRecord gear)
    {
        return gear.Extras.LocationOverrideId is { } locationId
            ? session.Inventory.FindGear(locationId)?.Name ?? gear.Location
            : gear.Location;
    }
    private void Duplicate()
    {
        if (Selected is not { } row) return;
        var dialog = new DuplicateGearWindow(row.Gear, session.Inventory.Settings) { Owner = Window.GetWindow(this) };
        if (dialog.ShowDialog() != true) return;
        try { var copy = GearService.Duplicate(session.Inventory, row.Id, dialog.CopyAttachments, dialog.Prefix); session.SaveGear(copy); Refresh(); }
        catch (Exception error) { PageUi.Error(error); }
    }
    private void Favorite()
    {
        if (Selected is not { } row)
            return;
        try { session.ToggleFavorite(row.Id); }
        catch (Exception error) { PageUi.Error(error); }
    }
    private void Trash()
    {
        if (Selected is not { } row)
            return;
        session.Trash([row.Id], true);
        Refresh();
    }
    private void Import()
    {
        var dialog = new OpenFileDialog { Filter = "CSV/TSV 文件|*.csv;*.tsv;*.txt|所有文件|*.*" };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            session.ImportCsv(File.ReadAllText(dialog.FileName));
            Refresh();
            MessageBox.Show("导入完成");
        }
        catch (Exception error) { PageUi.Error(error); }
    }
    private void ImportExcel()
    {
        var dialog = new OpenFileDialog
        {
            Filter = "Excel 工作簿|*.xlsx;*.xlsm",
            Title = "选择未加密的 .xlsx 或 .xlsm 工作簿"
        };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            var window = new ExcelImportWindow(session, dialog.FileName) { Owner = Window.GetWindow(this) };
            if (window.ShowDialog() == true)
                Refresh();
        }
        catch (Exception error) { PageUi.Error(error); }
    }
    private void Export()
    {
        var dialog = new SaveFileDialog { Filter = "CSV 文件|*.csv", FileName = "装备库.csv" };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            File.WriteAllText(dialog.FileName, session.ExportCsv(), new System.Text.UTF8Encoding(true));
        }
        catch (Exception error) { PageUi.Error(error); }
    }
    private void ImportTrail()
    {
        var dialog = new OpenFileDialog { Filter = "GPX/KML 轨迹|*.gpx;*.kml" };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            using var stream = File.OpenRead(dialog.FileName);
            var route = TrailFileReader.Read(dialog.FileName, stream);
            session.Inventory.Root["selectedRoute"] = TrailFileReader.ToJson(route);
            session.Save();
            MessageBox.Show($"已导入路线：{route.Name}\n{route.Distance}");
        }
        catch (Exception error) { PageUi.Error(error); }
    }
}
