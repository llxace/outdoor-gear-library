using System.Windows;
using System.Windows.Controls;
using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Wpf.Features.Equipment.Presentation;

public sealed class DuplicateGearWindow : Window
{
    private readonly CheckBox attachments = new() { Content = "复制照片和附件", Margin = new Thickness(0, 8, 0, 12) };
    private readonly TextBox prefix = new() { Height = 34, Padding = new Thickness(8) };

    public bool CopyAttachments => attachments.IsChecked == true;
    public string Prefix => prefix.Text;

    public DuplicateGearWindow(GearRecord gear, JsonObject settings)
    {
        Title = "复制装备"; Width = 440; Height = 250; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        attachments.IsChecked = InventoryDocument.Bool(settings["copyAttachments"], true);
        prefix.Text = settings["copyPrefix"]?.ToString() ?? "副本 · ";
        var panel = new StackPanel { Margin = new Thickness(22) };
        panel.Children.Add(new TextBlock { Text = $"复制：{gear.Name}", FontSize = 20, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(attachments);
        panel.Children.Add(new TextBlock { Text = "名称前缀", Margin = new Thickness(0, 0, 0, 5) });
        panel.Children.Add(prefix);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        var cancel = new Button { Content = "取消", Margin = new Thickness(0, 0, 8, 0) }; cancel.Click += (_, _) => DialogResult = false;
        var confirm = new Button { Content = "复制" }; confirm.Click += (_, _) => DialogResult = true;
        buttons.Children.Add(cancel); buttons.Children.Add(confirm); panel.Children.Add(buttons); Content = panel;
    }
}
