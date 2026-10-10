using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using OutdoorGear.Core.Features.Profiles.Business;

namespace OutdoorGear.Wpf.Features.Profiles.Presentation;

public sealed class AvatarCropWindow : Window
{
    private const double ViewportSize = 320;
    private readonly string sourcePath;
    private readonly BitmapImage source;
    private readonly Canvas viewport = new() { Width = ViewportSize, Height = ViewportSize, ClipToBounds = true };
    private readonly Image preview = new() { Stretch = Stretch.Fill, IsHitTestVisible = false };
    private readonly Slider zoom = new() { Minimum = 1, Maximum = 5, Value = 1, TickFrequency = .1, IsSnapToTickEnabled = false };
    private Point dragOrigin;
    private Vector offset;
    private Vector startingOffset;
    private bool dragging;

    public string? CroppedPath { get; private set; }

    public AvatarCropWindow(string imagePath)
    {
        sourcePath = Path.GetFullPath(imagePath); source = LoadSource(sourcePath);
        Title = "裁剪头像"; Width = 480; Height = 510; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildLayout();
        viewport.Children.Add(preview);
        viewport.MouseLeftButtonDown += BeginDrag;
        viewport.MouseMove += Drag;
        viewport.MouseLeftButtonUp += EndDrag;
        zoom.ValueChanged += (_, _) => UpdatePreview();
        UpdatePreview();
    }

    private static BitmapImage LoadSource(string path)
    {
        var image = new BitmapImage();
        image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad; image.DecodePixelWidth = 2048; image.UriSource = new Uri(Path.GetFullPath(path)); image.EndInit(); image.Freeze();
        return image;
    }

    private UIElement BuildLayout()
    {
        var root = new StackPanel { Margin = new Thickness(22), HorizontalAlignment = HorizontalAlignment.Center };
        root.Children.Add(new TextBlock { Text = "拖动图片调整位置，缩放滑块调整大小。圆圈内区域将保存为正方形头像。", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 16) });
        viewport.Clip = new EllipseGeometry(new Rect(0, 0, ViewportSize, ViewportSize));
        root.Children.Add(new Border { Width = ViewportSize, Height = ViewportSize, CornerRadius = new CornerRadius(ViewportSize / 2), BorderThickness = new Thickness(2), BorderBrush = SystemColors.ControlDarkBrush, Child = viewport });
        root.Children.Add(new TextBlock { Text = "缩放", Margin = new Thickness(0, 16, 0, 4) }); root.Children.Add(zoom);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) };
        actions.Children.Add(new Button { Content = "重置", Padding = new Thickness(14, 6, 14, 6), Margin = new Thickness(0, 0, 8, 0) });
        ((Button)actions.Children[0]).Click += (_, _) => { zoom.Value = 1; offset = new Vector(0, 0); UpdatePreview(); };
        var cancel = new Button { Content = "取消", Padding = new Thickness(14, 6, 14, 6), Margin = new Thickness(0, 0, 8, 0) }; cancel.Click += (_, _) => DialogResult = false;
        var save = new Button { Content = "使用裁剪结果", Padding = new Thickness(14, 6, 14, 6), IsDefault = true }; save.Click += (_, _) => SaveCrop();
        actions.Children.Add(cancel); actions.Children.Add(save); root.Children.Add(actions);
        return root;
    }

    private double Scale() => Math.Max(ViewportSize / source.PixelWidth, ViewportSize / source.PixelHeight) * zoom.Value;

    private void UpdatePreview()
    {
        var scale = Scale();
        offset = ClampOffset(offset, scale);
        preview.Source = source; preview.Width = source.PixelWidth * scale; preview.Height = source.PixelHeight * scale;
        Canvas.SetLeft(preview, (ViewportSize - preview.Width) / 2 + offset.X);
        Canvas.SetTop(preview, (ViewportSize - preview.Height) / 2 + offset.Y);
    }

    private Vector ClampOffset(Vector value, double scale)
    {
        var maxX = Math.Max(0, (source.PixelWidth * scale - ViewportSize) / 2);
        var maxY = Math.Max(0, (source.PixelHeight * scale - ViewportSize) / 2);
        return new Vector(Math.Clamp(value.X, -maxX, maxX), Math.Clamp(value.Y, -maxY, maxY));
    }

    private void BeginDrag(object sender, MouseButtonEventArgs e) { dragging = true; dragOrigin = e.GetPosition(viewport); startingOffset = offset; viewport.CaptureMouse(); }
    private void Drag(object sender, MouseEventArgs e) { if (!dragging) return; var delta = e.GetPosition(viewport) - dragOrigin; offset = ClampOffset(startingOffset + delta, Scale()); UpdatePreview(); }
    private void EndDrag(object sender, MouseButtonEventArgs e) { dragging = false; viewport.ReleaseMouseCapture(); }

    private void SaveCrop()
    {
        CroppedPath = Path.Combine(Path.GetTempPath(), "OutdoorGearAvatar-" + Guid.NewGuid().ToString("N") + ".png");
        try { AvatarCropRenderer.Render(sourcePath, CroppedPath, zoom.Value, offset.X, offset.Y); DialogResult = true; }
        catch (Exception error) { if (File.Exists(CroppedPath)) File.Delete(CroppedPath); CroppedPath = null; MessageBox.Show(error.Message, "头像裁剪失败", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

}
