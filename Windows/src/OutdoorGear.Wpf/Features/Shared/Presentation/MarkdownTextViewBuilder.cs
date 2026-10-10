using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using OutdoorGear.Core.Services;

namespace OutdoorGear.Wpf.Features.Shared.Presentation;

internal static class MarkdownTextViewBuilder
{
    public static StackPanel Build(string? markdown)
    {
        var panel = new StackPanel();
        foreach (var line in MarkdownTextParser.Parse(markdown)) panel.Children.Add(BuildLine(line));
        return panel;
    }

    private static TextBlock BuildLine(MarkdownLine line)
    {
        var text = new TextBlock { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 5) };
        text.FontSize = HeadingSize(line);
        if (line.Kind is MarkdownBlockKind.Heading) text.FontWeight = FontWeights.SemiBold;
        if (line.Kind is MarkdownBlockKind.Quote) text.Foreground = Brushes.Gray;
        AddBlockPrefix(text, line);
        foreach (var span in line.Spans) AddSpan(text, span);
        return text;
    }

    private static double HeadingSize(MarkdownLine line) => line.Kind switch
    {
        MarkdownBlockKind.Heading when line.Level <= 2 => 18,
        MarkdownBlockKind.Heading => 16,
        _ => 14
    };

    private static void AddBlockPrefix(TextBlock text, MarkdownLine line)
    {
        var prefix = line.Kind switch
        {
            MarkdownBlockKind.Bullet => "•  ",
            MarkdownBlockKind.Numbered => $"{line.Level}.  ",
            MarkdownBlockKind.Quote => "│  ",
            _ => ""
        };
        if (prefix.Length > 0) text.Inlines.Add(new Run(prefix));
    }

    private static void AddSpan(TextBlock text, MarkdownSpan span)
    {
        if (span.Kind is MarkdownSpanKind.Link && Uri.TryCreate(span.Url, UriKind.Absolute, out var uri))
        {
            text.Inlines.Add(BuildLink(span.Text, uri));
            return;
        }
        text.Inlines.Add(BuildRun(span));
    }

    private static Hyperlink BuildLink(string content, Uri uri)
    {
        var link = new Hyperlink(new Run(content)) { NavigateUri = uri };
        link.Click += (_, _) => OpenLink(uri);
        return link;
    }

    private static void OpenLink(Uri uri)
    {
        try { Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true }); }
        catch (Exception error) { PageUi.Error(error); }
    }

    private static Run BuildRun(MarkdownSpan span)
    {
        var run = new Run(span.Text);
        if (span.Kind is MarkdownSpanKind.Strong) run.FontWeight = FontWeights.Bold;
        if (span.Kind is MarkdownSpanKind.Emphasis) run.FontStyle = FontStyles.Italic;
        if (span.Kind is MarkdownSpanKind.Strikethrough) run.TextDecorations = TextDecorations.Strikethrough;
        if (span.Kind is MarkdownSpanKind.Code)
        {
            run.FontFamily = new FontFamily("Consolas");
            run.Background = Brushes.Gainsboro;
        }
        return run;
    }
}
