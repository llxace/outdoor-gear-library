using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using OutdoorGear.Core.Features.Meals.Business;
using OutdoorGear.Core.Features.Meals.Data;
using OutdoorGear.Core.Features.Meals.Domain;

namespace OutdoorGear.Wpf.Features.Meals.Presentation;

public sealed class FoodLabelScannerWindow : Window
{
    private readonly TextBox recognizedText = new() { AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MinHeight = 250 };
    private readonly TextBlock preview = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 10) };
    private readonly TextBlock fileName = new() { Text = "尚未选择包装照片", Margin = new Thickness(0, 8, 0, 8) };
    private readonly Button recognizeButton = new() { Content = "开始识别", Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 0, 8, 8) };
    private string? imagePath;
    public FoodLabelResult? Result { get; private set; }

    public FoodLabelScannerWindow()
    {
        Title = "识别食品包装"; Width = 650; Height = 620; MinWidth = 500; MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new DockPanel { Margin = new Thickness(22) };
        var header = new StackPanel();
        header.Children.Add(new TextBlock { Text = "本机离线识别", FontSize = 22, FontWeight = FontWeights.SemiBold });
        header.Children.Add(new TextBlock { Text = "选择包装照片，识别品名、净含量和营养表。照片与识别文字不会上传。识别结果需核对。", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 8) });
        var controls = new WrapPanel();
        controls.Children.Add(new Button { Content = "选择包装照片…", Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 0, 8, 8) });
        ((Button)controls.Children[0]).Click += (_, _) => SelectPhoto();
        recognizeButton.Click += async (_, _) => await RecognizeAsync(recognizeButton);
        controls.Children.Add(recognizeButton);
        var camera = new Button { Content = "摄像头拍照…", Padding = new Thickness(12, 7, 12, 7), Margin = new Thickness(0, 0, 8, 8) };
        camera.Click += (_, _) => CapturePhoto();
        controls.Children.Add(camera);
        header.Children.Add(controls); header.Children.Add(fileName); header.Children.Add(preview);
        DockPanel.SetDock(header, Dock.Top); root.Children.Add(header);
        root.Children.Add(recognizedText);
        recognizedText.TextChanged += (_, _) => UpdatePreview();
        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        var cancel = new Button { Content = "取消", Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(0, 0, 8, 0) };
        cancel.Click += (_, _) => DialogResult = false;
        var use = new Button { Content = "核对并填入草稿", Padding = new Thickness(14, 7, 14, 7) };
        use.Click += (_, _) => { Result = FoodLabelParser.Parse(recognizedText.Text); DialogResult = true; };
        footer.Children.Add(cancel); footer.Children.Add(use); DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        Content = root;
    }

    private void SelectPhoto()
    {
        var picker = new OpenFileDialog { Filter = "图片|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.tif;*.tiff" };
        if (picker.ShowDialog(this) != true) return;
        imagePath = picker.FileName;
        fileName.Text = System.IO.Path.GetFileName(imagePath);
    }

    private void CapturePhoto()
    {
        var camera = new CameraCaptureWindow { Owner = this };
        if (camera.ShowDialog() != true || camera.CapturedPath is null) return;
        imagePath = camera.CapturedPath;
        fileName.Text = "摄像头照片 · " + System.IO.Path.GetFileName(imagePath);
        _ = RecognizeAsync(recognizeButton);
    }

    private async Task RecognizeAsync(Button button)
    {
        if (imagePath is null) { MessageBox.Show(this, "请先选择包装照片。", "包装识别"); return; }
        button.IsEnabled = false;
        try
        {
            var modelDirectory = System.IO.Path.Combine(AppContext.BaseDirectory, "Resources", "Ocr", "tessdata");
            recognizedText.Text = await FoodTextRecognizer.RecognizeAsync(imagePath, modelDirectory);
            UpdatePreview();
        }
        catch (Exception error) { MessageBox.Show(this, error.Message, "包装识别", MessageBoxButton.OK, MessageBoxImage.Information); }
        finally { button.IsEnabled = true; }
    }

    private void UpdatePreview()
    {
        var parsed = FoodLabelParser.Parse(recognizedText.Text);
        preview.Text = $"品名：{Value(parsed.Name)}    净含量：{parsed.Grams?.ToString("0.##") ?? "未识别"} g    热量：{parsed.Calories?.ToString("0.##") ?? "需手动核对"} kcal\n{parsed.Message}";
    }

    private static string Value(string value) => string.IsNullOrWhiteSpace(value) ? "未识别" : value;
}
