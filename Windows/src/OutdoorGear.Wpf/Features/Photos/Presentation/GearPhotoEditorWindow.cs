using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using OutdoorGear.Core.Features.Photos.Data;

namespace OutdoorGear.Wpf.Features.Photos.Presentation;

internal sealed class GearPhotoEditorWindow : Window
{
    private readonly string sourcePath;
    private readonly string dataDirectory;
    private readonly Image preview = new() { Stretch = System.Windows.Media.Stretch.Uniform, MaxHeight = 540 };
    private readonly CheckBox whiteBackground = new() { Content = "白底抠图（本地模型，首次加载较慢）", Margin = new Thickness(0, 8, 0, 0) };
    private readonly CheckBox softShadow = new() { Content = "添加柔和阴影", IsChecked = true, Margin = new Thickness(0, 4, 0, 8) };
    private readonly TextBlock status = new() { Text = "选择处理选项后生成预览。原图会保留。", Margin = new Thickness(0, 6, 0, 8), TextWrapping = TextWrapping.Wrap };
    private readonly Button apply = new() { Content = "应用处理结果", IsEnabled = false, Padding = new Thickness(14, 7, 14, 7) };
    private bool busy;
    private string? renderedFile;
    private bool lastWhite;
    private bool lastShadow;

    public string? OutputFile { get; private set; }

    public GearPhotoEditorWindow(string sourcePath, string dataDirectory)
    {
        this.sourcePath = sourcePath;
        this.dataDirectory = dataDirectory;
        Title = "照片白底与规格化";
        Width = 760;
        Height = 820;
        MinWidth = 560;
        MinHeight = 620;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = BuildContent();
        LoadPreview(sourcePath);
        BindEvents();
    }

    private UIElement BuildContent()
    {
        var root = new DockPanel { Margin = new Thickness(16) };
        var controls = BuildControls();
        DockPanel.SetDock(controls, Dock.Bottom);
        root.Children.Add(controls);
        root.Children.Add(BuildPreviewPanel());
        return root;
    }

    private StackPanel BuildControls()
    {
        var controls = new StackPanel();
        controls.Children.Add(whiteBackground);
        controls.Children.Add(softShadow);
        controls.Children.Add(status);
        controls.Children.Add(BuildActionButtons());
        return controls;
    }

    private StackPanel BuildActionButtons()
    {
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        var previewButton = new Button { Content = "生成预览", Padding = new Thickness(14, 7, 14, 7) };
        var cancelButton = new Button { Content = "取消", Padding = new Thickness(14, 7, 14, 7) };
        previewButton.Margin = new Thickness(0, 0, 8, 0);
        cancelButton.Margin = new Thickness(0, 0, 8, 0);
        previewButton.Click += async (_, _) => await RenderAsync();
        cancelButton.Click += (_, _) => Cancel();
        apply.Click += async (_, _) => await ApplyAsync();
        buttons.Children.Add(previewButton);
        buttons.Children.Add(apply);
        buttons.Children.Add(cancelButton);
        return buttons;
    }

    private UIElement BuildPreviewPanel()
    {
        var border = new Border
        {
            BorderThickness = new Thickness(1),
            BorderBrush = System.Windows.Media.Brushes.Gray,
            Background = System.Windows.Media.Brushes.White,
            Padding = new Thickness(8),
            Child = preview
        };
        return new ScrollViewer
        {
            Content = border,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
    }

    private void BindEvents()
    {
        Closing += (_, e) => PreventCloseDuringProcessing(e);
        Closed += (_, _) => RemoveAbandonedPreview();
        whiteBackground.Checked += InvalidatePreview;
        whiteBackground.Unchecked += InvalidatePreview;
        softShadow.Checked += InvalidatePreview;
        softShadow.Unchecked += InvalidatePreview;
    }

    private void Cancel()
    {
        if (!busy)
            DialogResult = false;
    }

    private void PreventCloseDuringProcessing(System.ComponentModel.CancelEventArgs args)
    {
        if (!busy)
            return;
        args.Cancel = true;
        status.Text = "照片仍在处理，请稍候。";
    }

    private void RemoveAbandonedPreview()
    {
        if (DialogResult == true || renderedFile is not { } abandoned)
            return;
        try { File.Delete(abandoned); } catch { }
    }

    private async Task ApplyAsync()
    {
        if (!MatchesCurrentOptions() || renderedFile is null)
            await RenderAsync();
        if (renderedFile is not { } file || !File.Exists(file))
            return;
        OutputFile = file;
        DialogResult = true;
    }

    private void InvalidatePreview(object sender, RoutedEventArgs e)
    {
        if (renderedFile is { } old && old != OutputFile) try { File.Delete(old); } catch { }
        renderedFile = null; apply.IsEnabled = !busy;
        status.Text = "处理选项已更改，请重新生成预览。";
    }

    private bool MatchesCurrentOptions() => renderedFile is not null && lastWhite == (whiteBackground.IsChecked == true) && lastShadow == (softShadow.IsChecked == true);

    private async Task RenderAsync()
    {
        if (busy) return;
        busy = true; apply.IsEnabled = false; status.Text = "正在本机处理照片…";
        var white = whiteBackground.IsChecked == true; var shadow = softShadow.IsChecked == true;
        var destination = Path.Combine(dataDirectory, "Photos", "PHOTO-" + Guid.NewGuid().ToString("N").ToUpperInvariant() + ".png");
        try
        {
            var model = Path.Combine(AppContext.BaseDirectory, "Resources", "Models", "u2net.onnx");
            await Task.Run(() => new ProductPhotoProcessor().Process(sourcePath, destination, model, white, shadow));
            if (renderedFile is { } old && old != OutputFile) try { File.Delete(old); } catch { }
            renderedFile = destination; lastWhite = white; lastShadow = shadow;
            LoadPreview(destination); status.Text = "预览已生成。确认后应用；原始照片会作为附件保留。";
            apply.IsEnabled = true;
        }
        catch (Exception error)
        {
            try { if (File.Exists(destination)) File.Delete(destination); } catch { }
            status.Text = "照片处理失败：" + error.Message; apply.IsEnabled = false;
        }
        finally { busy = false; }
    }

    private void LoadPreview(string path)
    {
        using var stream = File.OpenRead(path);
        var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze();
        preview.Source = bitmap;
    }
}
