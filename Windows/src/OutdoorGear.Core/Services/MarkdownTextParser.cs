using System.Text.RegularExpressions;

namespace OutdoorGear.Core.Services;

public enum MarkdownBlockKind { Paragraph, Heading, Bullet, Numbered, Quote }
public enum MarkdownSpanKind { Plain, Strong, Emphasis, Strikethrough, Code, Link }
public sealed record MarkdownSpan(string Text, MarkdownSpanKind Kind, string? Url = null);
public sealed record MarkdownLine(MarkdownBlockKind Kind, int Level, IReadOnlyList<MarkdownSpan> Spans);

public static partial class MarkdownTextParser
{
    [GeneratedRegex(@"\[(?<linkText>[^\]]+)\]\((?<url>https?://[^\s)]+)\)|(?<strong>\*\*|__)(?<strongText>.+?)\k<strong>|(?<strike>~~)(?<strikeText>.+?)\k<strike>|(?<code>`)(?<codeText>.+?)\k<code>|(?<italic>\*|_)(?<italicText>.+?)\k<italic>")]
    private static partial Regex InlinePattern();

    public static IReadOnlyList<MarkdownLine> Parse(string? markdown)
    {
        if (string.IsNullOrEmpty(markdown)) return [];
        return markdown.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n')
            .Split('\n').Select(ParseLine).ToArray();
    }

    private static MarkdownLine ParseLine(string value)
    {
        var content = value.TrimStart();
        var kind = MarkdownBlockKind.Paragraph;
        var level = 0;
        if (TryHeading(content, out var heading, out level)) { kind = MarkdownBlockKind.Heading; content = heading; }
        else if (TryPrefix(content, "- ", "* ", "+ ")) { kind = MarkdownBlockKind.Bullet; content = content[2..]; }
        else if (TryNumbered(content, out var numbered, out level)) { kind = MarkdownBlockKind.Numbered; content = numbered; }
        else if (content.StartsWith("> ", StringComparison.Ordinal)) { kind = MarkdownBlockKind.Quote; content = content[2..]; }
        return new MarkdownLine(kind, level, ParseSpans(content));
    }

    private static bool TryHeading(string value, out string content, out int level)
    {
        level = value.TakeWhile(character => character == '#').Count();
        var isHeading = level is > 0 and <= 6 && value.Length > level && value[level] == ' ';
        content = isHeading
            ? value[(level + 1)..].TrimEnd('#', ' ')
            : value;
        return isHeading;
    }

    private static bool TryPrefix(string value, params string[] prefixes) =>
        prefixes.Any(prefix => value.StartsWith(prefix, StringComparison.Ordinal));

    private static bool TryNumbered(string value, out string content, out int number)
    {
        var match = NumberedPrefixPattern().Match(value);
        content = match.Success ? value[match.Length..] : value;
        if (!match.Success) { number = 0; return false; }
        int.TryParse(match.Groups["number"].Value, System.Globalization.NumberStyles.None,
            System.Globalization.CultureInfo.InvariantCulture, out number);
        return true;
    }

    [GeneratedRegex(@"^(?<number>\d+)\. ")]
    private static partial Regex NumberedPrefixPattern();

    private static IReadOnlyList<MarkdownSpan> ParseSpans(string value)
    {
        var spans = new List<MarkdownSpan>();
        var offset = 0;
        foreach (Match match in InlinePattern().Matches(value))
        {
            if (match.Index > offset) spans.Add(new MarkdownSpan(value[offset..match.Index], MarkdownSpanKind.Plain));
            spans.Add(ToSpan(match));
            offset = match.Index + match.Length;
        }
        if (offset < value.Length) spans.Add(new MarkdownSpan(value[offset..], MarkdownSpanKind.Plain));
        if (spans.Count == 0) spans.Add(new MarkdownSpan(value, MarkdownSpanKind.Plain));
        return spans;
    }

    private static MarkdownSpan ToSpan(Match match)
    {
        if (match.Groups["linkText"].Success) return new MarkdownSpan(match.Groups["linkText"].Value, MarkdownSpanKind.Link, match.Groups["url"].Value);
        if (match.Groups["strongText"].Success) return new MarkdownSpan(match.Groups["strongText"].Value, MarkdownSpanKind.Strong);
        if (match.Groups["strikeText"].Success) return new MarkdownSpan(match.Groups["strikeText"].Value, MarkdownSpanKind.Strikethrough);
        if (match.Groups["codeText"].Success) return new MarkdownSpan(match.Groups["codeText"].Value, MarkdownSpanKind.Code);
        return new MarkdownSpan(match.Groups["italicText"].Value, MarkdownSpanKind.Emphasis);
    }
}
