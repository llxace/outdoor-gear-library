using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;

namespace OutdoorGear.Wpf.Features.Equipment.Presentation;

internal sealed class GearCategoryIconConverter : IValueConverter
{
    public static GearCategoryIconConverter Instance { get; } = new();

    private static readonly IReadOnlyDictionary<string, Geometry> Icons = new Dictionary<string, Geometry>
    {
        ["default"] = Parse("M4,4 H13 V13 H4 Z M19,4 H28 V13 H19 Z M4,19 H13 V28 H4 Z M19,19 H28 V28 H19 Z"),
        ["▦"] = Parse("M4,4 H13 V13 H4 Z M19,4 H28 V13 H19 Z M4,19 H13 V28 H4 Z M19,19 H28 V28 H19 Z"),
        ["▣"] = Parse("M12,7 C12,4 14,2 16,2 C18,2 20,4 20,7 M10,8 H22 C25,8 27,10 27,13 V26 C27,28 25,30 23,30 H9 C7,30 5,28 5,26 V13 C5,10 7,8 10,8 Z M9,17 H23 V24 H9 Z M5,13 L2,16 V23 M27,13 L30,16 V23"),
        ["⌂"] = Parse("M3,28 L14,5 C15,3 17,3 18,5 L29,28 Z M16,5 V28 M16,17 L25,28"),
        ["♟"] = Parse("M11,4 L14,2 H18 L21,4 L29,9 L25,16 L21,14 V29 H11 V14 L7,16 L3,9 Z M11,9 L7,12 M21,9 L25,12"),
        ["◒"] = Parse("M4,22 C7,21 9,19 10,16 L12,8 H17 L20,17 C21,20 23,21 27,22 L30,24 V27 C30,29 28,30 26,30 H6 C3,30 2,28 3,25 Z M5,26 H29 M20,20 L23,22"),
        ["♨"] = Parse("M6,3 V12 M10,3 V12 M14,3 V12 M6,12 C6,15 14,15 14,12 M10,15 V30 M24,3 C20,8 20,14 24,16 V30 M24,3 V16"),
        ["☼"] = Parse("M10,4 H22 L24,10 H8 Z M11,10 V26 C11,29 21,29 21,26 V10 M11,17 H21 M13,4 V2 H19 V4"),
        ["✚"] = Parse("M5,12 H27 V29 H5 Z M11,12 V7 H21 V12 M13,18 H19 V21 H22 V25 H19 V28 H13 V25 H10 V21 H13 Z"),
        ["✧"] = Parse("M6,17 C9,18 11,17 14,16 L20,14 C22,13 24,15 22,17 L17,20 L23,18 C26,17 28,20 25,22 L17,27 C14,29 10,29 7,27 L3,24 Z M8,12 L6,9 M14,10 L13,7 M20,10 L22,7 M26,12 L29,10"),
        ["⚠"] = Parse("M16,3 L30,28 H2 Z M16,11 V19 M16,24 V25")
    };

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not string glyph)
            return Icons["default"];
        return Icons.TryGetValue(glyph, out var icon) ? icon : Icons["default"];
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
        throw new NotSupportedException();

    private static Geometry Parse(string data)
    {
        var geometry = Geometry.Parse(data);
        geometry.Freeze();
        return geometry;
    }
}
