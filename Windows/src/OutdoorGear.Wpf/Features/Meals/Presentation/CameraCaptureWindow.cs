using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using OpenCvSharp;
using OpenCvSharp.WpfExtensions;

namespace OutdoorGear.Wpf.Features.Meals.Presentation;

public sealed class CameraCaptureWindow : System.Windows.Window
{
    private readonly VideoCapture camera = new();
    private readonly Mat frame = new();
    private readonly Image preview = new() { Stretch = System.Windows.Media.Stretch.Uniform };
    private readonly TextBlock status = new() { Text = "正在连接摄像头…", Margin = new Thickness(0, 8, 0, 8) };
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(70) };
    public string? CapturedPath { get; private set; }

    public CameraCaptureWindow()
    {
        Title = "拍摄食品包装"; Width = 850; Height = 620; MinWidth = 560; MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new DockPanel { Margin = new Thickness(16) };
        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "取消", Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(0, 0, 8, 0) };
        cancel.Click += (_, _) => Close();
        var take = new Button { Content = "拍照并识别", Padding = new Thickness(14, 7, 14, 7) };
        take.Click += (_, _) => TakePhoto();
        footer.Children.Add(cancel); footer.Children.Add(take);
        var bottom = new StackPanel(); bottom.Children.Add(status); bottom.Children.Add(footer);
        DockPanel.SetDock(bottom, Dock.Bottom); root.Children.Add(bottom); root.Children.Add(preview);
        Content = root;
        Loaded += (_, _) => StartCamera();
        Closed += (_, _) => StopCamera();
        timer.Tick += (_, _) => UpdateFrame();
    }

    private void StartCamera()
    {
        try
        {
            if (!camera.Open(0, VideoCaptureAPIs.MSMF))
            {
                status.Text = "未找到可用摄像头。请检查 Windows 隐私设置中的桌面应用摄像头权限，或改用选择照片。";
                return;
            }
            camera.Set(VideoCaptureProperties.FrameWidth, 1280);
            camera.Set(VideoCaptureProperties.FrameHeight, 720);
            status.Text = "将包装品名与营养表对准画面后拍摄。";
            timer.Start();
        }
        catch (Exception error) { status.Text = "摄像头无法启动：" + error.Message; }
    }

    private void UpdateFrame()
    {
        try
        {
            if (!camera.IsOpened() || !camera.Read(frame) || frame.Empty()) return;
            BitmapSource bitmap = BitmapSourceConverter.ToBitmapSource(frame);
            if (bitmap.CanFreeze) bitmap.Freeze();
            preview.Source = bitmap;
        }
        catch (Exception error) { status.Text = "摄像头读取失败：" + error.Message; timer.Stop(); }
    }

    private void TakePhoto()
    {
        if (!camera.IsOpened() || frame.Empty()) { status.Text = "目前没有摄像头画面可拍摄。"; return; }
        try
        {
            var directory = Path.Combine(Path.GetTempPath(), "OutdoorGearCamera");
            Directory.CreateDirectory(directory);
            CapturedPath = Path.Combine(directory, $"food-{DateTime.Now:yyyyMMdd-HHmmss}.jpg");
            if (!Cv2.ImWrite(CapturedPath, frame)) throw new IOException("无法保存摄像头照片。");
            DialogResult = true;
        }
        catch (Exception error) { status.Text = "照片保存失败：" + error.Message; }
    }

    private void StopCamera()
    {
        timer.Stop();
        camera.Release();
        camera.Dispose();
        frame.Dispose();
    }
}
