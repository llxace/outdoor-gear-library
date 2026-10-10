using System.Text.Json;
using System.Text.Json.Nodes;
using OutdoorGear.Core.Models;

namespace OutdoorGear.Core.Services;

public sealed record LibraryUserRecord(string Id, string Name, string? AvatarFile);
public sealed record UserCatalogRecord(string SelectedId, IReadOnlyList<LibraryUserRecord> Users);

public sealed class LocalLibraryRepository
{
    public static readonly string DefaultUserId = "00000000-0000-0000-0000-000000000001";
    public static string DefaultDataRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OutdoorGearLibrary");
    public string Root { get; }
    private UserCatalogRecord catalog = new(DefaultUserId, [new LibraryUserRecord(DefaultUserId, "默认用户", null)]);
    private InventoryDocument current = InventoryDocument.Empty();
    public UserCatalogRecord Catalog => catalog;
    public InventoryDocument Current => current;

    public LocalLibraryRepository(string? root = null, string? seedDirectory = null)
    {
        Root = Path.GetFullPath(root ?? DefaultDataRoot);
        InitializeSeed(seedDirectory);
        Directory.CreateDirectory(Root);
        if (!ContainsFiles(Root)) InitializeEmptyLibrary();
        LoadCatalogAndInventory();
    }

    public string DirectoryFor(string userId) => InventoryDocument.IdEquals(userId, DefaultUserId) ? Root : Path.Combine(Root, "Users", InventoryDocument.NormalizeId(userId) ?? throw new ArgumentException("用户 ID 无效。"));

    public InventoryDocument ReadUserInventory(string userId)
    {
        var normalized = InventoryDocument.NormalizeId(userId) ?? throw new ArgumentException("用户 ID 无效。");
        if (!catalog.Users.Any(user => InventoryDocument.IdEquals(user.Id, normalized)))
            throw new InvalidOperationException("用户资料不存在。");
        var path = Path.Combine(DirectoryFor(normalized), "inventory.json");
        if (!File.Exists(path)) throw new FileNotFoundException("来源用户的装备库文件不存在。", path);
        var document = InventoryDocument.Parse(File.ReadAllText(path));
        document.Validate();
        return document;
    }

    public void SaveOtherUserInventory(string userId, InventoryDocument document)
    {
        var normalized = InventoryDocument.NormalizeId(userId) ?? throw new ArgumentException("用户 ID 无效。", nameof(userId));
        if (InventoryDocument.IdEquals(normalized, catalog.SelectedId))
            throw new InvalidOperationException("当前用户资料必须通过当前资料库保存入口写入。");
        if (!catalog.Users.Any(user => InventoryDocument.IdEquals(user.Id, normalized)))
            throw new InvalidOperationException("目标用户资料不存在。");
        document.Validate();
        SaveInventory(DirectoryFor(normalized), document);
    }

    public bool SelectUser(string userId)
    {
        var normalized = InventoryDocument.NormalizeId(userId) ?? throw new ArgumentException("用户 ID 无效。");
        if (!catalog.Users.Any(user => InventoryDocument.IdEquals(user.Id, normalized))) return false;
        var next = LoadInventory(DirectoryFor(normalized));
        var previous = catalog;
        catalog = catalog with { SelectedId = normalized };
        try { SaveCatalog(catalog); current = next; return true; }
        catch { catalog = previous; throw; }
    }

    public void SaveCurrent()
    {
        current.Validate(); SaveInventory(DirectoryFor(catalog.SelectedId), current);
    }

    public void ReplaceCurrent(InventoryDocument document)
    {
        document.Validate(); var old = current; current = document;
        try { SaveInventory(DirectoryFor(catalog.SelectedId), document); }
        catch { current = old; throw; }
    }

    public void SaveProfile(string name, string? profileId = null, string? avatarFile = null, bool removeAvatar = false)
    {
        name = name.Trim();
        if (name.Length == 0 || catalog.Users.Any(user => !InventoryDocument.IdEquals(user.Id, profileId) && string.Equals(user.Name.Trim(), name, StringComparison.OrdinalIgnoreCase))) throw new InvalidOperationException("用户名不能为空或重复。");
        if (profileId is null)
        {
            var id = Guid.NewGuid().ToString("D").ToUpperInvariant(); var directory = DirectoryFor(id); Directory.CreateDirectory(directory);
            SaveInventory(directory, InventoryDocument.Empty());
            catalog = catalog with { Users = catalog.Users.Append(new LibraryUserRecord(id, name, CopyAvatar(avatarFile))).ToArray() };
            SaveCatalog(catalog); return;
        }
        var index = catalog.Users.ToList().FindIndex(user => InventoryDocument.IdEquals(user.Id, profileId));
        if (index < 0) throw new InvalidOperationException("用户不存在。");
        var rows = catalog.Users.ToArray(); var old = rows[index]; rows[index] = old with { Name = name, AvatarFile = removeAvatar ? null : CopyAvatar(avatarFile) ?? old.AvatarFile };
        var previous = catalog; catalog = catalog with { Users = rows };
        try { SaveCatalog(catalog); if (removeAvatar && old.AvatarFile is not null) TryDelete(Path.Combine(Root, "Avatars", Path.GetFileName(old.AvatarFile))); }
        catch { catalog = previous; throw; }
    }

    public void InitializeSeed(string? seedDirectory)
    {
        if (!CanInitializeSeed(seedDirectory)) return;
        var staging = StageSeed(seedDirectory!);
        try { CommitSeed(staging); }
        finally { DeleteDirectoryIfPresent(staging); }
    }

    private bool CanInitializeSeed(string? seedDirectory) => seedDirectory is not null
        && Directory.Exists(seedDirectory)
        && !File.Exists(Path.Combine(Root, "users.json"))
        && !ContainsFiles(Root);

    private string StageSeed(string seedDirectory)
    {
        var parent = Path.GetDirectoryName(Root)!;
        Directory.CreateDirectory(parent);
        var staging = Path.Combine(parent, $".{Path.GetFileName(Root)}.seed-{Guid.NewGuid():N}");
        Directory.CreateDirectory(staging);
        try
        {
            CopySeedFiles(seedDirectory, staging);
            if (!ContainsFiles(staging)) throw new InvalidDataException("随包迁移资料为空，未改动本机数据。");
            return staging;
        }
        catch { DeleteDirectoryIfPresent(staging); throw; }
    }

    private static void CopySeedFiles(string seedDirectory, string destinationRoot)
    {
        foreach (var source in Directory.EnumerateFiles(seedDirectory, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(seedDirectory, source);
            var destination = Path.Combine(destinationRoot, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(source, destination, overwrite: false);
        }
    }

    private void CommitSeed(string staging)
    {
        if (!Directory.Exists(Root)) { Directory.Move(staging, Root); return; }
        if (ContainsFiles(Root)) return;
        var emptyRoot = staging + ".empty-root";
        Directory.Move(Root, emptyRoot);
        if (ContainsFiles(emptyRoot)) { Directory.Move(emptyRoot, Root); return; }
        try { Directory.Move(staging, Root); }
        catch
        {
            if (!Directory.Exists(Root)) Directory.Move(emptyRoot, Root);
            throw;
        }
        DeleteDirectoryIfPresent(emptyRoot);
    }

    private static bool ContainsFiles(string directory) => Directory.Exists(directory)
        && Directory.EnumerateFiles(directory, "*", SearchOption.AllDirectories).Any();

    private static void DeleteDirectoryIfPresent(string directory)
    {
        if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
    }

    private void InitializeEmptyLibrary()
    {
        Directory.CreateDirectory(Root);
        SaveCatalog(catalog);
        SaveInventory(Root, InventoryDocument.Empty());
    }

    private void LoadCatalogAndInventory()
    {
        EnsureDataDirectories(Root);
        var catalogPath = Path.Combine(Root, "users.json");
        if (File.Exists(catalogPath)) catalog = ParseCatalog(File.ReadAllText(catalogPath));
        else { SaveCatalog(catalog); }
        if (!catalog.Users.Any(user => InventoryDocument.IdEquals(user.Id, catalog.SelectedId))) throw new InvalidDataException("当前用户资料缺失，未重建数据。");
        current = LoadInventory(DirectoryFor(catalog.SelectedId));
    }

    private InventoryDocument LoadInventory(string directory)
    {
        EnsureDataDirectories(directory); var file = Path.Combine(directory, "inventory.json");
        if (!File.Exists(file)) throw new FileNotFoundException("用户装备库文件不存在。为避免覆盖或重建资料，已停止读取。", file);
        var source = File.ReadAllText(file); var oldVersion = InventoryDocument.Int((JsonNode.Parse(source) as JsonObject)?["version"]);
        var document = InventoryDocument.Parse(source); document.Validate();
        if (oldVersion < InventoryDocument.CurrentSchema)
        {
            var backup = Path.Combine(directory, "升级前备份", DateTime.Now.ToString("yyyyMMdd-HHmmss", System.Globalization.CultureInfo.InvariantCulture) + ".gearbackup");
            Directory.CreateDirectory(backup);
            foreach (var name in new[] { "inventory.json", "Photos", "Files" })
            {
                var item = Path.Combine(directory, name); if (!File.Exists(item) && !Directory.Exists(item)) continue;
                var target = Path.Combine(backup, name); if (Directory.Exists(item)) CopyTree(item, target); else File.Copy(item, target, true);
            }
            SaveInventory(directory, document);
        }
        return document;
    }

    private static void SaveInventory(string directory, InventoryDocument document)
    {
        Directory.CreateDirectory(directory); EnsureDataDirectories(directory);
        var path = Path.Combine(directory, "inventory.json"); var temp = path + ".tmp";
        File.WriteAllText(temp, document.Serialize());
        if (File.Exists(path)) File.Copy(path, Path.Combine(directory, "inventory.previous.json"), overwrite: true);
        File.Move(temp, path, overwrite: true);
    }

    private void SaveCatalog(UserCatalogRecord next)
    {
        var json = new JsonObject { ["selectedID"] = InventoryDocument.NormalizeId(next.SelectedId), ["users"] = new JsonArray(next.Users.Select(user => (JsonNode?)new JsonObject { ["id"] = InventoryDocument.NormalizeId(user.Id), ["name"] = user.Name, ["avatarFile"] = user.AvatarFile }).ToArray()) };
        WriteAtomic(Path.Combine(Root, "users.json"), json.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    private static UserCatalogRecord ParseCatalog(string text)
    {
        var root = JsonNode.Parse(text) as JsonObject ?? throw new InvalidDataException("用户资料 JSON 格式错误。");
        var users = (root["users"] as JsonArray ?? throw new InvalidDataException("用户列表缺失。")).OfType<JsonObject>().Select(user => new LibraryUserRecord(InventoryDocument.NormalizeId(user["id"]?.ToString()) ?? throw new InvalidDataException("用户 ID 无效。"), user["name"]?.ToString() ?? "", user["avatarFile"]?.ToString())).ToArray();
        var selected = InventoryDocument.NormalizeId(root["selectedID"]?.ToString()) ?? throw new InvalidDataException("当前用户 ID 无效。");
        if (users.Length == 0 || users.Select(user => user.Id).Distinct(StringComparer.OrdinalIgnoreCase).Count() != users.Length || users.Any(user => string.IsNullOrWhiteSpace(user.Name)) || !users.Any(user => InventoryDocument.IdEquals(user.Id, selected))) throw new InvalidDataException("用户列表包含空名、重复资料或未找到当前用户。");
        return new UserCatalogRecord(selected, users);
    }

    private string? CopyAvatar(string? source)
    {
        if (string.IsNullOrWhiteSpace(source)) return null;
        var path = Path.GetFullPath(source); if (!File.Exists(path)) throw new FileNotFoundException("头像文件不存在。", path);
        var extension = Path.GetExtension(path); if (extension.Length > 10) throw new InvalidDataException("头像文件扩展名无效。");
        var folder = Path.Combine(Root, "Avatars"); Directory.CreateDirectory(folder); var file = Guid.NewGuid().ToString("D").ToUpperInvariant() + extension;
        File.Copy(path, Path.Combine(folder, file)); return file;
    }

    private static void EnsureDataDirectories(string directory) { foreach (var name in new[] { "Photos", "Files" }) Directory.CreateDirectory(Path.Combine(directory, name)); }
    private static void CopyTree(string source, string destination) { Directory.CreateDirectory(destination); foreach (var file in Directory.EnumerateFiles(source)) File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), true); foreach (var child in Directory.EnumerateDirectories(source)) CopyTree(child, Path.Combine(destination, Path.GetFileName(child))); }
    private static void WriteAtomic(string path, string content) { var temp = path + ".tmp"; File.WriteAllText(temp, content); File.Move(temp, path, true); }
    private static void TryDelete(string path) { try { if (File.Exists(path)) File.Delete(path); } catch { } }
}
