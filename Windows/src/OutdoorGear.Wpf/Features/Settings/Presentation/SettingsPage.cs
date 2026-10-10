using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;
using OutdoorGear.Wpf.Features.Equipment.Presentation;
using OutdoorGear.Wpf.Features.Photos.Presentation;
using OutdoorGear.Wpf.Features.Profiles.Presentation;
using OutdoorGear.Wpf.Features.Shared.Presentation;

namespace OutdoorGear.Wpf.Features.Settings.Presentation;

public sealed class SettingsPage : UserControl
{
    private readonly LibrarySession session;
    private readonly TextBox profileName = new() { Width = 220 };
    private readonly TextBox libraryName = new() { Width = 220 };
    private readonly TextBox copyPrefix = new() { Width = 180 };
    private readonly ComboBox currency = new() { Width = 140 };
    private readonly ComboBox appearance = new() { Width = 160 };
    private readonly CheckBox autoId = new()
    {
        Content = "自动生成装备编号",
        Margin = new Thickness(0, 8, 0, 8)
    };
    private readonly CheckBox copyAttachments = new()
    {
        Content = "复制装备时包含照片与附件",
        Margin = new Thickness(0, 8, 0, 8)
    };
    private readonly TextBlock exchangeStatus = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 8) };
    public SettingsPage(LibrarySession session)
    {
        this.session = session;
        InitializeSettingsFields();
        exchangeStatus.Text = session.ExchangeDescription;
        var root = BuildSettingsContent();
        Content = new ScrollViewer
        {
            Content = root,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
    }
    private void InitializeSettingsFields()
    {
        var settings = session.Inventory.Settings;
        libraryName.Text = settings["name"]?.ToString() ?? "户外装备库";
        copyPrefix.Text = settings["copyPrefix"]?.ToString() ?? "副本 · ";
        currency.ItemsSource = new[] { "CNY", "USD", "EUR", "GBP", "JPY", "HKD", "TWD" };
        currency.SelectedItem = settings["currency"]?.ToString() ?? "CNY";
        appearance.ItemsSource = new[] { "跟随系统", "浅色", "深色" };
        appearance.SelectedItem = settings["appearance"]?.ToString() ?? "跟随系统";
        autoId.IsChecked = InventoryDocument.Bool(settings["autoAssetID"], true);
        copyAttachments.IsChecked = InventoryDocument.Bool(settings["copyAttachments"], true);
    }
    private StackPanel BuildSettingsContent()
    {
        var root = PageUi.Root("设置", "本地数据、用户资料、外观、币种与备份");
        root.Children.Add(BuildLibrarySummary());
        root.Children.Add(BuildLibrarySettings());
        root.Children.Add(BuildProfileSettings());
        root.Children.Add(BuildCleanupSettings());
        root.Children.Add(BuildBackupSettings());
        root.Children.Add(PageUi.Button("关于户外装备库", (_, _) => ShowAbout()));
        return root;
    }
    private void ShowAbout()
    {
        var version = typeof(SettingsPage).Assembly.GetName().Version;
        var displayVersion = version is null ? "开发版" : $"{version.Major}.{version.Minor}.{version.Build} ({version.Revision})";
        var content = new StackPanel { Margin = new Thickness(24), HorizontalAlignment = HorizontalAlignment.Center };
        content.Children.Add(new Border
        {
            Width = 72,
            Height = 72,
            CornerRadius = new CornerRadius(16),
            Background = (System.Windows.Media.Brush)Application.Current.Resources["AccentBrush"],
            Child = new TextBlock { Text = "🎒", FontSize = 38, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }
        });
        content.Children.Add(new TextBlock { Text = "户外装备库", FontSize = 22, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 16, 0, 4) });
        content.Children.Add(new TextBlock { Text = $"Windows 原生版 · {displayVersion}", HorizontalAlignment = HorizontalAlignment.Center, Foreground = System.Windows.Media.Brushes.Gray });
        content.Children.Add(new TextBlock { Text = "个人装备、徒步打包与历史记录管理", HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) });
        var about = new Window
        {
            Title = "关于户外装备库",
            Width = 360,
            Height = 310,
            ResizeMode = ResizeMode.NoResize,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Owner = Window.GetWindow(this),
            Content = content
        };
        about.ShowDialog();
    }
    private UIElement BuildLibrarySummary()
    {
        return new TextBlock
        {
            Text = $"当前资料库：{session.CurrentUserName}\n有效装备：{session.ActiveGearCount} · 徒步记录：{session.HistoryCount}\n存储：Windows 本机应用数据目录",
            Margin = new Thickness(0, 4, 0, 14),
            FontSize = 15
        };
    }
    private UIElement BuildLibrarySettings()
    {
        var section = new StackPanel();
        section.Children.Add(Section("资料库设置"));
        section.Children.Add(BuildPreferenceControls());
        section.Children.Add(autoId);
        section.Children.Add(copyAttachments);
        section.Children.Add(exchangeStatus);
        section.Children.Add(PageUi.Button("刷新参考汇率", (_, _) => _ = RefreshExchangeRatesAsync()));
        section.Children.Add(BuildExchangeDescription());
        section.Children.Add(PageUi.Button("保存设置", (_, _) => SaveSettings()));
        return section;
    }
    private UIElement BuildPreferenceControls()
    {
        var preferences = new WrapPanel();
        AddPreference(preferences, "名称", libraryName, 0);
        AddPreference(preferences, "货币", currency, 14);
        AddPreference(preferences, "外观", appearance, 14);
        AddPreference(preferences, "复制名称前缀", copyPrefix, 14);
        return preferences;
    }
    private static void AddPreference(WrapPanel panel, string label, Control control, double leftMargin)
    {
        panel.Children.Add(new TextBlock
        {
            Text = label,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(leftMargin, 0, 8, 8)
        });
        panel.Children.Add(control);
    }
    private static UIElement BuildExchangeDescription()
    {
        return new TextBlock
        {
            Text = "汇率为每日参考价；装备与路餐价格仍以人民币录入。",
            Foreground = System.Windows.Media.Brushes.Gray,
            Margin = new Thickness(0, 0, 0, 8)
        };
    }
    private UIElement BuildProfileSettings()
    {
        var section = new StackPanel();
        section.Children.Add(Section("用户资料"));
        section.Children.Add(BuildProfileActions());
        return section;
    }
    private UIElement BuildProfileActions()
    {
        var actions = new WrapPanel();
        AddPreference(actions, "新资料库名称", profileName, 0);
        actions.Children.Add(PageUi.Button("创建资料库", (_, _) => CreateProfile()));
        actions.Children.Add(PageUi.Button("重命名当前用户", (_, _) => RenameProfile()));
        actions.Children.Add(PageUi.Button("选择并裁剪头像", (_, _) => ChangeAvatar()));
        actions.Children.Add(PageUi.Button("裁剪当前头像", (_, _) => CropCurrentAvatar()));
        actions.Children.Add(PageUi.Button("使用默认头像", (_, _) => UseDefaultAvatar()));
        return actions;
    }
    private UIElement BuildCleanupSettings()
    {
        var section = new StackPanel();
        section.Children.Add(Section("快速整理与导入"));
        section.Children.Add(PageUi.Button("导入 Excel 表格", (_, _) => ImportExcel()));
        section.Children.Add(BuildExcelImportDescription());
        section.Children.Add(Section("整理工具"));
        section.Children.Add(BuildCleanupActions());
        section.Children.Add(Section("批量清理"));
        section.Children.Add(PageUi.Button("将当前用户全部装备移入回收站", (_, _) => TrashAllGear()));
        return section;
    }
    private static UIElement BuildExcelImportDescription()
    {
        return new TextBlock
        {
            Text = "导入前可预览字段映射；按装备 ID 更新已有记录。",
            Foreground = System.Windows.Media.Brushes.Gray,
            Margin = new Thickness(0, 0, 0, 8)
        };
    }
    private UIElement BuildCleanupActions()
    {
        var actions = new WrapPanel();
        actions.Children.Add(PageUi.Button("补齐缺失装备编号", (_, _) => RunCleanup("装备编号", session.EnsureIdentifiers)));
        actions.Children.Add(PageUi.Button("为装备设置第一张照片", (_, _) => RunCleanup("主照片", session.SetMissingPrimaryPhotos)));
        actions.Children.Add(PageUi.Button("标准化购买日期", (_, _) => RunCleanup("购买日期", session.NormalizePurchaseDates)));
        return actions;
    }
    private UIElement BuildBackupSettings()
    {
        var section = new StackPanel();
        section.Children.Add(Section("备份与迁移"));
        section.Children.Add(BuildBackupActions());
        section.Children.Add(BuildBackupDescription());
        return section;
    }
    private UIElement BuildBackupActions()
    {
        var actions = new WrapPanel();
        actions.Children.Add(PageUi.Button("备份当前资料库", (_, _) => Backup()));
        actions.Children.Add(PageUi.Button("从 ZIP 恢复", (_, _) => RestoreZip()));
        actions.Children.Add(PageUi.Button("导入旧版备份文件夹", (_, _) => RestoreFolder()));
        actions.Children.Add(PageUi.Button("导入 CSV/TSV", (_, _) => Import()));
        actions.Children.Add(PageUi.Button("导出 CSV", (_, _) => Export()));
        actions.Children.Add(PageUi.Button("打开本机数据目录", (_, _) => OpenDataFolder()));
        return actions;
    }
    private static UIElement BuildBackupDescription()
    {
        return new TextBlock
        {
            Text = "备份仅包含当前用户资料库及其照片、附件。恢复时按记录 ID 合并：同 ID 由备份替换，其他记录保留；恢复前会自动生成当前资料库备份。兼容旧版 .gearbackup 文件夹。",
            Foreground = System.Windows.Media.Brushes.Gray,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 14, 0, 0)
        };
    }
    private static TextBlock Section(string title) => new() { Text = title, FontSize = 18, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 18, 0, 8) };
    private void SaveSettings()
    {
        try
        {
            SaveSettingsValues();
            ApplyAppearance();
            RefreshRatesWhenNeeded();
            MessageBox.Show("设置已保存。", "设置");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void SaveSettingsValues()
    {
        if (string.IsNullOrWhiteSpace(libraryName.Text))
            throw new InvalidDataException("资料库名称不能为空。");

        var settings = session.Inventory.Settings;
        settings["name"] = libraryName.Text.Trim();
        settings["currency"] = SelectedCurrency();
        settings["appearance"] = SelectedAppearance();
        settings["autoAssetID"] = autoId.IsChecked == true;
        settings["copyAttachments"] = copyAttachments.IsChecked == true;
        settings["copyPrefix"] = copyPrefix.Text;
        session.Save();
    }
    private void ApplyAppearance()
    {
        ((App)Application.Current).ApplyAppearance(SelectedAppearance());
    }
    private string SelectedCurrency() => currency.SelectedItem?.ToString() ?? "CNY";
    private string SelectedAppearance() => appearance.SelectedItem?.ToString() ?? "跟随系统";
    private void RefreshRatesWhenNeeded()
    {
        if (SelectedCurrency() != "CNY")
            _ = RefreshExchangeRatesAsync();
    }
    private void RenameProfile()
    {
        var current = session.Users.FirstOrDefault(user =>
            InventoryDocument.IdEquals(user.Id, session.SelectedUserId));
        if (current is null)
            return;

        var value = Microsoft.VisualBasic.Interaction.InputBox(
            "输入新的用户名称",
            "重命名用户",
            current.Name);
        if (string.IsNullOrWhiteSpace(value) || value == current.Name)
            return;

        try
        {
            session.SaveProfile(value.Trim());
            RefreshProfileSelection();
            MessageBox.Show("用户名称已更新；顶部选择器会显示新名称。");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void RefreshProfileSelection()
    {
        if (Window.GetWindow(this) is MainWindow window)
            window.RefreshProfileSelection();
    }
    private void ChangeAvatar()
    {
        var dialog = new OpenFileDialog { Filter = "头像图片|*.png;*.jpg;*.jpeg;*.webp;*.bmp" };
        if (dialog.ShowDialog() == true)
            CropAndSaveAvatar(dialog.FileName);
    }
    private void CropCurrentAvatar()
    {
        var current = session.Users.FirstOrDefault(user => InventoryDocument.IdEquals(user.Id, session.SelectedUserId));
        var path = current?.AvatarFile is { Length: > 0 } avatar
            ? Path.Combine(LocalLibraryRepository.DefaultDataRoot, "Avatars", Path.GetFileName(avatar))
            : null;
        if (path is not null && File.Exists(path))
        {
            CropAndSaveAvatar(path);
            return;
        }
        MessageBox.Show("当前用户还没有自定义头像。", "用户资料");
    }
    private void CropAndSaveAvatar(string sourcePath)
    {
        try
        {
            var crop = new AvatarCropWindow(sourcePath) { Owner = Window.GetWindow(this) };
            if (crop.ShowDialog() != true || crop.CroppedPath is not { } croppedPath)
                return;
            try
            {
                var current = session.Users.First(user => InventoryDocument.IdEquals(user.Id, session.SelectedUserId));
                session.SaveProfile(current.Name, croppedPath);
                RefreshProfileSelection();
                MessageBox.Show("头像已裁剪并保存到本机用户资料。", "用户资料");
            }
            finally
            {
                if (File.Exists(croppedPath))
                    File.Delete(croppedPath);
            }
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void UseDefaultAvatar()
    {
        try
        {
            var current = session.Users.First(user => InventoryDocument.IdEquals(user.Id, session.SelectedUserId));
            session.SaveProfile(current.Name, removeAvatar: true);
            RefreshProfileSelection();
            MessageBox.Show("已恢复默认头像。", "用户资料");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void OpenDataFolder()
    {
        try
        {
            var path = session.CurrentDataDirectory;
            var start = new System.Diagnostics.ProcessStartInfo("explorer.exe", path)
            {
                UseShellExecute = true
            };
            System.Diagnostics.Process.Start(start);
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void CreateProfile()
    {
        if (string.IsNullOrWhiteSpace(profileName.Text))
            return;
        try
        {
            session.CreateProfile(profileName.Text.Trim());
            RefreshProfileSelection();
            profileName.Clear();
            MessageBox.Show("已创建并切换到独立资料库。", "用户资料");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void ImportExcel()
    {
        var dialog = new OpenFileDialog { Filter = "Excel 工作簿|*.xlsx;*.xlsm", Title = "选择未加密的 .xlsx 或 .xlsm 工作簿" };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            var window = new ExcelImportWindow(session, dialog.FileName)
            {
                Owner = Window.GetWindow(this)
            };
            if (window.ShowDialog() == true)
                MessageBox.Show(session.Message, "Excel 导入完成");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void RunCleanup(string label, Func<int> action)
    {
        try
        {
            var count = action();
            MessageBox.Show($"已处理 {count} 项{label}。", "整理工具");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private async Task RefreshExchangeRatesAsync()
    {
        exchangeStatus.Text = "正在获取参考汇率…";
        await session.RefreshExchangeRatesAsync();
        exchangeStatus.Text = BuildExchangeStatus();
    }
    private string BuildExchangeStatus()
    {
        return session.ExchangeError.Length == 0
            ? session.ExchangeDescription
            : session.ExchangeDescription + "\n" + session.ExchangeError;
    }
    private void TrashAllGear()
    {
        if (!ConfirmTrashAllGear())
            return;
        try
        {
            MessageBox.Show($"已将 {session.TrashAllGear()} 件装备移入回收站。", "批量清理");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private bool ConfirmTrashAllGear()
    {
        var message = $"将“{session.CurrentUserName}”资料库中的全部装备移入回收站？此操作可在回收站恢复。";
        return MessageBox.Show(
            message,
            "确认批量清理",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning) == MessageBoxResult.Yes;
    }
    private void Backup()
    {
        var dialog = new SaveFileDialog
        {
            Filter = "资料库备份|*.zip",
            FileName = "户外装备库备份.zip"
        };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            session.Backup(dialog.FileName);
            MessageBox.Show("当前资料库备份已保存。", "备份");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private void RestoreZip()
    {
        var dialog = new OpenFileDialog { Filter = "资料库备份|*.zip" };
        if (dialog.ShowDialog() == true)
            RestoreFrom(dialog.FileName);
    }
    private void RestoreFolder()
    {
        var dialog = new OpenFolderDialog
        {
            Title = "选择旧版 .gearbackup 备份文件夹",
            Multiselect = false
        };
        if (dialog.ShowDialog(Window.GetWindow(this)) == true)
            RestoreFrom(dialog.FolderName);
    }
    private void RestoreFrom(string path)
    {
        if (!ConfirmRestore())
            return;
        try
        {
            session.RestoreBackup(path);
            MessageBox.Show("资料库恢复完成。", "恢复");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
    private bool ConfirmRestore()
    {
        const string message = "备份会合并到当前用户资料库：相同 ID 的记录会替换，其他记录保留。恢复前将自动生成当前资料库备份。继续吗？";
        return MessageBox.Show(
            message,
            "确认恢复",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning) == MessageBoxResult.Yes;
    }
    private void Import()
    {
        var dialog = new OpenFileDialog { Filter = "CSV/TSV 文件|*.csv;*.tsv;*.txt" };
        if (dialog.ShowDialog() != true)
            return;
        try
        {
            session.ImportCsv(File.ReadAllText(dialog.FileName));
            MessageBox.Show("导入完成");
        }
        catch (Exception error)
        {
            PageUi.Error(error);
        }
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
        catch (Exception error)
        {
            PageUi.Error(error);
        }
    }
}
