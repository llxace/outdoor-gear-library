using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Core.Features.ImportExport.Data;
using OutdoorGear.Core.Features.ImportExport.Business;
using OutdoorGear.Core.Features.Photos.Business;
using OutdoorGear.Core.Features.Settings.Business;
using OutdoorGear.Core.Features.Settings.Data;
using OutdoorGear.Core.Features.Settings.Domain;
using System.Text.Json.Nodes;
using System.IO;
using System.Net.Http;

namespace OutdoorGear.Wpf.ViewModels;

public sealed class LibrarySession : INotifyPropertyChanged
{
    private readonly LocalLibraryRepository repository;
    private string selectedCategory = "全部分类";
    private string searchText = "";
    private string statusFilter = "全部状态";
    private string sortBy = "名称";
    private bool sortAscending = true;
    private string message = "数据保存在本机";
    private string weatherMessage = "选择路线后加载行前天气";
    private DateTime departure = DateTime.Now.AddDays(1).Date.AddHours(8);
    private WeatherForecast? forecast;
    private SeasonalOutlook? outlook;
    private TerrainSummary? terrain;
    private bool forecastOutOfRange;
    private string outlookError = "";
    private PackingUndo? clearUndo;
    private IReadOnlyDictionary<string, ExchangeRate> exchangeRates =
        new Dictionary<string, ExchangeRate>();
    private bool exchangeLoading;
    private bool exchangeOffline;
    private string exchangeError = "";
    public event PropertyChangedEventHandler? PropertyChanged;
    public InventoryDocument Inventory => repository.Current;
    public IReadOnlyList<LibraryUserRecord> Users => repository.Catalog.Users;
    public string SelectedUserId => repository.Catalog.SelectedId;
    public string CurrentDataDirectory => repository.DirectoryFor(SelectedUserId);
    public string CurrentUserName => Users.FirstOrDefault(user => InventoryDocument.IdEquals(user.Id, SelectedUserId))?.Name ?? "用户";
    public ObservableCollection<GearRowViewModel> Rows { get; } = [];
    public ObservableCollection<CategoryFolderViewModel> Categories { get; } = [];
    public string Message { get => message; private set { message = value; OnPropertyChanged(); } }
    public string SelectedCategory { get => selectedCategory; private set { selectedCategory = value; OnPropertyChanged(); RefreshRows(); } }
    public string SearchText { get => searchText; set { searchText = value; OnPropertyChanged(); RefreshRows(); } }
    public string StatusFilter { get => statusFilter; set { statusFilter = value; OnPropertyChanged(); RefreshRows(); } }
    public string SortBy { get => sortBy; set { sortBy = value; OnPropertyChanged(); RefreshRows(); } }
    public bool SortAscending { get => sortAscending; set { sortAscending = value; OnPropertyChanged(); RefreshRows(); } }
    public int ActiveGearCount => Inventory.Gear(false).Count(item => !item.IsLocation);
    public int HistoryCount => Inventory.HikeNodes.OfType<System.Text.Json.Nodes.JsonObject>().Count(item => !InventoryDocument.Bool(item["deleted"]));
    public PackingSummary Packing => PackingService.Summarize(Inventory);
    public double TotalPurchaseValue => Inventory.Gear(false).Where(item => !item.IsLocation).Sum(item => item.PurchasePrice);
    public TripPlanningService Trip { get; } = new(Path.Combine(AppContext.BaseDirectory, "Resources", "DomesticRoutes.json"));
    public RouteSummary? SelectedRoute => TripPlanningService.ReadSelectedRoute(Inventory.Root["selectedRoute"]);
    public string RouteName => SelectedRoute?.Name ?? "未选择路线";
    public string RouteDistance => SelectedRoute?.Distance ?? "搜索或导入路线后查看联动天气与轨迹";
    public IReadOnlyDictionary<string, ExchangeRate> ExchangeRates => exchangeRates;
    public bool ExchangeLoading { get => exchangeLoading; private set { exchangeLoading = value; OnPropertyChanged(); OnPropertyChanged(nameof(ExchangeDescription)); } }
    public string ExchangeError { get => exchangeError; private set { exchangeError = value; OnPropertyChanged(); } }
    public string ExchangeDescription => CurrencyConversion.Describe(
        Inventory.Settings["currency"]?.ToString() ?? "CNY",
        ExchangeRates,
        ExchangeLoading,
        exchangeOffline);
    public DateTime Departure
    {
        get => departure;
        set
        {
            var localValue = DateTime.SpecifyKind(value, DateTimeKind.Local);
            if (departure == localValue && MealService.FromSwiftDate(Inventory.MealPlan["startDate"]) == localValue) return;
            var hadStartDate = Inventory.MealPlan.TryGetPropertyValue("startDate", out var previousStartDate);
            Inventory.MealPlan["startDate"] = MealService.ToSwiftDate(localValue);
            try { repository.SaveCurrent(); }
            catch
            {
                if (hadStartDate) Inventory.MealPlan["startDate"] = previousStartDate;
                else Inventory.MealPlan.Remove("startDate");
                throw;
            }
            departure = localValue;
            OnPropertyChanged();
            OnPropertyChanged(nameof(DepartureTrend));
            Message = "出发时间已保存到本机";
        }
    }
    public WeatherForecast? Forecast { get => forecast; private set { forecast = value; OnPropertyChanged(); } }
    public SeasonalOutlook? Outlook { get => outlook; private set { outlook = value; OnPropertyChanged(); OnPropertyChanged(nameof(DepartureTrend)); } }
    public WeatherTrend? DepartureTrend => Outlook is { } value ? TripPlanningService.TrendAt(value, Departure) : null;
    public bool ForecastOutOfRange { get => forecastOutOfRange; private set { forecastOutOfRange = value; OnPropertyChanged(); } }
    public string OutlookError { get => outlookError; private set { outlookError = value; OnPropertyChanged(); } }
    public TerrainSummary? Terrain { get => terrain; private set { terrain = value; OnPropertyChanged(); } }
    public string WeatherMessage { get => weatherMessage; private set { weatherMessage = value; OnPropertyChanged(); } }

    public LibrarySession()
    {
        repository = new LocalLibraryRepository();
        RefreshDepartureFromMealPlan();
        LoadCachedExchangeRates();
        RefreshCategories(); RefreshRows();
    }

    public bool SelectUser(string id)
    {
        try
        {
            if (!repository.SelectUser(id)) return false;
            OnPropertyChanged(nameof(Inventory)); OnPropertyChanged(nameof(CurrentUserName));
            OnPropertyChanged(nameof(SelectedRoute)); OnPropertyChanged(nameof(RouteName)); OnPropertyChanged(nameof(RouteDistance));
            RefreshDepartureFromMealPlan();
            Forecast = null; Outlook = null; Terrain = null; ForecastOutOfRange = false; OutlookError = "";
            LoadCachedExchangeRates(); RefreshCategories(); RefreshRows();
            try { RefreshBorrowedPackingItems(); }
            catch (Exception error) { Message = $"已切换用户；借用装备刷新失败：{error.Message}"; return true; }
            Message = $"已切换到 {CurrentUserName} 的资料库";
            return true;
        }
        catch (Exception error) { Message = error.Message; return false; }
    }

    public void SaveProfile(string name, string? avatarPath = null, bool removeAvatar = false)
    {
        repository.SaveProfile(name, SelectedUserId, avatarPath, removeAvatar);
        OnPropertyChanged(nameof(Users)); OnPropertyChanged(nameof(CurrentUserName));
        Message = "用户资料已保存";
    }

    public string ImportAsset(string sourcePath, bool photo)
    {
        if (!File.Exists(sourcePath)) throw new FileNotFoundException("找不到选择的文件。", sourcePath);
        var extension = Path.GetExtension(sourcePath);
        if (extension.Length is < 2 or > 12) throw new InvalidDataException("文件类型无效。");
        var folder = Path.Combine(CurrentDataDirectory, photo ? "Photos" : "Files");
        Directory.CreateDirectory(folder);
        var name = Guid.NewGuid().ToString("D").ToUpperInvariant() + extension.ToLowerInvariant();
        File.Copy(sourcePath, Path.Combine(folder, name));
        return name;
    }

    public void SetPrimaryPhotoFromAttachment(GearRecord gear, JsonObject attachment)
    {
        if (!Inventory.Gear().Any(item => InventoryDocument.IdEquals(item.Id, gear.Id)) ||
            !InventoryDocument.Bool(attachment["isImage"]))
            throw new InvalidOperationException("所选记录或图片附件无效。");
        var fileName = GearAssetService.CopyImageAttachmentToPhotos(CurrentDataDirectory, attachment);
        var destination = GearAssetService.AssetPath(CurrentDataDirectory, "Photos", fileName);
        var previous = gear.Photo;
        gear.Photo = fileName;
        try { SaveGear(gear); }
        catch
        {
            gear.Photo = previous;
            try { File.Delete(destination); } catch { }
            throw;
        }
    }

    public void CreateProfile(string name, string? avatarPath = null)
    {
        repository.SaveProfile(name, avatarFile: avatarPath);
        var created = repository.Catalog.Users.Last();
        if (!SelectUser(created.Id)) throw new InvalidOperationException("资料库已创建，但当前未能切换到该用户。");
        OnPropertyChanged(nameof(Users)); Message = "已创建并切换到新资料库";
    }

    public void Save()
    {
        try { repository.SaveCurrent(); OnPropertyChanged(nameof(Inventory)); OnPropertyChanged(nameof(ActiveGearCount)); OnPropertyChanged(nameof(HistoryCount)); OnPropertyChanged(nameof(Packing)); OnPropertyChanged(nameof(TotalPurchaseValue)); RefreshCategories(); RefreshRows(); Message = "已保存到本机"; }
        catch (Exception error) { Message = "保存失败：" + error.Message; throw; }
    }

    public bool RefreshDepartureFromMealPlan()
    {
        var previous = departure;
        var stored = Inventory.MealPlan["startDate"];
        departure = stored is null
            ? DateTime.Now.AddDays(1).Date.AddHours(8)
            : MealService.FromSwiftDate(stored);
        if (departure == previous) return false;
        OnPropertyChanged(nameof(Departure));
        return true;
    }

    public void SaveGear(GearRecord gear) { GearService.Save(Inventory, gear); Save(); }

    public void RestoreOriginalPhoto(GearRecord gear)
    {
        var change = ProductPhotoRestorationService.Restore(Inventory, CurrentDataDirectory, gear.Id!);
        try { SaveGear(gear); }
        catch { ProductPhotoRestorationService.RollBack(change); throw; }
    }

    public InventoryDocument ReadUserInventory(string userId) => repository.ReadUserInventory(userId);

    public void SaveGearForUser(string userId, InventoryDocument inventory, GearRecord gear)
    {
        var owner = Users.FirstOrDefault(user => InventoryDocument.IdEquals(user.Id, userId))
            ?? throw new InvalidOperationException("目标用户资料不存在。");
        var copiedAssets = GearAssetService.CopyGearAssetsToDirectory(gear, CurrentDataDirectory, repository.DirectoryFor(owner.Id));
        try
        {
            GearService.Save(inventory, gear);
            repository.SaveOtherUserInventory(owner.Id, inventory);
            Message = $"装备已保存到“{owner.Name}”的装备库";
        }
        catch
        {
            GearAssetService.DeleteCreated(copiedAssets);
            throw;
        }
    }

    public int EnsureIdentifiers()
    {
        var count = GearService.EnsureIdentifiers(Inventory);
        if (count > 0) Save();
        return count;
    }

    public int NormalizePurchaseDates()
    {
        var count = GearService.NormalizePurchaseDates(Inventory);
        if (count > 0) Save();
        return count;
    }

    public string FormatMoney(double yuan) => CurrencyConversion.FormatMoney(
        yuan,
        Inventory.Settings["currency"]?.ToString() ?? "CNY",
        ExchangeRates);

    public async Task RefreshExchangeRatesAsync(CancellationToken cancellationToken = default)
    {
        var currencyCode = Inventory.Settings["currency"]?.ToString() ?? "CNY";
        if (currencyCode == "CNY" || ExchangeLoading)
            return;
        ExchangeLoading = true;
        ExchangeError = "";
        exchangeOffline = false;
        try
        {
            exchangeRates = await new ExchangeRateRepository(CurrentDataDirectory)
                .FetchAndSaveAsync(cancellationToken);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidDataException or TaskCanceledException)
        {
            exchangeRates = new ExchangeRateRepository(CurrentDataDirectory).ReadCachedRates();
            exchangeOffline = exchangeRates.Count > 0;
            ExchangeError = "联网获取失败；使用本机缓存，未缓存时按人民币显示。";
        }
        finally
        {
            ExchangeLoading = false;
            OnPropertyChanged(nameof(ExchangeRates));
            OnPropertyChanged(nameof(ExchangeDescription));
        }
    }

    private void LoadCachedExchangeRates()
    {
        exchangeRates = new ExchangeRateRepository(CurrentDataDirectory).ReadCachedRates();
        exchangeOffline = false;
        ExchangeError = "";
        OnPropertyChanged(nameof(ExchangeRates));
        OnPropertyChanged(nameof(ExchangeDescription));
    }

    public int SetMissingPrimaryPhotos()
    {
        var changes = new List<(GearRecord Gear, string? Previous, string Created)>();
        try
        {
            CopyMissingPhotos(changes);
            if (changes.Count > 0) Save();
            return changes.Count;
        }
        catch
        {
            RollBackMissingPhotos(changes);
            throw;
        }
    }

    private void CopyMissingPhotos(List<(GearRecord Gear, string? Previous, string Created)> changes)
    {
        foreach (var gear in Inventory.Gear(false).Where(item => !item.IsLocation && string.IsNullOrWhiteSpace(item.Photo)))
        {
            var image = gear.Extras.Attachments.OfType<JsonObject>()
                .FirstOrDefault(item => InventoryDocument.Bool(item["isImage"]));
            if (image is null) continue;
            var copied = GearAssetService.CopyImageAttachmentToPhotos(CurrentDataDirectory, image);
            changes.Add((gear, gear.Photo, copied));
            gear.Photo = copied;
        }
    }

    private void RollBackMissingPhotos(
        IEnumerable<(GearRecord Gear, string? Previous, string Created)> changes)
    {
        foreach (var change in changes)
        {
            change.Gear.Photo = change.Previous;
            try { File.Delete(GearAssetService.AssetPath(CurrentDataDirectory, "Photos", change.Created)); }
            catch { }
        }
    }

    public void SetPacking(GearRowViewModel row, bool selected, double quantity)
    {
        try { PackingService.SetOwnQuantity(Inventory, row.Gear.Id!, selected ? quantity : null); Save(); }
        catch { row.RefreshPackingState(); throw; }
    }

    public void ClearPacking()
    {
        clearUndo = PackingService.Clear(Inventory); Save();
    }

    public bool UndoClearPacking()
    {
        if (clearUndo is null) return false; PackingService.Restore(Inventory, clearUndo); clearUndo = null; Save(); return true;
    }

    public void RemoveUnavailable()
    {
        var count = PackingService.RemoveUnavailable(Inventory); Save(); Message = $"已移除 {count} 项不可用装备";
    }

    public void SetCategory(string path) => SelectedCategory = path;
    public void SetSearch(string value) => SearchText = value;

    public void RefreshCategories()
    {
        Categories.Clear();
        AddCategory("全部装备", "全部分类");
        foreach (var name in Inventory.Categories.Select(node => node?.ToString() ?? ""))
        {
            var children = name switch { "帐篷与睡眠" => new[] { "帐篷", "睡袋", "防潮垫与睡眠配件" }, "服装与配饰" => new[] { "贴身与速干", "抓绒与中层", "羽绒与棉服", "防风与雨衣", "裤装", "帽子与头巾", "手套", "眼镜与面罩", "其他服装" }, "鞋袜与行走" => new[] { "鞋", "袜子", "行走配件" }, _ => Array.Empty<string>() };
            AddCategory(name, name);
            foreach (var child in children) AddCategory("    " + child, name + "/" + child);
        }
        AddCategory("已损坏", "已损坏");
    }

    public void RefreshRows()
    {
        if (Rows is null) return;
        var matches = GearService.Search(Inventory, SearchText, includeTrashed: false)
            .Where(item => !item.IsLocation && MatchesCategory(item) && (StatusFilter == "全部状态" || item.Status == StatusFilter));
        var ordered = SortBy switch
        {
            "资产编号" => SortAscending ? matches.OrderBy(item => item.Extras.AssetId) : matches.OrderByDescending(item => item.Extras.AssetId),
            "价格" => SortAscending ? matches.OrderBy(item => item.PurchasePrice) : matches.OrderByDescending(item => item.PurchasePrice),
            "重量" => SortAscending ? matches.OrderBy(item => item.Weight) : matches.OrderByDescending(item => item.Weight),
            "购买时间" => SortAscending ? matches.OrderBy(item => item.PurchaseDate, StringComparer.CurrentCultureIgnoreCase) : matches.OrderByDescending(item => item.PurchaseDate, StringComparer.CurrentCultureIgnoreCase),
            _ => SortAscending ? matches.OrderBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase) : matches.OrderByDescending(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
        };
        Rows.Clear(); foreach (var item in ordered) Rows.Add(new GearRowViewModel(item, this));
    }

    public IEnumerable<GearRecord> TrashRecords() => Inventory.Gear().Where(item => item.Trashed && !item.IsLocation);
    public IEnumerable<GearRecord> AllRecords() => Inventory.Gear(false);
    public void Trash(IEnumerable<string> ids, bool trashed) { GearService.SetTrashed(Inventory, ids, trashed); Save(); }
    public void DeletePermanently(IEnumerable<string> ids) { GearService.DeletePermanently(Inventory, ids); Save(); }
    public int TrashAllGear()
    {
        var ids = Inventory.Gear(false).Where(item => !item.IsLocation && !item.Trashed).Select(item => item.Id!).ToArray();
        if (ids.Length == 0) return 0;
        var changed = GearService.ChangeRecords(Inventory, ids, trashed: true);
        Save();
        return changed;
    }
    public void ToggleFavorite(string id) { GearService.ToggleFavorite(Inventory, id); Save(); }
    public string Backup(string path) { var result = InventoryBackupService.Create(Inventory, CurrentDataDirectory, path); Message = "当前资料库备份已保存"; return result; }
    public void RestoreBackup(string path) { BackupRestorationService.Restore(repository, path); OnPropertyChanged(nameof(Inventory)); RefreshCategories(); RefreshRows(); Message = "备份已合并恢复"; }
    public CsvImportResult ImportCsv(string text) { var result = CsvService.Merge(text, Inventory); repository.ReplaceCurrent(result.Inventory); RefreshCategories(); RefreshRows(); Message = $"CSV 导入完成：新增 {result.Added}、更新 {result.Updated}"; return result; }
    public void ImportExcel(ExcelImportResult result) { repository.ReplaceCurrent(result.Inventory); RefreshCategories(); RefreshRows(); Message = $"Excel 导入完成：新增 {result.Added}、更新 {result.Updated}、跳过 {result.Skipped}"; }
    public string ExportCsv() => CsvService.Export(Inventory);

    public IReadOnlyList<BorrowableGearRecord> ReadBorrowableGear(string ownerId) =>
        BorrowingService.ReadAvailableGear(repository, SelectedUserId, ownerId);

    public void AddBorrowedGear(string ownerId, string gearId)
    {
        var (owner, gear) = ResolveBorrowSource(ownerId, gearId);
        var copied = BorrowingService.CopyGearSnapshot(repository.DirectoryFor(owner.Id), CurrentDataDirectory, gear);
        try
        {
            PackingService.SetBorrowedQuantity(
                Inventory, owner.Id, owner.Name, copied.Gear, Math.Min(1, gear.Quantity), gear.Extras.Subcategory);
            Save();
        }
        catch
        {
            RemoveBorrowedGearSnapshot(owner.Id, gear.Id);
            BorrowingService.RemoveCopiedPhoto(CurrentDataDirectory, copied.CopiedPhoto);
            throw;
        }
    }

    private (LibraryUserRecord Owner, GearRecord Gear) ResolveBorrowSource(string ownerId, string gearId)
    {
        var owner = Users.FirstOrDefault(user => InventoryDocument.IdEquals(user.Id, ownerId))
            ?? throw new InvalidOperationException("来源用户不存在。");
        if (InventoryDocument.IdEquals(owner.Id, SelectedUserId))
            throw new InvalidOperationException("不能从当前用户自己的装备库借用装备。");
        if (Inventory.BorrowedNodes.OfType<JsonObject>().Any(item =>
                InventoryDocument.IdEquals(item["ownerID"]?.ToString(), owner.Id) &&
                InventoryDocument.IdEquals(item["gear"]?["id"]?.ToString(), gearId)))
            throw new InvalidOperationException("这件装备已经在本次打包清单中。");
        var source = repository.ReadUserInventory(owner.Id);
        var gear = source.FindGear(gearId);
        if (gear is null || gear.Trashed || gear.IsLocation) throw new InvalidOperationException("来源装备不存在或不可借用。");
        if (gear.Status == "损坏") throw new InvalidOperationException("已损坏的装备不能加入打包清单。");
        return (owner, gear);
    }

    public void SetBorrowedGearQuantity(string ownerId, string gearId, double? quantity)
    {
        var borrowed = Inventory.BorrowedNodes.OfType<JsonObject>().FirstOrDefault(item =>
            InventoryDocument.IdEquals(item["ownerID"]?.ToString(), ownerId) &&
            InventoryDocument.IdEquals(item["gear"]?["id"]?.ToString(), gearId))
            ?? throw new InvalidOperationException("这件借用装备已不在打包清单中。");
        if (quantity is null)
        {
            RemoveBorrowedGearSnapshot(ownerId, gearId);
            Save();
            return;
        }
        PackingService.SetBorrowedQuantity(
            Inventory,
            ownerId,
            borrowed["ownerName"]?.ToString() ?? "其他用户",
            (JsonObject)borrowed["gear"]!.DeepClone(),
            quantity,
            borrowed["subcategory"]?.ToString());
        Save();
    }

    public void RefreshBorrowedPackingItems()
    {
        if (BorrowingService.RefreshSnapshots(repository, SelectedUserId, Inventory)) Save();
    }

    private void RemoveBorrowedGearSnapshot(string ownerId, string? gearId)
    {
        for (var index = Inventory.BorrowedNodes.Count - 1; index >= 0; index--)
        {
            if (Inventory.BorrowedNodes[index] is JsonObject item &&
                InventoryDocument.IdEquals(item["ownerID"]?.ToString(), ownerId) &&
                InventoryDocument.IdEquals(item["gear"]?["id"]?.ToString(), gearId))
                Inventory.BorrowedNodes.RemoveAt(index);
        }
    }

    public async Task SelectRouteAsync(RouteSummary route)
    {
        WeatherMessage = "正在读取路线轨迹…";
        try
        {
            var detailed = await Trip.LoadRouteAsync(route);
            if (detailed.Segments.SelectMany(segment => segment).Any(point => !TrailFileReader.Valid(point))) throw new InvalidDataException("路线包含无效坐标。");
            Inventory.Root["selectedRoute"] = TripPlanningService.ToJson(detailed); Save(); OnPropertyChanged(nameof(SelectedRoute)); OnPropertyChanged(nameof(RouteName)); OnPropertyChanged(nameof(RouteDistance));
            await LoadWeatherAsync();
        }
        catch (Exception error) { WeatherMessage = "路线载入失败：" + error.Message; }
    }

    public void RemoveRoute()
    {
        Inventory.Root["selectedRoute"] = null; Save(); OnPropertyChanged(nameof(SelectedRoute)); OnPropertyChanged(nameof(RouteName)); OnPropertyChanged(nameof(RouteDistance)); Forecast = null; Outlook = null; Terrain = null; ForecastOutOfRange = false; OutlookError = ""; WeatherMessage = "未选择路线";
    }

    public async Task LoadWeatherAsync(CancellationToken cancellationToken = default)
    {
        ResetWeatherResults();
        var route = SelectedRoute;
        if (route is null) { WeatherMessage = "先搜索并选择一条路线"; return; }
        if (!ValidateDepartureTime()) return;
        WeatherMessage = "正在查询路线天气…";
        try { await LoadForecastAsync(route, cancellationToken); }
        catch (ForecastRangeException error) { await HandleForecastRangeAsync(error, cancellationToken); }
        catch (Exception error) { WeatherMessage = error.Message; }
    }

    private void ResetWeatherResults()
    {
        Forecast = null;
        Terrain = null;
        ForecastOutOfRange = false;
        OutlookError = "";
        Outlook = null;
    }

    private bool ValidateDepartureTime()
    {
        if (Departure < DateTime.Now)
        {
            WeatherMessage = "出发时间已过，请选择今天或之后的时间";
            return false;
        }
        return true;
    }

    private async Task LoadForecastAsync(RouteSummary route, CancellationToken cancellationToken)
    {
        Forecast = await Trip.ForecastAsync(route.Center, new DateTimeOffset(Departure), cancellationToken);
        Terrain = await Trip.TerrainAsync(route, cancellationToken);
        WeatherMessage = "天气来源：Open-Meteo · 路线中心网格预报";
    }

    private async Task HandleForecastRangeAsync(ForecastRangeException error, CancellationToken cancellationToken)
    {
        ForecastOutOfRange = true;
        WeatherMessage = error.Message;
        try
        {
            await LoadOutlookAsync(cancellationToken);
            WeatherMessage = DepartureTrend is { } trend
                ? $"已显示出发日期对应的{(trend.Monthly ? "月" : "周")}区域趋势，不代表当天预报"
                : "已查询远期趋势，但当前趋势数据不含所选日期";
        }
        catch (Exception outlookFailure) { WeatherMessage = error.Message + " 远期趋势查询失败：" + outlookFailure.Message; }
    }

    public async Task LoadOutlookAsync(CancellationToken cancellationToken = default)
    {
        var route = SelectedRoute; if (route is null) throw new InvalidOperationException("先选择路线。");
        Outlook = null; OutlookError = "";
        try { Outlook = await Trip.OutlookAsync(route.Center, cancellationToken); }
        catch (Exception error) { OutlookError = error.Message; throw; }
    }

    private bool MatchesCategory(GearRecord gear)
    {
        if (SelectedCategory is "全部分类" or "全部装备") return true;
        if (SelectedCategory == "已损坏") return gear.Status == "损坏";
        var parts = SelectedCategory.Split('/');
        return gear.Category == parts[0] && (parts.Length == 1 || GearService.Subcategory(gear) == parts[1]);
    }
    private void AddCategory(string name, string path)
    {
        var rows = Inventory.Gear(false).Where(item => !item.IsLocation && (path == "全部分类" || path == "已损坏" ? path == "全部分类" || item.Status == "损坏" : item.Category == path.Split('/')[0] && (path.Split('/').Length == 1 || GearService.Subcategory(item) == path.Split('/')[1]))).Count();
        Categories.Add(new CategoryFolderViewModel(name, path, rows, SelectedCategory == path));
    }
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed class CategoryFolderViewModel(string name, string path, int count, bool selected)
{
    public string Name { get; } = name; public string Path { get; } = path; public int Count { get; } = count; public bool Selected { get; } = selected;
    public string Glyph => Path switch { "全部分类" => "▦", "已损坏" => "⚠", _ => Path.Split('/')[0] switch { "背包与收纳" => "▣", "帐篷与睡眠" => "⌂", "服装与配饰" => "♟", "鞋袜与行走" => "◒", "炊具与饮水" => "♨", "照明与电子" => "☼", "工具与急救" => "✚", "洗漱与杂项" => "✧", _ => "✦" } };
}

public sealed class GearRowViewModel : INotifyPropertyChanged
{
    private readonly LibrarySession session;
    private bool isPacking;
    private double packQuantity;
    public GearRecord Gear { get; }
    public event PropertyChangedEventHandler? PropertyChanged;
    public string Id => Gear.Id!;
    public string Name { get => Gear.Name; set { Gear.Name = value; Changed(); } }
    public string Brand { get => Gear.Brand; set { Gear.Brand = value; Changed(); } }
    public string Model { get => Gear.Model; set { Gear.Model = value; Changed(); } }
    public string Category { get => Gear.Category; set { Gear.Category = value; Changed(); } }
    public string Status { get => Gear.Status; set { Gear.Status = value; Changed(); } }
    public double Weight { get => Gear.Weight; set { Gear.Weight = value; Changed(); } }
    public double Quantity { get => Gear.Quantity; set { Gear.Quantity = value; Changed(); } }
    public double PurchasePrice { get => Gear.PurchasePrice; set { Gear.PurchasePrice = value; Changed(); } }
    public string PurchasePriceLabel => PurchasePrice > 0 ? session.FormatMoney(PurchasePrice) : "未记录价格";
    public bool Favorite => session.Inventory.IsFavorite(Id);
    public bool IsPacking { get => isPacking; set { if (isPacking == value) return; session.SetPacking(this, value, Math.Max(1, PackQuantity)); isPacking = value; Changed(); Changed(nameof(PackWeightLabel)); } }
    public double PackQuantity { get => packQuantity; set { packQuantity = value; Changed(); Changed(nameof(PackWeightLabel)); if (IsPacking) session.SetPacking(this, true, value); } }
    public string WeightLabel => $"{Weight:0.##} g / 件 · 库内 {Quantity:0.##} 件";
    public string PackWeightLabel => IsPacking ? $"{Math.Min(PackQuantity, Quantity) * Weight:0.##} g" : "—";
    public string Subcategory => GearService.Subcategory(Gear);
    public string PhotoPath
    {
        get
        {
            if (string.IsNullOrWhiteSpace(Gear.Photo)) return "";
            try
            {
                var path = GearAssetService.AssetPath(session.CurrentDataDirectory, "Photos", Gear.Photo);
                return File.Exists(path) ? path : "";
            }
            catch (Exception error) when (error is InvalidDataException or IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
            {
                return "";
            }
        }
    }

    public GearRowViewModel(GearRecord gear, LibrarySession session)
    {
        Gear = gear; this.session = session;
        var pack = session.Inventory.PackingNodes.OfType<System.Text.Json.Nodes.JsonObject>().FirstOrDefault(node => InventoryDocument.IdEquals(node["sourceGearID"]?.ToString(), Id));
        isPacking = pack is not null && gear.Status != "损坏"; packQuantity = pack is null ? 0 : InventoryDocument.Number(pack["quantity"]);
    }
    public void RefreshPackingState()
    {
        var pack = session.Inventory.PackingNodes.OfType<System.Text.Json.Nodes.JsonObject>().FirstOrDefault(node => InventoryDocument.IdEquals(node["sourceGearID"]?.ToString(), Id));
        isPacking = pack is not null; packQuantity = pack is null ? 0 : InventoryDocument.Number(pack["quantity"]); Changed(nameof(IsPacking)); Changed(nameof(PackQuantity)); Changed(nameof(PackWeightLabel));
    }
    public void Commit() => session.Save();
    private void Changed([CallerMemberName] string? property = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(property));
}
