param(
    [string]$ExePath = (Join-Path $PSScriptRoot 'mini-task-manager.exe'),
    [string]$IcoPath = (Join-Path $PSScriptRoot 'icon.ico')
)

Add-Type @"
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class IconResource {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr BeginUpdateResourceW(string fileName, bool deleteExistingResources);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool UpdateResourceW(IntPtr hUpdate, IntPtr type, IntPtr name, ushort language, byte[] data, uint size);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool EndUpdateResourceW(IntPtr hUpdate, bool discard);

    public static void Embed(string exePath, string icoPath) {
        byte[] ico = File.ReadAllBytes(icoPath);
        if (ico.Length < 6 || BitConverter.ToUInt16(ico, 0) != 0 || BitConverter.ToUInt16(ico, 2) != 1)
            throw new InvalidDataException("Invalid ICO file");

        int count = BitConverter.ToUInt16(ico, 4);
        if (count <= 0)
            throw new InvalidDataException("ICO contains no images");

        IntPtr update = BeginUpdateResourceW(exePath, false);
        if (update == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "BeginUpdateResourceW failed");

        bool committed = false;
        try {
            using (MemoryStream groupStream = new MemoryStream()) {
                using (BinaryWriter group = new BinaryWriter(groupStream)) {
                    group.Write((ushort)0);
                    group.Write((ushort)1);
                    group.Write((ushort)count);

                    for (int i = 0; i < count; i++) {
                        int offset = 6 + i * 16;
                        byte width = ico[offset];
                        byte height = ico[offset + 1];
                        byte colors = ico[offset + 2];
                        byte reserved = ico[offset + 3];
                        ushort planes = BitConverter.ToUInt16(ico, offset + 4);
                        ushort bits = BitConverter.ToUInt16(ico, offset + 6);
                        uint imageSize = BitConverter.ToUInt32(ico, offset + 8);
                        uint imageOffset = BitConverter.ToUInt32(ico, offset + 12);

                        if ((long)imageOffset + imageSize > ico.Length)
                            throw new InvalidDataException("Invalid ICO image entry");

                        byte[] image = new byte[imageSize];
                        Array.Copy(ico, imageOffset, image, 0, imageSize);

                        ushort id = (ushort)(i + 1);
                        if (!UpdateResourceW(update, (IntPtr)3, (IntPtr)id, 0, image, imageSize))
                            throw new Win32Exception(Marshal.GetLastWin32Error(), "UpdateResourceW failed for icon " + id);

                        group.Write(width);
                        group.Write(height);
                        group.Write(colors);
                        group.Write(reserved);
                        group.Write(planes);
                        group.Write(bits);
                        group.Write(imageSize);
                        group.Write(id);
                    }
                }

                byte[] groupData = groupStream.ToArray();
                if (!UpdateResourceW(update, (IntPtr)14, (IntPtr)1, 0, groupData, (uint)groupData.Length))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "UpdateResourceW failed for icon group");
            }

            if (!EndUpdateResourceW(update, false))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "EndUpdateResourceW failed");
            committed = true;
        } finally {
            if (!committed)
                EndUpdateResourceW(update, true);
        }
    }
}
"@

if (-not (Test-Path -LiteralPath $ExePath)) { throw "Executable not found: $ExePath" }
if (-not (Test-Path -LiteralPath $IcoPath)) { throw "Icon not found: $IcoPath" }

[IconResource]::Embed((Resolve-Path -LiteralPath $ExePath).Path, (Resolve-Path -LiteralPath $IcoPath).Path)
Write-Output ("Embedded {0} into {1}" -f (Split-Path $IcoPath -Leaf), (Split-Path $ExePath -Leaf))
