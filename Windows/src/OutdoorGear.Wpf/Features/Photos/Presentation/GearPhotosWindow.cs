using System.Diagnostics;
using System.IO;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;

namespace OutdoorGear.Wpf.Features.Photos.Presentation;

public sealed class GearPhotosWindow : Window
{
    private readonly LibrarySession session;
    private readonly GearRecord gear;

    public GearPhotosWindow(LibrarySession session, GearRecord gear)
    {
        this.session = session;
        this.gear = gear;
        Title = $"{gear.Name} · 照片与附件";
        Width = 820;
        Height = 680;
        MinWidth = 600;
        MinHeight = 440;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        Content = BuildContent();
    }

    private UIElement BuildContent()
    {
        var content = new StackPanel { Margin = new Thickness(22) };
        content.Children.Add(new TextBlock
        {
            Text = "主照片",
            FontSize = 20,
            FontWeight = FontWeights.SemiBold
        });
        content.Children.Add(BuildPrimaryPhoto());
        AddGallery(content);
        return new ScrollViewer
        {
            Content = content,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
    }

    private Border BuildPrimaryPhoto()
    {
        var photoPanel = new Border
        {
            Height = 250,
            Margin = new Thickness(0, 10, 0, 20),
            Background = Brushes.DimGray,
            CornerRadius = new CornerRadius(8)
        };
        var photo = new Image { Stretch = Stretch.Uniform, Margin = new Thickness(8) };
        LoadPrimaryPhoto(photoPanel, photo);
        if (photoPanel.Child is null)
            photoPanel.Child = photo.Source is null ? EmptyPhotoLabel() : photo;
        return photoPanel;
    }

    private void LoadPrimaryPhoto(Border photoPanel, Image photo)
    {
        if (string.IsNullOrWhiteSpace(gear.Photo))
            return;
        try
        {
            var path = GearAssetService.AssetPath(
                session.CurrentDataDirectory, "Photos", gear.Photo);
            photo.Source = LoadImage(path);
        }
        catch (Exception error)
        {
            photoPanel.Child = new TextBlock
            {
                Text = "主照片无法预览：" + error.Message,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(12),
                VerticalAlignment = VerticalAlignment.Center
            };
        }
    }

    private static TextBlock EmptyPhotoLabel() => new()
    {
        Text = "尚未设置主照片",
        Foreground = Brushes.White,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center
    };

    private void AddGallery(StackPanel content)
    {
        var attachments = gear.Extras.Node["attachments"] as JsonArray ?? new JsonArray();
        content.Children.Add(new TextBlock { Text = $"照片与附件（{attachments.Count}）", FontSize = 18, FontWeight = FontWeights.SemiBold });

        var gallery = new WrapPanel();
        foreach (var item in attachments.OfType<JsonObject>()) gallery.Children.Add(AttachmentCard(item));
        if (attachments.Count == 0) gallery.Children.Add(new TextBlock { Text = "暂无附件", Margin = new Thickness(4, 12, 4, 4), Foreground = Brushes.Gray });
        content.Children.Add(gallery);
    }

    private Border AttachmentCard(JsonObject attachment)
    {
        var fileName = attachment["file"]?.ToString() ?? "";
        var isImage = InventoryDocument.Bool(attachment["isImage"]);
        var card = new Border { Width = 220, Margin = new Thickness(0, 10, 12, 0), Padding = new Thickness(10), Background = Brushes.DimGray, CornerRadius = new CornerRadius(8) };
        var layout = new StackPanel();
        var preview = new Border { Height = 130, Background = Brushes.White, CornerRadius = new CornerRadius(5) };
        if (isImage)
        {
            try { preview.Child = new Image { Source = LoadImage(GearAssetService.AttachmentPath(session.CurrentDataDirectory, attachment)), Stretch = Stretch.Uniform, Margin = new Thickness(4) }; }
            catch (Exception error) { preview.Child = new TextBlock { Text = "无法预览：" + error.Message, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(8), VerticalAlignment = VerticalAlignment.Center }; }
        }
        else preview.Child = new TextBlock { Text = "文件附件", HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Foreground = Brushes.Gray };
        layout.Children.Add(preview);
        layout.Children.Add(new TextBlock { Text = attachment["title"]?.ToString() ?? fileName, Margin = new Thickness(0, 8, 0, 5), TextTrimming = TextTrimming.CharacterEllipsis, ToolTip = fileName });
        var buttons = new WrapPanel();
        buttons.Children.Add(CreateButton("打开", (_, _) => Open(attachment)));
        buttons.Children.Add(CreateButton("导出", (_, _) => Export(attachment)));
        if (isImage) buttons.Children.Add(CreateButton("设为主照片", (_, _) => SetPrimary(attachment)));
        if (attachment["title"]?.ToString() == "修图原图")
            buttons.Children.Add(CreateButton("恢复原图", (_, _) => RestoreOriginal()));
        layout.Children.Add(buttons);
        card.Child = layout;
        return card;
    }

    private void Open(JsonObject attachment)
    {
        try { Process.Start(new ProcessStartInfo(GearAssetService.AttachmentPath(session.CurrentDataDirectory, attachment)) { UseShellExecute = true }); }
        catch (Exception error) { ShowError(error); }
    }

    private void Export(JsonObject attachment)
    {
        try
        {
            var source = GearAssetService.AttachmentPath(session.CurrentDataDirectory, attachment);
            if (!File.Exists(source)) throw new FileNotFoundException("找不到这份附件。", source);
            var dialog = new SaveFileDialog { FileName = Path.GetFileName(attachment["title"]?.ToString() ?? source), Title = "导出装备附件" };
            if (dialog.ShowDialog(this) == true) File.Copy(source, dialog.FileName, overwrite: true);
        }
        catch (Exception error) { ShowError(error); }
    }

    private void SetPrimary(JsonObject attachment)
    {
        try
        {
            session.SetPrimaryPhotoFromAttachment(gear, attachment);
            DialogResult = true;
        }
        catch (Exception error) { ShowError(error); }
    }

    private void RestoreOriginal()
    {
        try
        {
            session.RestoreOriginalPhoto(gear);
            DialogResult = true;
        }
        catch (Exception error) { ShowError(error); }
    }

    private static Button CreateButton(string text, RoutedEventHandler action)
    {
        var button = new Button { Content = text, Padding = new Thickness(12, 7, 12, 7) };
        button.Margin = new Thickness(0, 0, 8, 8);
        button.Click += action;
        return button;
    }

    private void ShowError(Exception error) =>
        MessageBox.Show(error.Message, "户外装备库", MessageBoxButton.OK, MessageBoxImage.Information);

    private static BitmapImage LoadImage(string path)
    {
        using var stream = File.OpenRead(path);
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.DecodePixelWidth = 420;
        image.StreamSource = stream;
        image.EndInit();
        image.Freeze();
        return image;
    }

}
