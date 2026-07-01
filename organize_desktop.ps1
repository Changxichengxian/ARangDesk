param(
    [int]$MarginX = 18,
    [int]$MarginY = 18,
    [switch]$Preview,
    [switch]$ShowCurrent,
    [switch]$WaitForUndo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-UnicodeEscapes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    [regex]::Replace(
        $Value,
        '\\u([0-9A-Fa-f]{4})',
        {
            param($Match)
            [string][char][Convert]::ToInt32($Match.Groups[1].Value, 16)
        }
    )
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA) {
    throw "This script must run in STA mode. Use the provided .cmd launcher."
}

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

public static class DesktopArrangeApi
{
    private const int SWC_DESKTOP = 0x8;
    private const int SWFO_NEEDDISPATCH = 0x1;
    private const uint SVGIO_ALLVIEW = 0x2;
    private const uint SVSI_POSITIONITEM = 0x80;
    private const uint SVSI_SELECT = 0x1;
    private const uint SVSI_DESELECTOTHERS = 0x4;
    private const uint SVSI_ENSUREVISIBLE = 0x8;
    private const uint SVSI_FOCUSED = 0x10;
    private const uint SFGAO_LINK = 0x00010000;
    private const uint SFGAO_FOLDER = 0x20000000;
    private const uint SPI_GETWORKAREA = 0x0030;
    private const int SM_XVIRTUALSCREEN = 76;
    private const int SM_YVIRTUALSCREEN = 77;
    private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

    private static readonly Guid CLSID_ShellWindows = new Guid("9BA05972-F6A8-11CF-A442-00A0C90A8F39");
    private static readonly Guid SID_STopLevelBrowser = new Guid("4C96BE40-915C-11CF-99D3-00AA004AE837");
    private static readonly Guid IID_IShellBrowser = new Guid("000214E2-0000-0000-C000-000000000046");
    private static readonly Guid IID_IShellFolder = new Guid("000214E6-0000-0000-C000-000000000046");
    private static readonly Guid IID_IShellItem = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public sealed class PreviewEntry
    {
        public int Index { get; set; }
        public string Name { get; set; }
        public string Group { get; set; }
        public int X { get; set; }
        public int Y { get; set; }
    }

    public sealed class WorkAreaInfo
    {
        public int Left { get; set; }
        public int Top { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    public sealed class LayoutState
    {
        private IntPtr[] pidls;
        private POINT[] points;

        internal LayoutState(IntPtr[] pidls, POINT[] points)
        {
            this.pidls = pidls;
            this.points = points;
        }

        internal IntPtr[] Pidls
        {
            get { return pidls; }
        }

        internal POINT[] Points
        {
            get { return points; }
        }

        public int Count
        {
            get { return pidls == null ? 0 : pidls.Length; }
        }

        public void Free()
        {
            if (pidls == null)
            {
                return;
            }

            FreePidlArray(pidls);
            pidls = null;
            points = null;
        }
    }

    private sealed class DesktopItem
    {
        public IntPtr Pidl;
        public int Index;
        public string Name;
        public int Category;
    }

    [ComImport]
    [Guid("6d5140c1-7436-11ce-8034-00aa006009fa")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IServiceProvider
    {
        [PreserveSig]
        int QueryService(
            ref Guid guidService,
            ref Guid riid,
            [MarshalAs(UnmanagedType.Interface)] out object ppvObject
        );
    }

    [ComImport]
    [Guid("00000114-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IOleWindow
    {
        [PreserveSig]
        int GetWindow(out IntPtr phwnd);

        [PreserveSig]
        int ContextSensitiveHelp([MarshalAs(UnmanagedType.Bool)] bool fEnterMode);
    }

    [ComImport]
    [Guid("000214E2-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellBrowser : IOleWindow
    {
        [PreserveSig]
        new int GetWindow(out IntPtr phwnd);

        [PreserveSig]
        new int ContextSensitiveHelp([MarshalAs(UnmanagedType.Bool)] bool fEnterMode);

        [PreserveSig]
        int InsertMenusSB(IntPtr hmenuShared, IntPtr lpMenuWidths);

        [PreserveSig]
        int SetMenuSB(IntPtr hmenuShared, IntPtr holemenuRes, IntPtr hwndActiveObject);

        [PreserveSig]
        int RemoveMenusSB(IntPtr hmenuShared);

        [PreserveSig]
        int SetStatusTextSB([MarshalAs(UnmanagedType.LPWStr)] string pszStatusText);

        [PreserveSig]
        int EnableModelessSB([MarshalAs(UnmanagedType.Bool)] bool fEnable);

        [PreserveSig]
        int TranslateAcceleratorSB(IntPtr pmsg, ushort wID);

        [PreserveSig]
        int BrowseObject(IntPtr pidl, uint wFlags);

        [PreserveSig]
        int GetViewStateStream(uint grfMode, out IntPtr ppStrm);

        [PreserveSig]
        int GetControlWindow(uint id, out IntPtr phwnd);

        [PreserveSig]
        int SendControlMsg(uint id, uint uMsg, IntPtr wParam, IntPtr lParam, out IntPtr pret);

        [PreserveSig]
        int QueryActiveShellView([MarshalAs(UnmanagedType.Interface)] out object ppshv);
    }

    [ComImport]
    [Guid("000214E6-0000-0000-C000-000000000046")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellFolder
    {
        [PreserveSig]
        int ParseDisplayName(
            IntPtr hwnd,
            IntPtr pbc,
            [MarshalAs(UnmanagedType.LPWStr)] string pszDisplayName,
            ref uint pchEaten,
            out IntPtr ppidl,
            ref uint pdwAttributes
        );

        [PreserveSig]
        int EnumObjects(IntPtr hwnd, int grfFlags, out IntPtr ppenumIDList);

        [PreserveSig]
        int BindToObject(IntPtr pidl, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);

        [PreserveSig]
        int BindToStorage(IntPtr pidl, IntPtr pbc, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);

        [PreserveSig]
        int CompareIDs(int lParam, IntPtr pidl1, IntPtr pidl2);

        [PreserveSig]
        int CreateViewObject(IntPtr hwndOwner, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);

        [PreserveSig]
        int GetAttributesOf(
            uint cidl,
            [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] IntPtr[] apidl,
            ref uint rgfInOut
        );

        [PreserveSig]
        int GetUIObjectOf(
            IntPtr hwndOwner,
            uint cidl,
            [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] IntPtr[] apidl,
            ref Guid riid,
            IntPtr rgfReserved,
            [MarshalAs(UnmanagedType.Interface)] out object ppv
        );
    }

    [ComImport]
    [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        [PreserveSig]
        int BindToHandler(IntPtr pbc, ref Guid bhid, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);

        [PreserveSig]
        int GetParent([MarshalAs(UnmanagedType.Interface)] out object ppsi);

        [PreserveSig]
        int GetDisplayName(uint sigdnName, out IntPtr ppszName);

        [PreserveSig]
        int GetAttributes(uint sfgaoMask, out uint psfgaoAttribs);

        [PreserveSig]
        int Compare([MarshalAs(UnmanagedType.Interface)] IShellItem psi, uint hint, out int piOrder);
    }

    [ComImport]
    [Guid("cde725b0-ccc9-4519-917e-325d72fab4ce")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFolderView
    {
        [PreserveSig]
        int GetCurrentViewMode(out uint pViewMode);

        [PreserveSig]
        int SetCurrentViewMode(uint viewMode);

        [PreserveSig]
        int GetFolder(ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);

        [PreserveSig]
        int Item(int iItemIndex, out IntPtr ppidl);

        [PreserveSig]
        int ItemCount(uint uFlags, out int pcItems);

        [PreserveSig]
        int Items(uint uFlags, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object ppv);

        [PreserveSig]
        int GetSelectionMarkedItem(out int piItem);

        [PreserveSig]
        int GetFocusedItem(out int piItem);

        [PreserveSig]
        int GetItemPosition(IntPtr pidl, out POINT ppt);

        [PreserveSig]
        int GetSpacing(ref POINT ppt);

        [PreserveSig]
        int GetDefaultSpacing(out POINT ppt);

        [PreserveSig]
        int GetAutoArrange();

        [PreserveSig]
        int SelectItem(int iItem, uint dwFlags);

        [PreserveSig]
        int SelectAndPositionItems(
            uint cidl,
            [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] IntPtr[] apidl,
            [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] POINT[] apt,
            uint dwFlags
        );
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetClientRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, out RECT pvParam, uint fWinIni);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int nIndex);

    [DllImport("shell32.dll")]
    private static extern int SHCreateItemWithParent(
        IntPtr pidlParent,
        [MarshalAs(UnmanagedType.Interface)] IShellFolder psfParent,
        IntPtr pidl,
        ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out object ppvItem
    );

    [DllImport("ole32.dll")]
    private static extern void CoTaskMemFree(IntPtr pv);

    public static void EnablePerMonitorDpiAware()
    {
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    }

    public static WorkAreaInfo GetPrimaryWorkArea()
    {
        RECT workArea;
        if (!SystemParametersInfo(SPI_GETWORKAREA, 0, out workArea, 0))
        {
            throw new InvalidOperationException("Failed to get the primary monitor work area.");
        }

        int virtualLeft = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int virtualTop = GetSystemMetrics(SM_YVIRTUALSCREEN);

        return new WorkAreaInfo
        {
            Left = workArea.Left - virtualLeft,
            Top = workArea.Top - virtualTop,
            Width = Math.Max(1, workArea.Right - workArea.Left),
            Height = Math.Max(1, workArea.Bottom - workArea.Top)
        };
    }

    public static bool IsAutoArrangeEnabled()
    {
        object shellViewObject = null;
        object folderObject = null;
        IntPtr desktopWindowHandle = IntPtr.Zero;
        try
        {
            IFolderView folderView = GetDesktopFolderView(out shellViewObject, out desktopWindowHandle);
            int autoArrange = folderView.GetAutoArrange();
            if (autoArrange < 0)
            {
                ThrowIfFailed(autoArrange, "Failed to query desktop auto-arrange state.");
            }

            return autoArrange == 0;
        }
        finally
        {
            ReleaseComObject(folderObject);
            ReleaseComObject(shellViewObject);
        }
    }

    public static PreviewEntry[] PreviewArrangement(
        int workAreaLeft,
        int workAreaTop,
        int workAreaWidth,
        int workAreaHeight,
        int marginX,
        int marginY
    )
    {
        object shellViewObject = null;
        object folderObject = null;
        List<DesktopItem> items = null;
        IntPtr desktopWindowHandle = IntPtr.Zero;

        try
        {
            IFolderView folderView = GetDesktopFolderView(out shellViewObject, out desktopWindowHandle);
            folderObject = GetShellFolderObject(folderView);
            IShellFolder shellFolder = (IShellFolder)folderObject;
            items = CollectDesktopItems(folderView, shellFolder);
            POINT[] ignoredPoints;
            IntPtr[] ignoredPidls;
            return BuildPreviewEntries(
                folderView,
                items,
                workAreaLeft,
                workAreaTop,
                workAreaWidth,
                workAreaHeight,
                marginX,
                marginY,
                out ignoredPoints,
                out ignoredPidls
            );
        }
        finally
        {
            FreePidls(items);
            ReleaseComObject(folderObject);
            ReleaseComObject(shellViewObject);
        }
    }

    public static PreviewEntry[] GetCurrentLayout()
    {
        object shellViewObject = null;
        object folderObject = null;
        List<DesktopItem> items = null;
        IntPtr desktopWindowHandle = IntPtr.Zero;

        try
        {
            IFolderView folderView = GetDesktopFolderView(out shellViewObject, out desktopWindowHandle);
            folderObject = GetShellFolderObject(folderView);
            IShellFolder shellFolder = (IShellFolder)folderObject;
            items = CollectDesktopItems(folderView, shellFolder);

            var current = new PreviewEntry[items.Count];
            for (int i = 0; i < items.Count; i++)
            {
                POINT position;
                ThrowIfFailed(
                    folderView.GetItemPosition(items[i].Pidl, out position),
                    "Failed to read the current position of a desktop item."
                );

                current[i] = new PreviewEntry
                {
                    Index = items[i].Index,
                    Name = items[i].Name,
                    Group = GetCategoryLabel(items[i].Category),
                    X = position.X,
                    Y = position.Y
                };
            }

            return current;
        }
        finally
        {
            FreePidls(items);
            ReleaseComObject(folderObject);
            ReleaseComObject(shellViewObject);
        }
    }

    public static LayoutState CaptureCurrentLayoutState()
    {
        object shellViewObject = null;
        object folderObject = null;
        List<DesktopItem> items = null;
        IntPtr[] pidls = null;
        POINT[] points = null;
        bool transferred = false;
        IntPtr desktopWindowHandle = IntPtr.Zero;

        try
        {
            IFolderView folderView = GetDesktopFolderView(out shellViewObject, out desktopWindowHandle);
            folderObject = GetShellFolderObject(folderView);
            IShellFolder shellFolder = (IShellFolder)folderObject;
            items = CollectDesktopItems(folderView, shellFolder);

            pidls = new IntPtr[items.Count];
            points = new POINT[items.Count];

            for (int i = 0; i < items.Count; i++)
            {
                POINT position;
                ThrowIfFailed(
                    folderView.GetItemPosition(items[i].Pidl, out position),
                    "Failed to read the current position of a desktop item."
                );

                pidls[i] = items[i].Pidl;
                points[i] = position;
                items[i].Pidl = IntPtr.Zero;
            }

            transferred = true;
            return new LayoutState(pidls, points);
        }
        finally
        {
            if (!transferred && pidls != null)
            {
                FreePidlArray(pidls);
            }

            FreePidls(items);
            ReleaseComObject(folderObject);
            ReleaseComObject(shellViewObject);
        }
    }

    public static void RestoreLayout(LayoutState layout)
    {
        if (layout == null || layout.Count == 0)
        {
            return;
        }

        object shellViewObject = null;
        IntPtr desktopWindowHandle = IntPtr.Zero;

        try
        {
            IFolderView folderView = GetDesktopFolderView(out shellViewObject, out desktopWindowHandle);
            ThrowIfFailed(
                folderView.SelectAndPositionItems((uint)layout.Count, layout.Pidls, layout.Points, SVSI_POSITIONITEM),
                "Failed to restore desktop icons."
            );
        }
        finally
        {
            ReleaseComObject(shellViewObject);
        }
    }

    public static void Arrange(
        int workAreaLeft,
        int workAreaTop,
        int workAreaWidth,
        int workAreaHeight,
        int marginX,
        int marginY
    )
    {
        object shellViewObject = null;
        object folderObject = null;
        List<DesktopItem> items = null;
        IntPtr desktopWindowHandle = IntPtr.Zero;

        try
        {
            IFolderView folderView = GetDesktopFolderView(out shellViewObject, out desktopWindowHandle);
            int autoArrange = folderView.GetAutoArrange();
            if (autoArrange == 0)
            {
                throw new InvalidOperationException("Desktop auto-arrange is enabled. Turn it off first.");
            }
            if (autoArrange < 0)
            {
                ThrowIfFailed(autoArrange, "Failed to query desktop auto-arrange state.");
            }

            folderObject = GetShellFolderObject(folderView);
            IShellFolder shellFolder = (IShellFolder)folderObject;
            items = CollectDesktopItems(folderView, shellFolder);

            POINT[] points;
            IntPtr[] pidls;
            BuildPreviewEntries(
                folderView,
                items,
                workAreaLeft,
                workAreaTop,
                workAreaWidth,
                workAreaHeight,
                marginX,
                marginY,
                out points,
                out pidls
            );
            ThrowIfFailed(
                folderView.SelectAndPositionItems((uint)pidls.Length, pidls, points, SVSI_POSITIONITEM),
                "Failed to move desktop icons."
            );

            if (items.Count > 0)
            {
                ThrowIfFailed(
                    folderView.SelectItem(
                        items[0].Index,
                        SVSI_SELECT | SVSI_DESELECTOTHERS | SVSI_ENSUREVISIBLE | SVSI_FOCUSED
                    ),
                    "Failed to bring the first arranged desktop item into view."
                );
            }
        }
        finally
        {
            FreePidls(items);
            ReleaseComObject(folderObject);
            ReleaseComObject(shellViewObject);
        }
    }

    private static IFolderView GetDesktopFolderView(out object shellViewObject, out IntPtr desktopWindowHandle)
    {
        object shellWindowsObject = null;
        object dispatchObject = null;
        object browserObject = null;
        shellViewObject = null;
        desktopWindowHandle = IntPtr.Zero;

        try
        {
            Type shellWindowsType = Type.GetTypeFromCLSID(CLSID_ShellWindows, true);
            shellWindowsObject = Activator.CreateInstance(shellWindowsType);

            object[] arguments = new object[] { 0, null, SWC_DESKTOP, 0, SWFO_NEEDDISPATCH };
            dispatchObject = shellWindowsType.InvokeMember(
                "FindWindowSW",
                BindingFlags.InvokeMethod,
                null,
                shellWindowsObject,
                arguments
            );

            if (arguments[3] != null)
            {
                desktopWindowHandle = new IntPtr(Convert.ToInt64(arguments[3]));
            }

            if (dispatchObject == null)
            {
                throw new InvalidOperationException("Failed to access the desktop shell window.");
            }

            IServiceProvider serviceProvider = (IServiceProvider)dispatchObject;
            Guid sidTopLevelBrowser = SID_STopLevelBrowser;
            Guid iidShellBrowser = IID_IShellBrowser;
            ThrowIfFailed(
                serviceProvider.QueryService(ref sidTopLevelBrowser, ref iidShellBrowser, out browserObject),
                "Failed to get the top-level shell browser."
            );

            IShellBrowser shellBrowser = (IShellBrowser)browserObject;
            ThrowIfFailed(
                shellBrowser.QueryActiveShellView(out shellViewObject),
                "Failed to get the active desktop shell view."
            );

            if (shellViewObject == null)
            {
                throw new InvalidOperationException("Failed to get the desktop folder view.");
            }

            return (IFolderView)shellViewObject;
        }
        finally
        {
            ReleaseComObject(browserObject);
            ReleaseComObject(dispatchObject);
            ReleaseComObject(shellWindowsObject);
        }
    }

    private static object GetShellFolderObject(IFolderView folderView)
    {
        object folderObject;
        Guid iidShellFolder = IID_IShellFolder;
        ThrowIfFailed(
            folderView.GetFolder(ref iidShellFolder, out folderObject),
            "Failed to get the desktop shell folder."
        );

        return folderObject;
    }

    private static List<DesktopItem> CollectDesktopItems(IFolderView folderView, IShellFolder shellFolder)
    {
        int count;
        ThrowIfFailed(folderView.ItemCount(SVGIO_ALLVIEW, out count), "Failed to count desktop items.");

        var items = new List<DesktopItem>(Math.Max(count, 0));
        for (int index = 0; index < count; index++)
        {
            IntPtr pidl;
            ThrowIfFailed(folderView.Item(index, out pidl), "Failed to read a desktop item identifier.");

            string name = GetDisplayName(shellFolder, pidl);
            int category = GetCategory(shellFolder, pidl);

            items.Add(new DesktopItem
            {
                Pidl = pidl,
                Index = index,
                Name = name,
                Category = category
            });
        }

        return items;
    }

    private static PreviewEntry[] BuildPreviewEntries(
        IFolderView folderView,
        List<DesktopItem> items,
        int workAreaLeft,
        int workAreaTop,
        int workAreaWidth,
        int workAreaHeight,
        int marginX,
        int marginY,
        out POINT[] points,
        out IntPtr[] pidls
    )
    {
        var leftGroup = new List<DesktopItem>();
        var fileGroup = new List<DesktopItem>();

        foreach (DesktopItem item in items)
        {
            if (item.Category == 2)
            {
                fileGroup.Add(item);
            }
            else
            {
                leftGroup.Add(item);
            }
        }

        leftGroup.Sort(CompareLeftItems);

        fileGroup.Sort(
            delegate (DesktopItem left, DesktopItem right)
            {
                return StringComparer.CurrentCultureIgnoreCase.Compare(left.Name, right.Name);
            }
        );

        POINT spacing = GetEffectiveSpacing(folderView);
        int spacingY = Math.Max(spacing.Y, 1);
        int spacingX = Math.Max(spacing.X, 1);
        int usableHeight = Math.Max(spacingY, workAreaHeight - marginY);
        int rowsPerColumn = Math.Max(1, ((usableHeight - 1) / spacingY) + 1);
        int totalColumns = Math.Max(1, ((Math.Max(0, workAreaWidth - (marginX * 2))) / Math.Max(spacing.X, 1)) + 1);

        points = new POINT[items.Count];
        pidls = new IntPtr[items.Count];
        var preview = new PreviewEntry[items.Count];
        int outputIndex = 0;

        for (int i = 0; i < leftGroup.Count; i++)
        {
            int column = i / rowsPerColumn;
            int row = i % rowsPerColumn;
            int x = workAreaLeft + marginX + (column * spacingX);
            int y = workAreaTop + marginY + (row * spacingY);

            points[outputIndex] = new POINT { X = x, Y = y };
            pidls[outputIndex] = leftGroup[i].Pidl;
            preview[outputIndex] = new PreviewEntry
            {
                Index = leftGroup[i].Index,
                Name = leftGroup[i].Name,
                Group = GetCategoryLabel(leftGroup[i].Category),
                X = x,
                Y = y
            };

            outputIndex++;
        }

        for (int i = 0; i < fileGroup.Count; i++)
        {
            int column = (totalColumns - 1) - (i / rowsPerColumn);
            int row = i % rowsPerColumn;
            int x = workAreaLeft + marginX + (column * spacingX);
            int y = workAreaTop + marginY + (row * spacingY);

            points[outputIndex] = new POINT { X = x, Y = y };
            pidls[outputIndex] = fileGroup[i].Pidl;
            preview[outputIndex] = new PreviewEntry
            {
                Index = fileGroup[i].Index,
                Name = fileGroup[i].Name,
                Group = GetCategoryLabel(fileGroup[i].Category),
                X = x,
                Y = y
            };

            outputIndex++;
        }

        return preview;
    }

    private static int CompareLeftItems(DesktopItem left, DesktopItem right)
    {
        int leftBucket = GetLeftBucket(left);
        int rightBucket = GetLeftBucket(right);
        if (leftBucket != rightBucket)
        {
            return leftBucket.CompareTo(rightBucket);
        }

        int leftRank = GetPreferredRank(left, leftBucket);
        int rightRank = GetPreferredRank(right, rightBucket);
        if (leftRank != rightRank)
        {
            return leftRank.CompareTo(rightRank);
        }

        return StringComparer.CurrentCultureIgnoreCase.Compare(left.Name, right.Name);
    }

    private static int GetLeftBucket(DesktopItem item)
    {
        if (IsRecycleBin(item.Name))
        {
            return 0;
        }

        if (item.Category == 0)
        {
            return GetPreferredShortcutRank(item.Name) >= 0 ? 1 : 2;
        }

        if (item.Category == 1)
        {
            return GetPreferredFolderRank(item.Name) >= 0 ? 3 : 4;
        }

        return 5;
    }

    private static int GetPreferredRank(DesktopItem item, int bucket)
    {
        if (bucket == 1)
        {
            return GetPreferredShortcutRank(item.Name);
        }

        if (bucket == 3)
        {
            return GetPreferredFolderRank(item.Name);
        }

        return Int32.MaxValue;
    }

    private static int GetPreferredShortcutRank(string name)
    {
        if (MatchesName(name, "Microsoft Edge", "edge"))
        {
            return 0;
        }

        if (MatchesName(name, "\u7EFF\u8054\u4E91"))
        {
            return 1;
        }

        if (MatchesName(name, "Visual Studio Code", "vscode"))
        {
            return 2;
        }

        if (MatchesName(name, "QQ"))
        {
            return 3;
        }

        if (MatchesName(name, "\u5FAE\u4FE1"))
        {
            return 4;
        }

        return -1;
    }

    private static int GetPreferredFolderRank(string name)
    {
        if (MatchesName(name, "app"))
        {
            return 0;
        }

        if (MatchesName(name, "\u9879\u76EE\u96C6"))
        {
            return 1;
        }

        if (MatchesName(name, "ARBATOS", "ARBA-TOS"))
        {
            return 2;
        }

        if (MatchesName(name, "\u8BFE\u5802"))
        {
            return 3;
        }

        if (ContainsNormalized(name, "nofx"))
        {
            return 4;
        }

        return -1;
    }

    private static bool IsRecycleBin(string name)
    {
        return MatchesName(name, "\u56DE\u6536\u7AD9", "Recycle Bin");
    }

    private static bool MatchesName(string source, params string[] candidates)
    {
        string normalizedSource = NormalizeName(source);
        foreach (string candidate in candidates)
        {
            if (normalizedSource == NormalizeName(candidate))
            {
                return true;
            }
        }

        return false;
    }

    private static bool ContainsNormalized(string source, string token)
    {
        return NormalizeName(source).Contains(NormalizeName(token));
    }

    private static string NormalizeName(string value)
    {
        if (String.IsNullOrEmpty(value))
        {
            return String.Empty;
        }

        var builder = new StringBuilder(value.Length);
        foreach (char ch in value)
        {
            if (Char.IsLetterOrDigit(ch))
            {
                builder.Append(Char.ToLowerInvariant(ch));
            }
        }

        return builder.ToString();
    }

    private static POINT GetEffectiveSpacing(IFolderView folderView)
    {
        POINT spacing = new POINT();
        int hr = folderView.GetSpacing(ref spacing);
        if (hr < 0)
        {
            ThrowIfFailed(hr, "Failed to read desktop icon spacing.");
        }

        if (spacing.X <= 0 || spacing.Y <= 0)
        {
            ThrowIfFailed(folderView.GetDefaultSpacing(out spacing), "Failed to read fallback desktop icon spacing.");
        }

        if (spacing.X <= 0)
        {
            spacing.X = 80;
        }

        if (spacing.Y <= 0)
        {
            spacing.Y = 100;
        }

        return spacing;
    }

    private static string GetDisplayName(IShellFolder shellFolder, IntPtr pidl)
    {
        object itemObject = null;
        Guid iidShellItem = IID_IShellItem;
        ThrowIfFailed(
            SHCreateItemWithParent(IntPtr.Zero, shellFolder, pidl, ref iidShellItem, out itemObject),
            "Failed to create a shell item from a desktop item."
        );

        try
        {
            IShellItem shellItem = (IShellItem)itemObject;
            IntPtr namePointer;
            ThrowIfFailed(shellItem.GetDisplayName(0, out namePointer), "Failed to read a desktop item name.");

            try
            {
                return Marshal.PtrToStringUni(namePointer) ?? string.Empty;
            }
            finally
            {
                if (namePointer != IntPtr.Zero)
                {
                    CoTaskMemFree(namePointer);
                }
            }
        }
        finally
        {
            ReleaseComObject(itemObject);
        }
    }

    private static int GetCategory(IShellFolder shellFolder, IntPtr pidl)
    {
        object itemObject = null;
        Guid iidShellItem = IID_IShellItem;
        ThrowIfFailed(
            SHCreateItemWithParent(IntPtr.Zero, shellFolder, pidl, ref iidShellItem, out itemObject),
            "Failed to create a shell item from a desktop item."
        );

        uint attributes;
        try
        {
            IShellItem shellItem = (IShellItem)itemObject;
            ThrowIfFailed(
                shellItem.GetAttributes(SFGAO_LINK | SFGAO_FOLDER, out attributes),
                "Failed to read desktop item attributes."
            );
        }
        finally
        {
            ReleaseComObject(itemObject);
        }

        if ((attributes & SFGAO_LINK) != 0)
        {
            return 0;
        }

        if ((attributes & SFGAO_FOLDER) != 0)
        {
            return 1;
        }

        return 2;
    }

    private static string GetCategoryLabel(int category)
    {
        switch (category)
        {
            case 0:
                return "Shortcut";
            case 1:
                return "Folder";
            default:
                return "File";
        }
    }

    private static void FreePidls(List<DesktopItem> items)
    {
        if (items == null)
        {
            return;
        }

        foreach (DesktopItem item in items)
        {
            if (item != null && item.Pidl != IntPtr.Zero)
            {
                CoTaskMemFree(item.Pidl);
                item.Pidl = IntPtr.Zero;
            }
        }
    }

    private static void FreePidlArray(IntPtr[] pidls)
    {
        for (int i = 0; i < pidls.Length; i++)
        {
            if (pidls[i] != IntPtr.Zero)
            {
                CoTaskMemFree(pidls[i]);
                pidls[i] = IntPtr.Zero;
            }
        }
    }

    private static void ReleaseComObject(object value)
    {
        if (value != null && Marshal.IsComObject(value))
        {
            Marshal.ReleaseComObject(value);
        }
    }

    private static void ThrowIfFailed(int hr, string message)
    {
        if (hr >= 0)
        {
            return;
        }

        throw new COMException(message, hr);
    }
}
"@

[DesktopArrangeApi]::EnablePerMonitorDpiAware()
$primaryWorkArea = [DesktopArrangeApi]::GetPrimaryWorkArea()
$targetAreaLeft = $primaryWorkArea.Left
$targetAreaTop = $primaryWorkArea.Top
$targetAreaWidth = $primaryWorkArea.Width
$targetAreaHeight = $primaryWorkArea.Height

if ($Preview) {
    $previewItems = [DesktopArrangeApi]::PreviewArrangement(
        $targetAreaLeft,
        $targetAreaTop,
        $targetAreaWidth,
        $targetAreaHeight,
        $MarginX,
        $MarginY
    )

    Write-Host "Preview only. No desktop icons will be moved."
    Write-Host ""

    $previewItems |
        Select-Object `
            @{ Name = 'Index'; Expression = { $_.Index } }, `
            @{ Name = 'Name'; Expression = { $_.Name } }, `
            @{ Name = 'Group'; Expression = { $_.Group } }, `
            X,
            Y |
        Format-Table -AutoSize

    return
}

if ($ShowCurrent) {
    $currentItems = [DesktopArrangeApi]::GetCurrentLayout()

    $currentItems |
        Sort-Object X, Y, Name |
        Select-Object `
            @{ Name = 'Index'; Expression = { $_.Index } }, `
            @{ Name = 'Name'; Expression = { $_.Name } }, `
            @{ Name = 'Group'; Expression = { $_.Group } }, `
            X,
            Y |
        Format-Table -AutoSize

    return
}

if ([DesktopArrangeApi]::IsAutoArrangeEnabled()) {
    throw "Desktop auto-arrange is enabled. Right-click the desktop, open View, turn off Auto arrange icons, then run this script again."
}

$previousLayout = $null

try {
    if ($WaitForUndo) {
        $previousLayout = [DesktopArrangeApi]::CaptureCurrentLayoutState()
    }

    [DesktopArrangeApi]::Arrange(
        $targetAreaLeft,
        $targetAreaTop,
        $targetAreaWidth,
        $targetAreaHeight,
        $MarginX,
        $MarginY
    )

    if ($WaitForUndo) {
        Write-Host (ConvertFrom-UnicodeEscapes '\u672C\u6B21\u6574\u7406\u5DF2\u5B8C\u6210\u3002\u6309\u7A7A\u683C\u6216\u8005 Enter \u952E\u53D6\u6D88\u8FD9\u6B21\u66F4\u6539\uFF1B\u6309\u5176\u4ED6\u952E\u9000\u51FA\u3002')

        if (-not [Console]::IsInputRedirected) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Spacebar -or $key.Key -eq [ConsoleKey]::Enter) {
                [DesktopArrangeApi]::RestoreLayout($previousLayout)
                Write-Host (ConvertFrom-UnicodeEscapes '\u5DF2\u53D6\u6D88\u8FD9\u6B21\u66F4\u6539\uFF0C\u684C\u9762\u56FE\u6807\u4F4D\u7F6E\u5DF2\u8FD8\u539F\u3002')
                Start-Sleep -Milliseconds 800
            }
        }
    }
    else {
        Write-Host (ConvertFrom-UnicodeEscapes '\u672C\u6B21\u6574\u7406\u5DF2\u5B8C\u6210\u3002')
    }
}
finally {
    if ($null -ne $previousLayout) {
        $previousLayout.Free()
    }
}
