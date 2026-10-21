# TestPng.ps1 - a PNG writer for the tests, kept apart from the module's
# reader so a mistake in one does not hide in the other: every colour type
# and bit depth, each of the five row filters, Adam7 interlacing, and the
# image data split over two IDAT chunks. Its CRC goes bit by bit, with no
# table. Dot-sourced by ImageArt.Tests.ps1.

if (-not ('UsaBannerTests.TestPng' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace UsaBannerTests
{
    public static class TestPng
    {
        public static uint Crc(byte[] data, int offset, int count)
        {
            uint crc = 0xFFFFFFFF;
            for (int i = offset; i < offset + count; i++)
            {
                crc ^= data[i];
                for (int k = 0; k < 8; k++) crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
            }
            return ~crc;
        }

        // samples: each pixel's channels for its colour type, in order (grey; R G B; index;
        // grey alpha; R G B A), row by row. filter: 0 to 4 for every row, or -1 for row number mod 5.
        public static byte[] Write(int width, int height, int colorType, int depth, int[] samples,
            byte[] palette, byte[] paletteAlpha, int[] key, bool interlace, int filter)
        {
            int channels = colorType == 2 ? 3 : colorType == 4 ? 2 : colorType == 6 ? 4 : 1;
            var raw = new MemoryStream();
            if (!interlace) WritePass(raw, samples, width, height, channels, depth, 0, 0, 1, 1, filter);
            else
            {
                // Adam7, from the specification's figure: starting column, starting row, step across, step down.
                int[][] passes = {
                    new[] { 0, 0, 8, 8 }, new[] { 4, 0, 8, 8 }, new[] { 0, 4, 4, 8 }, new[] { 2, 0, 4, 4 },
                    new[] { 0, 2, 2, 4 }, new[] { 1, 0, 2, 2 }, new[] { 0, 1, 1, 2 } };
                foreach (int[] p in passes) WritePass(raw, samples, width, height, channels, depth, p[0], p[1], p[2], p[3], filter);
            }
            var packed = new MemoryStream();
            using (var z = new ZLibStream(packed, CompressionLevel.Optimal, true)) raw.WriteTo(z);
            byte[] idat = packed.ToArray();

            var file = new MemoryStream();
            file.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, 0, 8);
            var header = new byte[13];
            Put32(header, 0, (uint)width);
            Put32(header, 4, (uint)height);
            header[8] = (byte)depth;
            header[9] = (byte)colorType;
            header[12] = (byte)(interlace ? 1 : 0);
            Chunk(file, "IHDR", header);
            if (palette != null) Chunk(file, "PLTE", palette);
            if (paletteAlpha != null) Chunk(file, "tRNS", paletteAlpha);
            if (key != null)
            {
                var trns = new byte[key.Length * 2];
                for (int i = 0; i < key.Length; i++)
                {
                    trns[2 * i] = (byte)(key[i] >> 8);
                    trns[2 * i + 1] = (byte)key[i];
                }
                Chunk(file, "tRNS", trns);
            }
            int half = idat.Length / 2;
            Chunk(file, "IDAT", Slice(idat, 0, half));
            Chunk(file, "IDAT", Slice(idat, half, idat.Length - half));
            Chunk(file, "IEND", new byte[0]);
            return file.ToArray();
        }

        static void WritePass(MemoryStream raw, int[] samples, int width, int height, int channels, int depth,
            int x0, int y0, int dx, int dy, int filter)
        {
            var xs = new List<int>();
            for (int x = x0; x < width; x += dx) xs.Add(x);
            var ys = new List<int>();
            for (int y = y0; y < height; y += dy) ys.Add(y);
            if (xs.Count == 0 || ys.Count == 0) return;
            int bitsPerPixel = channels * depth;
            int rowBytes = (xs.Count * bitsPerPixel + 7) / 8;
            int left = Math.Max(1, bitsPerPixel / 8);
            var prior = new byte[rowBytes];
            for (int r = 0; r < ys.Count; r++)
            {
                var row = new byte[rowBytes];
                int bit = 0;
                foreach (int x in xs)
                    for (int c = 0; c < channels; c++)
                    {
                        int v = samples[(ys[r] * width + x) * channels + c];
                        if (depth == 16)
                        {
                            row[bit / 8] = (byte)(v >> 8);
                            row[bit / 8 + 1] = (byte)(v & 255);
                        }
                        else if (depth == 8) row[bit / 8] = (byte)v;
                        else row[bit / 8] |= (byte)(v << (8 - depth - bit % 8));
                        bit += depth;
                    }
                int f = filter >= 0 ? filter : r % 5;
                raw.WriteByte((byte)f);
                for (int i = 0; i < rowBytes; i++)
                {
                    int a = i >= left ? row[i - left] : 0, b = prior[i], c = i >= left ? prior[i - left] : 0;
                    int guess;
                    if (f == 0) guess = 0;
                    else if (f == 1) guess = a;
                    else if (f == 2) guess = b;
                    else if (f == 3) guess = (a + b) / 2;
                    else
                    {
                        int p = a + b - c, pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c);
                        guess = pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
                    }
                    raw.WriteByte((byte)((row[i] - guess) & 255));
                }
                prior = row;
            }
        }

        static void Chunk(MemoryStream file, string type, byte[] data)
        {
            var body = new byte[4 + data.Length];
            Encoding.ASCII.GetBytes(type, 0, 4, body, 0);
            Buffer.BlockCopy(data, 0, body, 4, data.Length);
            var length = new byte[4];
            Put32(length, 0, (uint)data.Length);
            file.Write(length, 0, 4);
            file.Write(body, 0, body.Length);
            var crc = new byte[4];
            Put32(crc, 0, Crc(body, 0, body.Length));
            file.Write(crc, 0, 4);
        }

        static void Put32(byte[] bytes, int at, uint value)
        {
            bytes[at] = (byte)(value >> 24);
            bytes[at + 1] = (byte)(value >> 16);
            bytes[at + 2] = (byte)(value >> 8);
            bytes[at + 3] = (byte)value;
        }

        static byte[] Slice(byte[] bytes, int start, int count)
        {
            var part = new byte[count];
            Buffer.BlockCopy(bytes, start, part, 0, count);
            return part;
        }
    }
}
'@
}

function New-TestPng {
    # In:  an RGBA picture (width, height, and 4 bytes a pixel), where to write it, and how: a colour
    #      type and bit depth, interlaced or not, and the row filter (-1: each in turn)
    # Out: nothing; the PNG file at Path. RGB types take the picture's R, G and B; grey types its R;
    #      palette types a palette of its colours, with a tRNS chunk when any is not opaque
    # Why: the tests draw pictures as RGBA, whatever format they store them in
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height,
        [Parameter(Mandatory)][byte[]]$Rgba,
        [Parameter(Mandatory)][string]$Path,
        [int]$ColorType = 6,
        [int]$Depth = 8,
        [switch]$Interlace,
        [int]$Filter = -1
    )
    $channels = switch ($ColorType) { 0 { 1 } 2 { 3 } 3 { 1 } 4 { 2 } 6 { 4 } }
    $samples = [int[]]::new($Width * $Height * $channels)
    $palette = $null
    $paletteAlpha = $null
    $scale = {
        # In:  an 8-bit value
        # Out: the same value at the PNG's bit depth
        # Why: 16-bit repeats the byte (0xAB -> 0xABAB); fewer bits keep the high ones
        param([int]$Value)
        if ($Depth -eq 16) { return $Value * 257 }
        $Value -shr (8 - $Depth)
    }
    if ($ColorType -eq 3) {
        $index = @{}
        $colours = [System.Collections.Generic.List[int]]::new()
        for ($i = 0; $i -lt $Width * $Height; $i++) {
            $rgbaKey = [BitConverter]::ToInt32($Rgba, 4 * $i)
            if (-not $index.ContainsKey($rgbaKey)) {
                $index[$rgbaKey] = $colours.Count
                $colours.Add($rgbaKey)
            }
            $samples[$i] = $index[$rgbaKey]
        }
        if ($colours.Count -gt [Math]::Pow(2, $Depth)) { throw "TestPng: $($colours.Count) colours do not fit $Depth bits." }
        $palette = [byte[]]::new(3 * $colours.Count)
        $alpha = [byte[]]::new($colours.Count)
        for ($c = 0; $c -lt $colours.Count; $c++) {
            $bytes = [BitConverter]::GetBytes($colours[$c])
            $palette[3 * $c] = $bytes[0]
            $palette[3 * $c + 1] = $bytes[1]
            $palette[3 * $c + 2] = $bytes[2]
            $alpha[$c] = $bytes[3]
        }
        if (@($alpha | Where-Object { $_ -ne 255 }).Count -gt 0) { $paletteAlpha = $alpha }
    }
    else {
        for ($i = 0; $i -lt $Width * $Height; $i++) {
            $r = $Rgba[4 * $i]; $g = $Rgba[4 * $i + 1]; $b = $Rgba[4 * $i + 2]; $a = $Rgba[4 * $i + 3]
            $values = switch ($ColorType) { 0 { , @($r) } 2 { , @($r, $g, $b) } 4 { , @($r, $a) } 6 { , @($r, $g, $b, $a) } }
            for ($c = 0; $c -lt $channels; $c++) { $samples[$i * $channels + $c] = & $scale $values[$c] }
        }
    }
    $bytes = [UsaBannerTests.TestPng]::Write($Width, $Height, $ColorType, $Depth, $samples, $palette, $paletteAlpha, $null, [bool]$Interlace, $Filter)
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function New-TestPicture {
    # In:  a width and height, and a script block giving each pixel's [r, g, b, a] from its x and y
    # Out: the picture as RGBA bytes
    # Why: the tests draw their pictures from shapes
    param([int]$Width, [int]$Height, [scriptblock]$Pixel)
    $rgba = [byte[]]::new($Width * $Height * 4)
    for ($y = 0; $y -lt $Height; $y++) {
        for ($x = 0; $x -lt $Width; $x++) {
            $p = & $Pixel $x $y
            $at = 4 * ($y * $Width + $x)
            for ($c = 0; $c -lt 4; $c++) { $rgba[$at + $c] = $p[$c] }
        }
    }
    , $rgba
}
