using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using Microsoft.Win32;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;
using OutdoorGear.Wpf.Features.Photos.Presentation;

namespace OutdoorGear.Wpf.Features.Shared.Presentation;

internal static class PageUi
{
    public static StackPanel Root(string title, string subtitle = "")
    {
        var root = new StackPanel { Margin = new Thickness(2, 8, 2, 2) };
        root.Children.Add(new TextBlock { Text = title, FontSize = 24, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 4) });
        if (subtitle.Length > 0) root.Children.Add(new TextBlock { Text = subtitle, Foreground = System.Windows.Media.Brushes.Gray, Margin = new Thickness(0, 0, 0, 12) });
        return root;
    }
    public static Button Button(string text, RoutedEventHandler handler) { var b = new Button { Content = text, Margin = new Thickness(0, 0, 8, 8), Padding = new Thickness(12, 7, 12, 7) }; b.Click += handler; return b; }
    public static void Error(Exception error) => MessageBox.Show(error.Message, "户外装备库", MessageBoxButton.OK, MessageBoxImage.Information);
}
