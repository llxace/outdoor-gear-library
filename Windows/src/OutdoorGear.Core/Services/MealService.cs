using System.Globalization;
using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public sealed record MealSummary(double FoodWeightGrams, double TotalWeightGrams, double Calories, double TotalCost, double WaterLiters, int FoodCount);
public sealed record MealRecommendationOptions(int Days, int People, bool Heavy, bool CanHeat, bool HasResupply, int CarryDays, int StartDay, double DailyCalories, bool Reserve);

public static class MealService
{
    public static MealSummary Summarize(InventoryDocument inventory)
    {
        var plan = inventory.MealPlan; var foods = InventoryDocument.EnsureArray(plan, "foods").OfType<JsonObject>().ToList();
        var foodWeight = foods.Sum(FoodWeight); var water = InventoryDocument.Number(plan["waterLiters"]);
        return new MealSummary(foodWeight, foodWeight + water * 1000, foods.Sum(FoodEnergy), foods.Sum(FoodCost), water, foods.Count);
    }

    public static void Configure(InventoryDocument inventory, DateTime departureDate, int days, int people, double dailyGoal, double waterLiters)
    {
        if (days is < 1 or > 60 || people is < 1 or > 100 || !double.IsFinite(dailyGoal) || dailyGoal < 0 || !double.IsFinite(waterLiters) || waterLiters < 0)
            throw new InvalidDataException("天数、人数、热量目标或携水量无效。");
        var foods = InventoryDocument.EnsureArray(inventory.MealPlan, "foods");
        if (foods.OfType<JsonObject>().Any(item => InventoryDocument.Int(item["day"], 1) > days)) throw new InvalidOperationException("计划中还有较晚日期的食物，请先移到现有日期或删除，再减少行程天数。");
        inventory.MealPlan["startDate"] = ToSwiftDate(departureDate);
        inventory.MealPlan["days"] = days; inventory.MealPlan["people"] = people;
        inventory.MealPlan["dailyGoal"] = dailyGoal; inventory.MealPlan["waterLiters"] = waterLiters;
    }

    public static string AddOrUpdateFood(InventoryDocument inventory, JsonObject food)
    {
        var name = food["name"]?.ToString()?.Trim() ?? "";
        var day = InventoryDocument.Int(food["day"], 1); var meal = food["meal"]?.ToString() ?? "行进零食"; var preparation = food["preparation"]?.ToString() ?? "即食";
        var planDays = InventoryDocument.Int(inventory.MealPlan["days"], 1);
        if (name.Length == 0 || day < 1 || day > planDays || !Meals.Contains(meal) || !Preparations.Contains(preparation)) throw new InvalidDataException("食物名称、日期、餐次或准备方式无效。");
        foreach (var key in new[] { "quantity", "grams", "calories", "price" })
        {
            var value = InventoryDocument.Number(food[key], double.NaN);
            if (!double.IsFinite(value) || (key == "quantity" ? value <= 0 : value < 0)) throw new InvalidDataException($"食物字段 {key} 数值无效。");
            food[key] = value;
        }
        if (food["id"] is null) food["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant();
        var foods = InventoryDocument.EnsureArray(inventory.MealPlan, "foods");
        var id = food["id"]?.ToString();
        for (var index = foods.Count - 1; index >= 0; index--) if (InventoryDocument.IdEquals((foods[index] as JsonObject)?["id"]?.ToString(), id)) foods.RemoveAt(index);
        foods.Add(food); return InventoryDocument.NormalizeId(id) ?? throw new InvalidDataException("食物 ID 无效。");
    }

    public static void RemoveFood(InventoryDocument inventory, string id)
    {
        var foods = InventoryDocument.EnsureArray(inventory.MealPlan, "foods");
        for (var index = foods.Count - 1; index >= 0; index--) if (InventoryDocument.IdEquals((foods[index] as JsonObject)?["id"]?.ToString(), id)) foods.RemoveAt(index);
    }

    public static void SetFoodFlags(InventoryDocument inventory, string id, bool? purchased = null, bool? packed = null)
    {
        var food = InventoryDocument.EnsureArray(inventory.MealPlan, "foods").OfType<JsonObject>().FirstOrDefault(item => InventoryDocument.IdEquals(item["id"]?.ToString(), id)) ?? throw new InvalidOperationException("路餐项目不存在。");
        if (purchased is not null) food["purchased"] = purchased.Value; if (packed is not null) food["packed"] = packed.Value;
    }

    public static double EnergyForDay(InventoryDocument inventory, int day) => InventoryDocument.EnsureArray(inventory.MealPlan, "foods").OfType<JsonObject>().Where(item => InventoryDocument.Int(item["day"], 1) == day && item["meal"]?.ToString() != "备用粮").Sum(FoodEnergy);

    public static string ShoppingList(InventoryDocument inventory)
    {
        var plan = inventory.MealPlan; var days = InventoryDocument.Int(plan["days"], 1); var people = InventoryDocument.Int(plan["people"], 1); var summary = Summarize(inventory);
        var lines = new List<string> { $"路餐清单 · {days} 天 · {people} 人", $"食物 {summary.FoodWeightGrams:0.##} g · 出发携水 {summary.WaterLiters:0.##} L" };
        foreach (var item in InventoryDocument.EnsureArray(plan, "foods").OfType<JsonObject>().OrderBy(item => InventoryDocument.Int(item["day"], 1)))
            lines.Add($"{(InventoryDocument.Bool(item["purchased"]) ? "已购" : "待购")} · 第{InventoryDocument.Int(item["day"], 1)}天 {item["meal"]} · {item["name"]} × {InventoryDocument.Number(item["quantity"]):0.##} · {FoodWeight(item):0.##} g · {item["preparation"]}" + (string.IsNullOrWhiteSpace(item["notes"]?.ToString()) ? "" : " · " + item["notes"]));
        return string.Join(Environment.NewLine, lines);
    }

    public static IReadOnlyList<JsonObject> Recommend(MealRecommendationOptions options)
    {
        if (options.Days is < 1 or > 60 || options.People is < 1 or > 100 || options.StartDay < 1 || options.StartDay > options.Days || options.CarryDays < 1 || !double.IsFinite(options.DailyCalories) || options.DailyCalories is < 1000 or > 10000)
            throw new InvalidDataException("推荐计划的天数、人数或每日热量无效。");
        var endDay = options.StartDay + (options.HasResupply ? Math.Min(options.CarryDays, options.Days - options.StartDay + 1) : options.Days - options.StartDay + 1) - 1;
        var templates = new (string Name, string Meal, double Grams, double Calories, string Preparation)[]
        {
            (options.CanHeat ? "燕麦与奶粉组合" : "即食麦片与奶粉组合", "早餐", 120, 520, options.CanHeat ? "热水冲泡" : "即食"),
            ("饼干／卷饼与坚果酱组合", "午餐", 140, 600, "即食"),
            (options.CanHeat ? "速食主食与脱水菜肉组合" : "即食饼干与肉干组合", "晚餐", options.CanHeat ? 140 : 160, options.CanHeat ? 600 : 650, options.CanHeat ? "热水冲泡" : "即食"),
            ("混合坚果", "行进零食", 80, 480, "即食"), ("果干", "行进零食", 60, 180, "即食"), ("巧克力／能量棒", "行进零食", 40, 220, "即食")
        };
        var ratio = options.DailyCalories / templates.Sum(item => item.Calories);
        var output = new List<JsonObject>();
        for (var day = options.StartDay; day <= endDay; day++)
            foreach (var item in templates)
                output.Add(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["name"] = item.Name, ["day"] = day, ["meal"] = item.Meal, ["quantity"] = options.People, ["grams"] = item.Grams * ratio + 5, ["calories"] = item.Calories * ratio, ["price"] = 0, ["preparation"] = item.Preparation, ["notes"] = "推荐示例估值，每份为1人份；含估计包装5g。按实际包装核对重量、热量和价格；按口味及过敏原替换。", ["purchased"] = false, ["packed"] = false });
        if (options.Reserve)
            output.Add(new JsonObject { ["id"] = Guid.NewGuid().ToString("D").ToUpperInvariant(), ["name"] = "备用即食粮（坚果、能量棒、饼干）", ["day"] = options.StartDay, ["meal"] = "备用粮", ["quantity"] = options.People, ["grams"] = options.DailyCalories / 4.4 + 10, ["calories"] = options.DailyCalories, ["price"] = 0, ["preparation"] = "即食", ["notes"] = "约1天／人的应急储备，示例估值含包装；不计入每日计划热量。请按实际食品标签核对。", ["purchased"] = false, ["packed"] = false });
        return output;
    }

    public static double ToSwiftDate(DateTime value) => (value.ToUniversalTime() - new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
    public static DateTime FromSwiftDate(JsonNode? node) => new DateTime(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddSeconds(InventoryDocument.Number(node)).ToLocalTime();
    public static readonly string[] Meals = ["早餐", "午餐", "晚餐", "行进零食", "备用粮"];
    public static readonly string[] Preparations = ["即食", "热水冲泡", "需要烹煮"];
    private static double FoodWeight(JsonObject node) => InventoryDocument.Number(node["quantity"]) * InventoryDocument.Number(node["grams"]);
    private static double FoodEnergy(JsonObject node) => InventoryDocument.Number(node["quantity"]) * InventoryDocument.Number(node["calories"]);
    private static double FoodCost(JsonObject node) => InventoryDocument.Number(node["quantity"]) * InventoryDocument.Number(node["price"]);
}
