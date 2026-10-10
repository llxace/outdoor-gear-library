using System.Globalization;
using System.IO;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using Microsoft.Win32;
using OutdoorGear.Core.Models;
using OutdoorGear.Core.Services;
using OutdoorGear.Wpf.ViewModels;

using OutdoorGear.Wpf.Features.Photos.Presentation;
using OutdoorGear.Wpf.Features.Shared.Presentation;

namespace OutdoorGear.Wpf.Features.Equipment.Presentation;

public sealed class RecyclePage : UserControl
{
    private readonly LibrarySession session;
    private readonly ListBox list = new() { Height = 540, SelectionMode = SelectionMode.Extended };
    public RecyclePage(LibrarySession session)
    {
        this.session = session;
        var root = PageUi.Root("回收站", "删除前可恢复，永久删除会清除关联的打包引用");
        root.Children.Add(BuildActions());
        root.Children.Add(list);
        Content = root;
        Refresh();
    }
    private UIElement BuildActions()
    {
        var actions = new WrapPanel();
        actions.Children.Add(PageUi.Button("恢复所选", (_, _) => Act(false)));
        actions.Children.Add(PageUi.Button("永久删除所选", (_, _) => Delete()));
        return actions;
    }
    private void Refresh()
    {
        list.ItemsSource = session.TrashRecords()
            .Select(item => new GearChoice(item.Id!, item.Name, item.Category))
            .ToList();
    }
    private string[] Ids() => list.SelectedItems.Cast<GearChoice>().Select(x => x.Id).ToArray();
    private void Act(bool trash)
    {
        var ids = Ids();
        if (ids.Length == 0)
            return;
        session.Trash(ids, trash);
        Refresh();
    }
    private void Delete()
    {
        var ids = Ids();
        if (ids.Length == 0)
            return;
        if (!ConfirmPermanentDeletion())
            return;
        session.DeletePermanently(ids);
        Refresh();
    }
    private bool ConfirmPermanentDeletion()
    {
        return MessageBox.Show(
            "永久删除所选装备及其子装备？此操作不可撤销。",
            "确认删除",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning) == MessageBoxResult.Yes;
    }
}
