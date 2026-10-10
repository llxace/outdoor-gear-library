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

public sealed record GearChoice(string Id, string Name, string Category) { public override string ToString() => $"{Name}   ·   {Category}"; }
internal sealed record GearParentChoice(string? Id, string Name);
internal sealed record GearUserChoice(string Id, string Name);
