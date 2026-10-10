using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;



using OutdoorGear.Wpf.Features.Shared.Presentation;

namespace OutdoorGear.Wpf.Features.Equipment.Presentation;

public sealed class ExcelImportWindow : Window
{
    private readonly LibrarySession session;
    private readonly string filename;
    private readonly ComboBox sheets = new() { MinWidth = 280 };
    private readonly TextBox headerRow = new() { Width = 64, Text = "1" };
    private readonly CheckBox updateExisting = new() { Content = "按装备 ID 更新已有记录", IsChecked = true, VerticalAlignment = VerticalAlignment.Center };
    private readonly DataGrid mappingGrid = new() { AutoGenerateColumns = false, CanUserAddRows = false, Height = 350 };
    private readonly ListBox preview = new() { FontFamily = new System.Windows.Media.FontFamily("Consolas"), MinWidth = 300 };
    private readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 8) };
    private IReadOnlyList<IReadOnlyList<string>> rows = [];
    private List<ExcelMappingRow> mappings = [];
    private bool loading;

    public ExcelImportWindow(LibrarySession session, string filename)
    {
        this.session = session; this.filename = filename;
        Title = "导入 Excel 装备表"; Width = 1040; Height = 760; MinWidth = 900; MinHeight = 620; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new DockPanel { Margin = new Thickness(20) };
        var title = new StackPanel(); title.Children.Add(new TextBlock { Text = "导入 Excel 装备表", FontSize = 23, FontWeight = FontWeights.SemiBold }); title.Children.Add(new TextBlock { Text = System.IO.Path.GetFileName(filename), Margin = new Thickness(0, 4, 0, 14), Foreground = System.Windows.Media.Brushes.Gray }); DockPanel.SetDock(title, Dock.Top); root.Children.Add(title);
        var top = new WrapPanel { Margin = new Thickness(0, 0, 0, 12), VerticalAlignment = VerticalAlignment.Center };
        top.Children.Add(new TextBlock { Text = "工作表", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) }); top.Children.Add(sheets); sheets.SelectionChanged += (_, _) => LoadSheet();
        top.Children.Add(new TextBlock { Text = "表头行", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(18, 0, 6, 0) }); top.Children.Add(headerRow); headerRow.LostFocus += (_, _) => ResetMapping(); top.Children.Add(updateExisting); DockPanel.SetDock(top, Dock.Top); root.Children.Add(top);
        var split = new Grid(); split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); split.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var left = new DockPanel { Margin = new Thickness(0, 0, 12, 0) }; left.Children.Add(new TextBlock { Text = "列与目标字段", FontSize = 16, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8) }); DockPanel.SetDock(left.Children[^1], Dock.Top); BuildMappingGrid(); left.Children.Add(mappingGrid); split.Children.Add(left);
        var right = new DockPanel { Margin = new Thickness(12, 0, 0, 0) }; right.Children.Add(new TextBlock { Text = "工作表预览（最多显示 12 行）", FontSize = 16, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8) }); DockPanel.SetDock(right.Children[^1], Dock.Top); right.Children.Add(preview); Grid.SetColumn(right, 1); split.Children.Add(right);
        DockPanel.SetDock(split, Dock.Top); root.Children.Add(split);
        status.Text = "仅读取装备基本资料，不运行工作簿宏。重复导入可按装备 ID 更新；空白字段会保留已有值。"; DockPanel.SetDock(status, Dock.Bottom); root.Children.Add(status);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 10, 0, 0) };
        var cancel = new Button { Content = "取消", Padding = new Thickness(18, 8, 18, 8), Margin = new Thickness(0, 0, 8, 0) }; cancel.Click += (_, _) => DialogResult = false;
        var import = new Button { Content = "确认导入", Padding = new Thickness(18, 8, 18, 8) }; import.Click += Import_Click; buttons.Children.Add(cancel); buttons.Children.Add(import); DockPanel.SetDock(buttons, Dock.Bottom); root.Children.Add(buttons);
        Content = root;
        try
        {
            using var workbook = new ExcelWorkbook(filename);
            sheets.ItemsSource = workbook.Sheets;
            sheets.DisplayMemberPath = nameof(ExcelWorksheet.Name);
            sheets.SelectedItem = workbook.Sheets.FirstOrDefault(sheet => sheet.Name.Contains("主库", StringComparison.Ordinal)) ?? workbook.Sheets[0];
        }
        catch (Exception e) { status.Text = e.Message; }
    }

    private void BuildMappingGrid()
    {
        mappingGrid.Columns.Add(new DataGridTextColumn { Header = "原表列名", Binding = new Binding(nameof(ExcelMappingRow.Header)), IsReadOnly = true, Width = new DataGridLength(1, DataGridLengthUnitType.Star) });
        mappingGrid.Columns.Add(new DataGridComboBoxColumn { Header = "对应字段", ItemsSource = ExcelImportService.Fields, SelectedItemBinding = new Binding(nameof(ExcelMappingRow.Field)) { UpdateSourceTrigger = UpdateSourceTrigger.PropertyChanged }, Width = new DataGridLength(1.2, DataGridLengthUnitType.Star) });
    }

    private void LoadSheet()
    {
        if (loading || sheets.SelectedItem is not ExcelWorksheet selected) return;
        try
        {
            using var workbook = new ExcelWorkbook(filename);
            rows = workbook.ReadRows(workbook.Sheets.First(sheet => sheet.Path == selected.Path));
            var row = ExcelImportService.DetectHeaderRow(rows);
            headerRow.Text = (row + 1).ToString();
            RebuildMapping(row);
            status.Text = $"工作表共 {rows.Count} 行。可调整表头行和字段对应关系后预览导入。";
        }
        catch (Exception e) { rows = []; mappingGrid.ItemsSource = null; preview.ItemsSource = null; status.Text = e.Message; }
    }

    private void ResetMapping()
    {
        if (loading || !int.TryParse(headerRow.Text, out var oneBased) || oneBased < 1 || oneBased > rows.Count) return;
        RebuildMapping(oneBased - 1);
    }

    private void RebuildMapping(int header)
    {
        if (header < 0 || header >= rows.Count) return;
        loading = true;
        var values = rows[header]; var guesses = ExcelImportService.GuessMapping(values);
        mappings = values.Select((value, index) => new ExcelMappingRow(string.IsNullOrWhiteSpace(value) ? $"空列 {index + 1}" : value, guesses[index])).ToList();
        mappingGrid.ItemsSource = mappings;
        preview.ItemsSource = rows.Skip(header).Take(12).Select((row, offset) => $"{header + offset + 1,4}: {string.Join("  │  ", row)}").ToArray();
        loading = false;
    }

    private void Import_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            mappingGrid.CommitEdit(DataGridEditingUnit.Cell, true); mappingGrid.CommitEdit(DataGridEditingUnit.Row, true);
            if (sheets.SelectedItem is not ExcelWorksheet sheet || !int.TryParse(headerRow.Text, out var header) || header < 1) throw new InvalidDataException("请选择工作表并填写有效的表头行。");
            var result = ExcelImportService.Import(filename, sheet.Name, header - 1, mappings.Select(item => item.Field).ToArray(), session.Inventory, updateExisting.IsChecked == true);
            var warnings = result.Warnings.Count == 0 ? "" : $"\n有 {result.Warnings.Count} 个数字字段未能识别，请检查原表。";
            if (MessageBox.Show($"新增 {result.Added} 项，更新 {result.Updated} 项，跳过 {result.Skipped} 行。{warnings}\n\n确认写入当前资料库？", "导入预览", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            session.ImportExcel(result);
            MessageBox.Show(session.Message, "Excel 导入完成", MessageBoxButton.OK, MessageBoxImage.Information);
            DialogResult = true;
        }
        catch (Exception error) { PageUi.Error(error); }
    }
}

public sealed class ExcelMappingRow : INotifyPropertyChanged
{
    private string selectedField;
    public string Header { get; }
    public ExcelMappingRow(string header, string selectedField) { Header = header; this.selectedField = selectedField; }
    public string Field { get => selectedField; set { if (selectedField == value) return; selectedField = value; PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Field))); } }
    public event PropertyChangedEventHandler? PropertyChanged;
}
