using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Features.Dashboard.Business;

public enum EquipmentStatisticMode
{
    CategoryQuantity,
    BrandQuantity,
    CategoryWeight,
    CategoryCost,
    BrandCost
}

public sealed record EquipmentDistribution(string Name, double Value);

public static class EquipmentStatistic
{
    public static IReadOnlyList<EquipmentDistribution> Calculate(
        IEnumerable<GearRecord> equipment,
        EquipmentStatisticMode mode)
    {
        var groups = new Dictionary<string, double>(StringComparer.CurrentCultureIgnoreCase);
        foreach (var item in equipment.Where(item => !item.Trashed && !item.IsLocation))
            AddEquipment(groups, item, mode);
        return groups
            .Select(pair => new EquipmentDistribution(pair.Key, pair.Value))
            .OrderByDescending(group => group.Value)
            .ThenBy(group => group.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    public static bool IsWeight(EquipmentStatisticMode mode) =>
        mode == EquipmentStatisticMode.CategoryWeight;

    public static bool IsCost(EquipmentStatisticMode mode) =>
        mode is EquipmentStatisticMode.CategoryCost or EquipmentStatisticMode.BrandCost;

    private static void AddEquipment(
        IDictionary<string, double> groups,
        GearRecord item,
        EquipmentStatisticMode mode)
    {
        var label = UsesBrand(mode) ? item.Brand : item.Category;
        var name = string.IsNullOrWhiteSpace(label) ? "未填写" : label.Trim();
        groups.TryGetValue(name, out var current);
        groups[name] = current + ValueFor(item, mode);
    }

    private static bool UsesBrand(EquipmentStatisticMode mode) =>
        mode is EquipmentStatisticMode.BrandQuantity or EquipmentStatisticMode.BrandCost;

    private static double ValueFor(GearRecord item, EquipmentStatisticMode mode)
    {
        if (IsWeight(mode))
            return item.Weight * item.Quantity / 1000;
        return IsCost(mode) ? item.PurchasePrice : item.Quantity;
    }
}
