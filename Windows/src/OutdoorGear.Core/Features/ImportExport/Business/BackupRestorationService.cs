using OutdoorGear.Core.Features.ImportExport.Data;
using OutdoorGear.Core.Services;

namespace OutdoorGear.Core.Features.ImportExport.Business;

public static class BackupRestorationService
{
    public static void Restore(LocalLibraryRepository repository, string path)
    {
        var dataDirectory = repository.DirectoryFor(repository.Catalog.SelectedId);
        using var source = InventoryBackupService.Open(path);
        var restorer = new BackupAssetRestorer(source.Root, dataDirectory);
        try
        {
            var backup = restorer.Read(out var version);
            var merged = BackupMergeService.Merge(backup, repository.Current, version);
            var recoveryPath = Path.Combine(dataDirectory, "Backups", $"恢复前-{DateTime.UtcNow:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}.zip");
            InventoryBackupService.Create(repository.Current, dataDirectory, recoveryPath);
            repository.ReplaceCurrent(merged);
        }
        catch
        {
            restorer.CleanupCreatedFiles();
            throw;
        }
    }
}
