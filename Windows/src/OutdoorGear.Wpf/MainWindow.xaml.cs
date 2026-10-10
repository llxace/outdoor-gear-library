using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.IO;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.Features.Dashboard.Presentation;
using OutdoorGear.Wpf.Features.Equipment.Presentation;
using OutdoorGear.Wpf.Features.History.Presentation;
using OutdoorGear.Wpf.Features.Packing.Presentation;
using OutdoorGear.Wpf.Features.Settings.Presentation;
using OutdoorGear.Wpf.ViewModels;


namespace OutdoorGear.Wpf;

public partial class MainWindow : Window
{
    private LibrarySession session = null!;
    private bool updatingProfile;

    public MainWindow()
    {
        InitializeComponent();
        try { session = new LibrarySession(); }
        catch (Exception error)
        {
            MessageBox.Show("装备库未能安全读取，原文件保持不变。\n\n" + error.Message, "读取失败", MessageBoxButton.OK, MessageBoxImage.Error);
            Close(); return;
        }
        ProfileSelector.ItemsSource = session.Users;
        ProfileSelector.SelectedValuePath = "Id";
        ProfileSelector.SelectedValue = session.SelectedUserId;
        UpdateProfileDisplay();
        ((App)Application.Current).ApplyAppearance(session.Inventory.Settings["appearance"]?.ToString() ?? "跟随系统");
        Navigation.SelectedIndex = 0;
        SetPage("打包");
    }

    private void Navigation_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (Navigation.SelectedItem is ListBoxItem item && item.Tag is string page) SetPage(page);
    }

    private void SetPage(string page)
    {
        if (PageTitle is null || session is null) return;
        PageTitle.Text = page;
        PageHost.Content = page switch
        {
            "打包" => new PackingPage(session),
            "仪表盘" => new OutdoorGear.Wpf.Features.Dashboard.Presentation.DashboardPage(session, SetPage),
            "个人专栏" => new HistoryPage(session),
            "装备库" => new GearLibraryPage(session),
            "设置" => new SettingsPage(session),
            "回收站" => new RecyclePage(session),
            _ => new PackingPage(session)
        };
        StatusText.Text = session.Message;
    }

    private void ProfileSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (updatingProfile || ProfileSelector.SelectedValue is not string id || session is null) return;
        if (!session.SelectUser(id))
        {
            updatingProfile = true; ProfileSelector.SelectedValue = session.SelectedUserId; updatingProfile = false;
        }
        UpdateProfileDisplay();
        SetPage(PageTitle.Text);
    }

    public void UpdateProfileDisplay()
    {
        CurrentUserName.Text = session.CurrentUserName;
        var user = session.Users.FirstOrDefault(record => OutdoorGear.Core.Models.InventoryDocument.IdEquals(record.Id, session.SelectedUserId));
        var path = user?.AvatarFile is { Length: > 0 } avatar ? Path.Combine(LocalLibraryRepository.DefaultDataRoot, "Avatars", Path.GetFileName(avatar)) : null;
        try
        {
            if (path is not null && File.Exists(path)) { var image = new BitmapImage(new Uri(path)); image.Freeze(); ProfileAvatar.Fill = new ImageBrush(image); }
            else SetDefaultProfileAvatar();
        }
        catch { SetDefaultProfileAvatar(); }
    }

    private void SetDefaultProfileAvatar() =>
        ProfileAvatar.SetResourceReference(System.Windows.Shapes.Shape.FillProperty, "AccentBrush");

    public void RefreshProfileSelection()
    {
        updatingProfile = true;
        ProfileSelector.ItemsSource = session.Users;
        ProfileSelector.SelectedValue = session.SelectedUserId;
        updatingProfile = false;
        UpdateProfileDisplay();
        SetPage(PageTitle.Text);
    }

    private void ProfileMenu_Click(object sender, RoutedEventArgs e)
    {
        Navigation.SelectedIndex = 4;
    }

    private void Borrow_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new BorrowGearWindow(session) { Owner = this };
        dialog.ShowDialog();
        SetPage(PageTitle.Text);
    }
}
