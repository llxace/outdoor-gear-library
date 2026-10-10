using System.IO;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;



using OutdoorGear.Wpf.Features.Shared.Presentation;

namespace OutdoorGear.Wpf.Features.Equipment.Presentation;

public sealed class GearMetadataWindow : Window
{
    private readonly LibrarySession session;
    private readonly GearRecord? sourceGear;
    private readonly ListBox labels = new();
    private readonly TextBox labelName = new(), labelDescription = new();
    private readonly ComboBox labelColor = new(), labelParent = new();
    private readonly ListBox templates = new();
    private readonly TextBox templateName = new(), templatePreview = new();
    private JsonObject? editingLabel, editingTemplate;
    public string? AppliedTemplateId { get; private set; }

    public GearMetadataWindow(LibrarySession session, GearRecord? sourceGear)
    {
        this.session = session; this.sourceGear = sourceGear;
        Title = "标签与装备模板"; Width = 820; Height = 620; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var tabs = new TabControl(); tabs.Items.Add(BuildLabelsTab()); tabs.Items.Add(BuildTemplatesTab()); Content = tabs;
        RefreshLabels(); RefreshTemplates();
    }

    private TabItem BuildLabelsTab()
    {
        var root = new Grid { Margin = new Thickness(16) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.4, GridUnitType.Star) });
        var left = new DockPanel { Margin = new Thickness(0, 0, 16, 0) };
        labels.SelectionChanged += (_, _) => LoadLabel();
        var labelButtons = new StackPanel { Orientation = Orientation.Horizontal };
        labelButtons.Children.Add(PageUi.Button("新建", (_, _) => NewLabel()));
        labelButtons.Children.Add(PageUi.Button("删除", (_, _) => RemoveLabel()));
        DockPanel.SetDock(labelButtons, Dock.Bottom); left.Children.Add(labelButtons); left.Children.Add(labels); Grid.SetColumn(left, 0); root.Children.Add(left);

        var form = new StackPanel(); Add("标签名称（装备标签以逗号分隔）", labelName); Add("描述", labelDescription);
        labelColor.ItemsSource = new[] { "绿色", "蓝色", "橙色", "红色", "紫色", "灰色" }; Add("颜色", labelColor); Add("父级标签", labelParent);
        var save = new Button { Content = "保存标签", Padding = new Thickness(14, 7, 14, 7), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        save.Click += (_, _) => SaveLabel(); form.Children.Add(save); Grid.SetColumn(form, 1); root.Children.Add(form);
        return new TabItem { Header = "标签", Content = root };
        void Add(string caption, Control control) { form.Children.Add(new TextBlock { Text = caption, Margin = new Thickness(0, 6, 0, 3), Foreground = System.Windows.Media.Brushes.Gray }); control.Height = 32; control.Margin = new Thickness(0, 0, 0, 4); form.Children.Add(control); }
    }

    private TabItem BuildTemplatesTab()
    {
        var root = new Grid { Margin = new Thickness(16) };
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.4, GridUnitType.Star) });
        var left = new DockPanel { Margin = new Thickness(0, 0, 16, 0) };
        templates.SelectionChanged += (_, _) => LoadTemplate();
        var listButtons = new StackPanel { Orientation = Orientation.Horizontal };
        listButtons.Children.Add(PageUi.Button("从所选装备新建", (_, _) => NewTemplateFromSelection()));
        listButtons.Children.Add(PageUi.Button("删除", (_, _) => RemoveTemplate()));
        DockPanel.SetDock(listButtons, Dock.Bottom); left.Children.Add(listButtons); left.Children.Add(templates); Grid.SetColumn(left, 0); root.Children.Add(left);
        var form = new StackPanel();
        form.Children.Add(new TextBlock { Text = sourceGear is null ? "从装备库选择一件装备后，可将其保存为模板。" : $"当前所选：{sourceGear.Name}", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) });
        form.Children.Add(new TextBlock { Text = "模板名称", Foreground = System.Windows.Media.Brushes.Gray }); templateName.Height = 32; templateName.Margin = new Thickness(0, 4, 0, 12); form.Children.Add(templateName);
        templatePreview.IsReadOnly = true; templatePreview.AcceptsReturn = true; templatePreview.TextWrapping = TextWrapping.Wrap; templatePreview.VerticalScrollBarVisibility = ScrollBarVisibility.Auto; templatePreview.Height = 300; form.Children.Add(templatePreview);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        var save = new Button { Content = "保存模板名称", Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(0, 0, 8, 0) }; save.Click += (_, _) => SaveTemplate();
        var apply = new Button { Content = "应用模板并新增装备", Padding = new Thickness(14, 7, 14, 7) }; apply.Click += (_, _) => ApplySelectedTemplate();
        actions.Children.Add(save); actions.Children.Add(apply); form.Children.Add(actions); Grid.SetColumn(form, 1); root.Children.Add(form);
        return new TabItem { Header = "装备模板", Content = root };
    }

    private void RefreshLabels(string? selectedId = null)
    {
        var choices = session.Inventory.Labels.OfType<JsonObject>().OrderBy(item => item["name"]?.ToString(), StringComparer.CurrentCultureIgnoreCase).Select(item => new MetadataChoice(item)).ToList();
        labels.ItemsSource = choices; labels.DisplayMemberPath = nameof(MetadataChoice.Name);
        RefreshLabelParents();
        labels.SelectedItem = choices.FirstOrDefault(item => InventoryDocument.IdEquals(item.Value["id"]?.ToString(), selectedId)) ?? choices.FirstOrDefault();
    }

    private void LoadLabel()
    {
        editingLabel = labels.SelectedItem is MetadataChoice selected ? (JsonObject)selected.Value.DeepClone() : null;
        labelName.Text = editingLabel?["name"]?.ToString() ?? ""; labelDescription.Text = editingLabel?["description"]?.ToString() ?? "";
        var color = editingLabel?["color"]?.ToString() ?? "绿色"; labelColor.SelectedItem = labelColor.Items.Contains(color) ? color : "绿色";
        RefreshLabelParents();
        var parents = (IEnumerable<GearParentChoice>)labelParent.ItemsSource;
        labelParent.SelectedItem = parents.FirstOrDefault(item => InventoryDocument.IdEquals(item.Id, editingLabel?["parentID"]?.ToString())) ?? parents.FirstOrDefault();
    }

    private void NewLabel()
    {
        editingLabel = new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["name"] = "", ["description"] = "", ["color"] = "绿色" };
        labelName.Text = ""; labelDescription.Text = ""; labelColor.SelectedItem = "绿色"; RefreshLabelParents(); labelParent.SelectedIndex = 0; labelName.Focus();
    }

    private void RefreshLabelParents()
    {
        var currentId = editingLabel?["id"]?.ToString();
        var parents = new List<GearParentChoice> { new(null, "无父级") };
        parents.AddRange(session.Inventory.Labels.OfType<JsonObject>().Where(item => !InventoryDocument.IdEquals(item["id"]?.ToString(), currentId)).Select(item => new GearParentChoice(item["id"]?.ToString(), item["name"]?.ToString() ?? "")));
        labelParent.ItemsSource = parents; labelParent.SelectedIndex = 0;
    }

    private void SaveLabel()
    {
        try
        {
            var label = editingLabel is null ? new JsonObject() : (JsonObject)editingLabel.DeepClone();
            label["name"] = labelName.Text.Trim(); label["description"] = labelDescription.Text; label["color"] = labelColor.SelectedItem?.ToString() ?? "绿色"; label["parentID"] = (labelParent.SelectedItem as GearParentChoice)?.Id;
            GearMetadataService.SaveLabel(session.Inventory, label); session.Save(); editingLabel = label; RefreshLabels(label["id"]?.ToString());
        }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void RemoveLabel()
    {
        if (editingLabel?["id"]?.ToString() is not { } id) return;
        if (MessageBox.Show($"删除标签“{editingLabel["name"]}”？装备和模板上的该标签也会移除。", "删除标签", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        try { GearMetadataService.RemoveLabel(session.Inventory, id); session.Save(); editingLabel = null; RefreshLabels(); }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void RefreshTemplates(string? selectedId = null)
    {
        var choices = session.Inventory.Templates.OfType<JsonObject>().OrderBy(item => item["name"]?.ToString(), StringComparer.CurrentCultureIgnoreCase).Select(item => new MetadataChoice(item)).ToList();
        templates.ItemsSource = choices; templates.DisplayMemberPath = nameof(MetadataChoice.Name);
        templates.SelectedItem = choices.FirstOrDefault(item => InventoryDocument.IdEquals(item.Value["id"]?.ToString(), selectedId)) ?? choices.FirstOrDefault();
    }

    private void LoadTemplate()
    {
        editingTemplate = templates.SelectedItem is MetadataChoice selected ? (JsonObject)selected.Value.DeepClone() : null;
        templateName.Text = editingTemplate?["name"]?.ToString() ?? "";
        templatePreview.Text = editingTemplate?["gear"] is JsonObject gear ? $"{gear["category"]} · {gear["brand"]} {gear["model"]}\n{gear["name"]}\n重量 {InventoryDocument.Number(gear["weight"]):0.##} g · 数量 {InventoryDocument.Number(gear["quantity"], 1):0.##}\n{gear["tags"]}\n{gear["notes"]}" : "选择模板或从所选装备创建模板。";
    }

    private void NewTemplateFromSelection()
    {
        if (sourceGear is null) { PageUi.Error(new InvalidOperationException("请先在装备库选中一件装备，再打开模板管理。")); return; }
        editingTemplate = new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["name"] = sourceGear.Name + "模板", ["gear"] = sourceGear.Node.DeepClone(), ["extras"] = sourceGear.Extras.Node.DeepClone() };
        templateName.Text = editingTemplate["name"]!.ToString(); LoadTemplatePreview();
    }

    private void LoadTemplatePreview()
    {
        var gear = editingTemplate?["gear"] as JsonObject;
        templatePreview.Text = gear is null ? "选择模板或从所选装备创建模板。" : $"{gear["category"]} · {gear["brand"]} {gear["model"]}\n{gear["name"]}\n重量 {InventoryDocument.Number(gear["weight"]):0.##} g · 数量 {InventoryDocument.Number(gear["quantity"], 1):0.##}\n{gear["tags"]}\n{gear["notes"]}";
    }

    private void SaveTemplate()
    {
        if (editingTemplate is null && sourceGear is not null) NewTemplateFromSelection();
        if (editingTemplate is null) { PageUi.Error(new InvalidOperationException("请先选择模板，或从所选装备新建模板。")); return; }
        try { editingTemplate["name"] = templateName.Text.Trim(); GearMetadataService.SaveTemplate(session.Inventory, editingTemplate); session.Save(); RefreshTemplates(editingTemplate["id"]?.ToString()); }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void RemoveTemplate()
    {
        if (editingTemplate?["id"]?.ToString() is not { } id) return;
        if (MessageBox.Show($"删除模板“{editingTemplate["name"]}”？", "删除模板", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        try { GearMetadataService.RemoveTemplate(session.Inventory, id); session.Save(); editingTemplate = null; RefreshTemplates(); }
        catch (Exception error) { PageUi.Error(error); }
    }

    private void ApplySelectedTemplate()
    {
        var id = editingTemplate?["id"]?.ToString();
        if (id is null) { PageUi.Error(new InvalidOperationException("请选择一个装备模板。")); return; }
        AppliedTemplateId = id; DialogResult = true;
    }
}

internal sealed class MetadataChoice(JsonObject value)
{
    public JsonObject Value { get; } = value;
    public string Name => Value["name"]?.ToString() ?? "";
}
