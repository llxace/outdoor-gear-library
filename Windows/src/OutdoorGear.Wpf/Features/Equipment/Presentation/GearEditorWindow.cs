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

public sealed class GearEditorWindow : Window
{
    private readonly ComboBox destinationUser = new() { MinWidth = 180, DisplayMemberPath = nameof(GearUserChoice.Name) };
    private readonly TextBox name = new();
    private readonly TextBox brand = new();
    private readonly TextBox model = new();
    private readonly TextBox weight = new();
    private readonly TextBox quantity = new();
    private readonly TextBox price = new();
    private readonly TextBox purchaseFrom = new();
    private readonly TextBox purchaseDate = new();
    private readonly TextBox location = new();
    private readonly TextBox tags = new();
    private readonly TextBox notes = new();
    private readonly TextBox description = new();
    private readonly TextBox assetId = new();
    private readonly ComboBox category = new();
    private readonly ComboBox status = new();
    private readonly ComboBox subcategory = new();
    private readonly ComboBox parent = new();
    private readonly ComboBox locationOverride = new();
    private readonly GearRecord? gear;
    private readonly LibrarySession session;
    private InventoryDocument editingInventory;
    private readonly string? initialParentId;
    private readonly ListBox attachmentList = new() { Height = 92 };
    private readonly TextBox attachmentTitle = new() { Width = 260, Height = 34 };
    public string NameValue => name.Text.Trim();
    public string BrandValue => brand.Text.Trim();
    public string ModelValue => model.Text.Trim();
    public string CategoryValue => category.SelectedItem?.ToString() ?? InventoryDocument.OutdoorCategories[7];
    public string StatusValue => status.SelectedItem?.ToString() ?? "可用";
    public double WeightValue => double.Parse(weight.Text);
    public double QuantityValue => double.Parse(quantity.Text);
    public double PriceValue => double.Parse(price.Text);
    public string PurchaseFromValue => purchaseFrom.Text.Trim();
    public string PurchaseDateValue => purchaseDate.Text.Trim();
    public string LocationValue => location.Text.Trim();
    public string TagsValue => tags.Text.Trim();
    public string NotesValue => notes.Text;
    public string DescriptionValue => description.Text;
    public int AssetIdValue => int.Parse(assetId.Text);
    public bool ContinueAdding { get; private set; }
    public string? SubcategoryValue => string.IsNullOrWhiteSpace(subcategory.SelectedItem?.ToString())
        ? null
        : subcategory.SelectedItem.ToString();
    public string? ParentIdValue => (parent.SelectedItem as GearParentChoice)?.Id;
    public string? LocationOverrideIdValue => (locationOverride.SelectedItem as GearParentChoice)?.Id;
    public string DestinationUserId => (destinationUser.SelectedItem as GearUserChoice)?.Id ?? session.SelectedUserId;
    public string? PhotoFile => selectedPhoto ?? gear?.Photo;
    public JsonArray Attachments { get; }
    private string? selectedPhoto;
    public GearEditorWindow(GearRecord? gear, LibrarySession session, string? parentId = null)
    {
        this.gear = gear;
        this.session = session;
        editingInventory = session.Inventory;
        initialParentId = parentId;
        Attachments = CopyAttachments(gear);
        ConfigureWindow(gear);
        ConfigureDestinationUser(gear);
        ConfigureChoices();
        ConfigureCategoryRelationships(parentId);
        category.SelectionChanged += (_, _) => RefreshSubcategories(gear?.Extras.Subcategory);

        var panel = BuildEditorPanel();
        PopulateEditorValues(gear);
        AddPhotoAndAttachmentControls(panel);
        panel.Children.Add(BuildDialogButtons());
        Content = new ScrollViewer { Content = panel };
    }
    private static JsonArray CopyAttachments(GearRecord? gear)
    {
        return gear?.Extras.Node["attachments"] is JsonArray attachments
            ? (JsonArray)attachments.DeepClone()
            : new JsonArray();
    }
    private void ConfigureWindow(GearRecord? gear)
    {
        Title = gear is null ? "新增装备" : "编辑装备";
        Width = 560;
        Height = 880;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
    }
    private void ConfigureChoices()
    {
        category.ItemsSource = InventoryDocument.OutdoorCategories;
        status.ItemsSource = new[] { "可用", "损坏", "维修中", "已借出", "想买", "借出", "已出售" };
        parent.ItemsSource = BuildParentChoices();
        locationOverride.ItemsSource = BuildLocationChoices();
    }
    private void ConfigureDestinationUser(GearRecord? gear)
    {
        if (gear is not null) return;
        destinationUser.ItemsSource = session.Users
            .Select(user => new GearUserChoice(user.Id, user.Name))
            .ToList();
        destinationUser.SelectedItem = ((IEnumerable<GearUserChoice>)destinationUser.ItemsSource)
            .FirstOrDefault(user => InventoryDocument.IdEquals(user.Id, session.SelectedUserId));
        destinationUser.SelectionChanged += DestinationUser_SelectionChanged;
    }
    private void DestinationUser_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (destinationUser.SelectedItem is not GearUserChoice selected) return;
        try
        {
            editingInventory = InventoryDocument.IdEquals(selected.Id, session.SelectedUserId)
                ? session.Inventory
                : session.ReadUserInventory(selected.Id);
            parent.ItemsSource = BuildParentChoices();
            locationOverride.ItemsSource = BuildLocationChoices();
            var preferredParent = InventoryDocument.IdEquals(selected.Id, session.SelectedUserId) ? initialParentId : null;
            ConfigureCategoryRelationships(preferredParent);
        }
        catch (Exception error)
        {
            PageUi.Error(error);
            destinationUser.SelectedItem = session.Users
                .Select(user => new GearUserChoice(user.Id, user.Name))
                .First(user => InventoryDocument.IdEquals(user.Id, session.SelectedUserId));
        }
    }
    private List<GearParentChoice> BuildParentChoices()
    {
        var choices = new List<GearParentChoice> { new(null, "无父级") };
        var currentId = gear?.Id ?? "00000000-0000-0000-0000-000000000000";
        var validParents = editingInventory.Gear(false).Where(item =>
            item.Id != gear?.Id && !item.Trashed &&
            GearService.CanSetParent(editingInventory, currentId, item.Id!));
        choices.AddRange(validParents.Select(item => new GearParentChoice(
            item.Id,
            item.Name + (item.IsLocation ? "（位置）" : ""))));
        return choices;
    }
    private List<GearParentChoice> BuildLocationChoices()
    {
        var choices = new List<GearParentChoice> { new(null, "使用父级位置") };
        var locations = editingInventory.Gear(false).Where(item =>
            item.IsLocation && !item.Trashed && item.Id != gear?.Id);
        choices.AddRange(locations.Select(item => new GearParentChoice(item.Id, item.Name)));
        return choices;
    }
    private void ConfigureCategoryRelationships(string? parentId)
    {
        var parentChoices = (List<GearParentChoice>)parent.ItemsSource;
        var locationChoices = (List<GearParentChoice>)locationOverride.ItemsSource;
        parent.SelectedItem = FindChoice(parentChoices, gear?.Extras.ParentId ?? parentId);
        locationOverride.SelectedItem = FindChoice(locationChoices, gear?.Extras.LocationOverrideId);
        RefreshSubcategories(gear?.Extras.Subcategory);
    }
    private static GearParentChoice FindChoice(IEnumerable<GearParentChoice> choices, string? id)
    {
        return choices.FirstOrDefault(item => InventoryDocument.IdEquals(item.Id, id)) ?? choices.First();
    }
    private StackPanel BuildEditorPanel()
    {
        var panel = new StackPanel { Margin = new Thickness(22) };
        if (gear is null)
        {
            AddField(panel, "保存到用户", destinationUser);
        }
        AddEditorFields(panel);
        return panel;
    }
    private void AddEditorFields(StackPanel panel)
    {
        AddField(panel, "名称", name);
        ConfigureMarkdownInput(description);
        AddField(panel, "描述", description);
        AddField(panel, "品牌", brand);
        AddField(panel, "型号", model);
        AddField(panel, "分类", category);
        AddField(panel, "子分类", subcategory);
        AddField(panel, "状态", status);
        AddField(panel, "单件重量（克）", weight);
        AddField(panel, "库存数量", quantity);
        AddField(panel, "购买价格", price);
        AddField(panel, "购买渠道", purchaseFrom);
        AddField(panel, "购买日期", purchaseDate);
        AddField(panel, "资产编号（0 为自动）", assetId);
        AddField(panel, "标签（逗号分隔）", tags);
        AddField(panel, "所属父级 / 位置", parent);
        AddField(panel, "指定存放位置", locationOverride);
        AddField(panel, "存放位置名称", location);
        ConfigureMarkdownInput(notes);
        AddField(panel, "笔记（支持 Markdown）", notes);
    }

    private static void ConfigureMarkdownInput(TextBox input)
    {
        input.AcceptsReturn = true;
        input.TextWrapping = TextWrapping.Wrap;
        input.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        input.ToolTip = "支持 Markdown：**粗体**、*斜体*、`代码`、[链接](https://...)";
    }

    private static void AddField(StackPanel panel, string label, Control control)
    {
        panel.Children.Add(new TextBlock
        {
            Text = label,
            Margin = new Thickness(0, 5, 0, 3),
            Foreground = System.Windows.Media.Brushes.Gray
        });
        control.Height = control is TextBox { AcceptsReturn: true } ? 96 : 34;
        control.Margin = new Thickness(0, 0, 0, 4);
        panel.Children.Add(control);
    }
    private void PopulateEditorValues(GearRecord? gear)
    {
        name.Text = gear?.Name ?? "";
        description.Text = gear?.Extras.Description ?? "";
        brand.Text = gear?.Brand ?? "";
        model.Text = gear?.Model ?? "";
        category.SelectedItem = gear?.Category ?? InventoryDocument.OutdoorCategories[7];
        status.SelectedItem = gear?.Status ?? "可用";
        weight.Text = (gear?.Weight ?? 0).ToString("0.##");
        quantity.Text = (gear?.Quantity ?? 1).ToString("0.##");
        price.Text = (gear?.PurchasePrice ?? 0).ToString("0.##");
        purchaseFrom.Text = gear?.PurchaseFrom ?? "";
        purchaseDate.Text = gear?.PurchaseDate ?? "";
        assetId.Text = (gear?.Extras.AssetId ?? 0).ToString(CultureInfo.InvariantCulture);
        tags.Text = gear?.Tags ?? "";
        location.Text = gear?.Location ?? "";
        notes.Text = gear?.Notes ?? "";
    }
    private void AddPhotoAndAttachmentControls(StackPanel panel)
    {
        var actions = new WrapPanel();
        actions.Children.Add(PageUi.Button("选择主照片", (_, _) => SelectPhoto()));
        actions.Children.Add(PageUi.Button("选择并修图", (_, _) => ProcessPhoto()));
        actions.Children.Add(PageUi.Button("添加附件", (_, _) => AddAttachment()));
        actions.Children.Add(PageUi.Button("重命名附件", (_, _) => RenameAttachment()));
        actions.Children.Add(PageUi.Button("移除附件", (_, _) => RemoveAttachment()));
        panel.Children.Add(actions);
        panel.Children.Add(attachmentTitle);
        panel.Children.Add(attachmentList);
        attachmentList.SelectionChanged += (_, _) => LoadAttachmentTitle();
        RefreshAttachments();
    }
    private UIElement BuildDialogButtons()
    {
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 12, 0, 0)
        };
        var cancel = new Button
        {
            Content = "取消",
            Padding = new Thickness(14, 7, 14, 7),
            Margin = new Thickness(0, 0, 8, 0)
        };
        cancel.Click += (_, _) => DialogResult = false;
        var save = new Button { Content = "保存", Padding = new Thickness(14, 7, 14, 7) };
        save.Click += SaveClicked;
        buttons.Children.Add(cancel);
        if (gear is null)
        {
            var saveAndContinue = new Button { Content = "保存并继续添加", Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(0, 0, 8, 0) };
            saveAndContinue.Click += SaveAndContinueClicked;
            buttons.Children.Add(saveAndContinue);
        }
        buttons.Children.Add(save);
        return buttons;
    }
    private void SaveClicked(object sender, RoutedEventArgs e)
    {
        try
        {
            ValidateEditorValues();
            DialogResult = true;
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void SaveAndContinueClicked(object sender, RoutedEventArgs e)
    {
        try
        {
            ValidateEditorValues();
            ContinueAdding = true;
            DialogResult = true;
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void ValidateEditorValues()
    {
        if (NameValue.Length == 0 || WeightValue < 0 || QuantityValue <= 0 || PriceValue < 0 || AssetIdValue < 0)
            throw new InvalidDataException("请检查名称、编号、重量、数量和价格。");
        if (LocationOverrideIdValue is { } locationId &&
            editingInventory.FindGear(locationId) is not { IsLocation: true })
            throw new InvalidDataException("指定位置必须选择位置记录。");
    }
    private void RefreshSubcategories(string? selected)
    {
        var values = SubcategoriesFor(CategoryValue);
        subcategory.ItemsSource = new[] { "" }.Concat(values).ToList();
        subcategory.SelectedItem = selected is not null && values.Contains(selected) ? selected : "";
    }
    private static string[] SubcategoriesFor(string category)
    {
        return category switch
        {
            "帐篷与睡眠" => ["帐篷", "睡袋", "防潮垫与睡眠配件"],
            "鞋袜与行走" => ["鞋", "袜子", "行走配件"],
            "服装与配饰" => ["贴身与速干", "抓绒与中层", "羽绒与棉服", "防风与雨衣", "裤装", "帽子与头巾", "手套", "眼镜与面罩", "其他服装"],
            _ => []
        };
    }
    private void SelectPhoto()
    {
        var dialog = new OpenFileDialog { Filter = "图片|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.heic" };
        if (dialog.ShowDialog(this) != true)
            return;
        try { selectedPhoto = session.ImportAsset(dialog.FileName, true); }
        catch (Exception error) { PageUi.Error(error); }
    }
    private void ProcessPhoto()
    {
        if (string.IsNullOrWhiteSpace(PhotoFile)) SelectPhoto();
        if (string.IsNullOrWhiteSpace(PhotoFile)) return;
        try
        {
            var sourcePath = GearAssetService.AssetPath(session.CurrentDataDirectory, "Photos", PhotoFile);
            var editor = new GearPhotoEditorWindow(sourcePath, session.CurrentDataDirectory) { Owner = this };
            if (editor.ShowDialog() != true || editor.OutputFile is not { } output)
                return;
            if (NeedsOriginalAttachment())
                Attachments.Add(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["title"] = "修图原图", ["file"] = PhotoFile, ["isImage"] = true });
            selectedPhoto = Path.GetFileName(output);
            RefreshAttachments();
        }
        catch (Exception error) { PageUi.Error(error); }
    }
    private bool NeedsOriginalAttachment()
    {
        return !Attachments.OfType<JsonObject>().Any(item =>
            item["title"]?.ToString() == "修图原图" &&
            item["file"]?.ToString() == PhotoFile);
    }
    private void AddAttachment()
    {
        var dialog = new OpenFileDialog { Filter = "所有文件|*.*", Multiselect = true };
        if (dialog.ShowDialog(this) != true)
            return;
        var originalCount = Attachments.Count;
        var imported = new List<string>();
        try
        {
            foreach (var path in dialog.FileNames)
            {
                var file = session.ImportAsset(path, false);
                imported.Add(file);
                Attachments.Add(CreateAttachment(path, file));
            }
            RefreshAttachments();
        }
        catch (Exception error)
        {
            while (Attachments.Count > originalCount) Attachments.RemoveAt(Attachments.Count - 1);
            foreach (var file in imported)
                try { File.Delete(GearAssetService.AssetPath(session.CurrentDataDirectory, "Files", file)); } catch { }
            RefreshAttachments();
            PageUi.Error(error);
        }
    }
    private static JsonObject CreateAttachment(string sourcePath, string file)
    {
        var imageExtensions = new[] { ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".heic" };
        return new JsonObject
        {
            ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(),
            ["title"] = Path.GetFileName(sourcePath),
            ["file"] = file,
            ["isImage"] = imageExtensions.Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase)
        };
    }
    private void RemoveAttachment()
    {
        var index = attachmentList.SelectedIndex;
        if (index < 0 || index >= Attachments.Count)
            return;
        Attachments.RemoveAt(index);
        RefreshAttachments();
    }
    private void LoadAttachmentTitle()
    {
        var attachment = Attachments.OfType<JsonObject>().ElementAtOrDefault(attachmentList.SelectedIndex);
        attachmentTitle.Text = attachment?["title"]?.ToString() ?? "";
    }
    private void RenameAttachment()
    {
        var attachment = Attachments.OfType<JsonObject>().ElementAtOrDefault(attachmentList.SelectedIndex);
        var title = attachmentTitle.Text.Trim();
        if (attachment is null || title.Length == 0)
        {
            PageUi.Error(new InvalidOperationException("请选择附件并输入名称。"));
            return;
        }
        attachment["title"] = title;
        RefreshAttachments();
        attachmentList.SelectedIndex = Attachments.IndexOf(attachment);
    }
    private void RefreshAttachments()
    {
        attachmentList.ItemsSource = Attachments.OfType<JsonObject>()
            .Select(item => item["title"]?.ToString())
            .ToList();
    }
}
