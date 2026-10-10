using System.Windows;
using System.Windows.Controls;



namespace OutdoorGear.Wpf.Features.Equipment.Presentation;

public sealed class BatchGearWindow : Window
{
    private readonly ComboBox action = new() { ItemsSource = new[] { "批量修改状态", "移入回收站", "从回收站恢复" }, SelectedIndex = 0 };
    private readonly ComboBox status = new() { ItemsSource = new[] { "可用", "想买", "借出", "损坏", "已出售" }, SelectedIndex = 0 };
    public string? StatusValue => action.SelectedIndex == 0 ? status.SelectedItem?.ToString() : null;
    public bool? TrashedValue => action.SelectedIndex switch { 1 => true, 2 => false, _ => null };

    public BatchGearWindow(int count)
    {
        Title = "批量操作"; Width = 470; Height = 300; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new StackPanel { Margin = new Thickness(22) };
        root.Children.Add(new TextBlock { Text = $"批量操作 · {count} 条装备记录", FontSize = 20, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 12) });
        root.Children.Add(new TextBlock { Text = "操作", Margin = new Thickness(0, 4, 0, 3) }); root.Children.Add(action);
        root.Children.Add(new TextBlock { Text = "新状态", Margin = new Thickness(0, 8, 0, 3) }); root.Children.Add(status);
        root.Children.Add(new TextBlock { Text = "移入回收站或恢复时会同时处理所选装备的子装备；状态修改只影响所选装备。回收站记录可以恢复。", TextWrapping = TextWrapping.Wrap, Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(0, 12, 0, 12) });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "取消", Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(0, 0, 8, 0) }; cancel.Click += (_, _) => DialogResult = false;
        var apply = new Button { Content = "应用", Padding = new Thickness(14, 7, 14, 7) }; apply.Click += (_, _) => DialogResult = true;
        buttons.Children.Add(cancel); buttons.Children.Add(apply); root.Children.Add(buttons); Content = root;
        action.SelectionChanged += (_, _) => status.IsEnabled = action.SelectedIndex == 0;
    }
}
