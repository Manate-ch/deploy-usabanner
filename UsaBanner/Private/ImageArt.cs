// ImageArt.cs - an image made into banner art, for New-UsaBannerArt.
// Private\ImageArt.ps1 compiles this with Add-Type the first time it is
// needed, not when the module loads: compiling takes a second or two. It is
// C# for speed: a 1500 x 1500 image is 2.25 million pixels, each visited
// several times. PowerShell makes two calls into it:
//
//   $image  = [UsaBanner.PngReader]::Decode($bytes, $maxPixels)
//   $result = [UsaBanner.ArtMaker]::Convert($image, $settings)
//
//   image file --> PngReader.Decode --> ImageRgba --> ArtMaker.Convert --> ArtResult
//
// PngReader reads PNG files itself, so a PNG makes the same art on every
// system (docs/DECISIONS.md, D19). ImageArt.ps1 hands other formats to
// System.Drawing on Windows, or to ImageMagick on Linux, which writes a PNG.
// docs/IMAGE-ART.md draws the steps below as a diagram.
//
// ArtMaker.Convert, step by step:
//
//   +---+-----------------+---------------------------------------------------+
//   | 1 | the background  | transparent pixels; else, when one colour holds   |
//   |   |                 | half the edge or more, the pixels of about that   |
//   |   |                 | colour the edge reaches (BorderColour, Flood)     |
//   | 2 | crop and size   | the picture's box; 40 columns by default; each    |
//   |   |                 | character cell read as 2 x 4 square dots, since   |
//   |   |                 | a cell is about twice as tall as it is wide       |
//   | 3 | colours         | median cut, then k-means, to at most N classes;   |
//   |   |                 | classes closer than MergeDistance become one. In  |
//   |   |                 | shape style, the blends anti-aliasing leaves and  |
//   |   |                 | the halos a JPEG leaves join a part (MergeBlends, |
//   |   |                 | MergeHalos), and the largest part the picture     |
//   |   |                 | encloses is the fill: a gap before login, solid   |
//   |   |                 | in colour (Enclosed)                              |
//   | 4 | dots            | how much of each class covers each dot (Spans)    |
//   | 5 | characters      | shape style, for logos: the character whose ink   |
//   |   |                 | pattern fits the cell's 8 dots best (BestFit);    |
//   |   |                 | ramp style, for photos: one by brightness         |
//   +---+-----------------+---------------------------------------------------+
//
// The C#, read as PowerShell:
//
//   +----------------------+--------------------------------------------------+
//   | static class, method | functions in a module, called as [Type]::Name()  |
//   | (byte)v, (int)v      | casts that TRUNCATE and WRAP: (byte)300 is 44    |
//   | 7 / 2, both ints     | 3, not 3.5: integer division drops the fraction  |
//   | c ? a : b            | if (c) { a } else { b }, as one expression       |
//   | out double t         | a second result, as [ref]$t                      |
//   | (a, b) => ...        | a scriptblock handed to a method                 |
//   | using (x) { }        | try { } finally { x.Dispose() }                  |
//   +----------------------+--------------------------------------------------+
//
// Bits: >> and << are -shr and -shl (r >> 3 is r / 8, rounded down). On
// numbers a single | or & is -bor or -band; || and && are -or and -and.
// A pixel is 4 bytes, R G B A, so the pixel at x, y is number
// i = y * width + x, and its bytes start at 4 * i.

using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace UsaBanner
{
    // An image as 8-bit RGBA, not premultiplied, row by row from the top.
    public sealed class ImageRgba
    {
        public readonly int Width;
        public readonly int Height;
        public readonly byte[] Pixels;

        public ImageRgba(int width, int height, byte[] pixels)
        {
            if (width < 1 || height < 1) throw new ArgumentException("an image needs a pixel at least");
            if (pixels == null || pixels.LongLength != (long)width * height * 4) throw new ArgumentException("an image needs four bytes for each pixel");
            Width = width;
            Height = height;
            Pixels = pixels;
        }

        // System.Drawing's Format32bppArgb lies in memory as B, G, R, A, its rows stride bytes apart.
        public static ImageRgba FromBgra(byte[] bgra, int width, int height, int stride)
        {
            var pixels = new byte[(long)width * height * 4];
            for (int y = 0; y < height; y++)
            {
                int from = y * stride, to = y * width * 4;
                for (int x = 0; x < width; x++, from += 4, to += 4)
                {
                    pixels[to] = bgra[from + 2];
                    pixels[to + 1] = bgra[from + 1];
                    pixels[to + 2] = bgra[from];
                    pixels[to + 3] = bgra[from + 3];
                }
            }
            return new ImageRgba(width, height, pixels);
        }
    }

    // Reads PNG (the W3C specification): colour types 0, 2, 3, 4 and 6 at every
    // bit depth each allows, Adam7 interlacing, and the PLTE and tRNS chunks.
    // Gamma and colour profiles are not applied: samples are taken as stored,
    // and a 16-bit sample by its high byte.
    public static class PngReader
    {
        // A PNG file is these 8 bytes (0x89, "PNG", CR LF, 0x1A, LF), then chunks, each
        // [length: 4 bytes][type: 4 letters][data][CRC: 4 bytes]. IHDR holds the size and the
        // format, PLTE a palette, tRNS transparency, IDAT the compressed picture (often split over
        // several IDATs), and IEND ends the file.
        static readonly byte[] Signature = { 137, 80, 78, 71, 13, 10, 26, 10 };
        // CRC-32, the checksum zip uses too: one entry per byte value, so each byte checked costs
        // one table lookup. A flipped bit anywhere in a chunk changes its CRC.
        static readonly uint[] CrcTable = MakeCrcTable();

        // Adam7: each pass's first column and row, and its steps across and down.
        static readonly int[] PassX = { 0, 4, 0, 2, 0, 1, 0 };
        static readonly int[] PassY = { 0, 0, 4, 0, 2, 0, 1 };
        static readonly int[] PassStepX = { 8, 8, 4, 4, 2, 2, 1 };
        static readonly int[] PassStepY = { 8, 8, 8, 4, 4, 2, 2 };

        static uint[] MakeCrcTable()
        {
            var table = new uint[256];
            for (uint n = 0; n < 256; n++)
            {
                uint c = n;
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                table[n] = c;
            }
            return table;
        }

        // The CRC-32 each chunk ends with, taken over its type and data.
        public static uint Crc32(byte[] data, int offset, int count)
        {
            uint c = 0xFFFFFFFFu;
            for (int i = offset; i < offset + count; i++) c = CrcTable[(c ^ data[i]) & 0xFF] ^ (c >> 8);
            return c ^ 0xFFFFFFFFu;
        }

        // 4 bytes as one number, most significant first, as PNG stores every number.
        static uint ReadUInt32(byte[] data, int at)
        {
            return ((uint)data[at] << 24) | ((uint)data[at + 1] << 16) | ((uint)data[at + 2] << 8) | data[at + 3];
        }

        static bool DepthAllowed(int colorType, int depth)
        {
            switch (colorType)
            {
                case 0: return depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16;
                case 3: return depth == 1 || depth == 2 || depth == 4 || depth == 8;
                case 2: case 4: case 6: return depth == 8 || depth == 16;
                default: return false;
            }
        }

        // The image in a PNG file's bytes. Throws FormatException, saying what is wrong, for a
        // file that is not a PNG, is damaged or cut short, or has more than maxPixels pixels.
        public static ImageRgba Decode(byte[] data, long maxPixels)
        {
            if (data == null || data.Length < Signature.Length) throw new FormatException("it is not a PNG file");
            for (int i = 0; i < Signature.Length; i++)
                if (data[i] != Signature[i]) throw new FormatException("it is not a PNG file");

            var layout = new Layout();
            int width = 0, height = 0, interlace = 0;
            bool haveHeader = false;
            var compressed = new MemoryStream();
            int at = Signature.Length;
            while (at + 12 <= data.Length)
            {
                uint length = ReadUInt32(data, at);
                if (length > (uint)(data.Length - at - 12)) throw new FormatException("it is cut short: a chunk runs past the end of the file");
                int size = (int)length, body = at + 8;
                string type = Encoding.ASCII.GetString(data, at + 4, 4);
                bool used = type == "IHDR" || type == "PLTE" || type == "tRNS" || type == "IDAT" || type == "IEND";
                if (used && Crc32(data, at + 4, size + 4) != ReadUInt32(data, body + size))
                    throw new FormatException("its " + type + " chunk fails its CRC check: the file is damaged");
                if (!haveHeader && type != "IHDR") throw new FormatException("it does not begin with a header (IHDR) chunk");
                if (type == "IEND") break;
                switch (type)
                {
                    case "IHDR":
                        if (size != 13) throw new FormatException("its header (IHDR) chunk is " + size + " bytes, not 13");
                        uint w = ReadUInt32(data, body), h = ReadUInt32(data, body + 4);
                        if (w == 0 || h == 0 || w > int.MaxValue || h > int.MaxValue) throw new FormatException("it says it is " + w + " x " + h + " pixels");
                        width = (int)w;
                        height = (int)h;
                        layout.Depth = data[body + 8];
                        layout.ColorType = data[body + 9];
                        interlace = data[body + 12];
                        if (!DepthAllowed(layout.ColorType, layout.Depth)) throw new FormatException("colour type " + layout.ColorType + " at " + layout.Depth + " bits is not a PNG combination");
                        if (data[body + 10] != 0 || data[body + 11] != 0) throw new FormatException("it names a compression or filter method PNG does not have");
                        if (interlace > 1) throw new FormatException("it names interlace method " + interlace + ", which PNG does not have");
                        if ((long)width * height > maxPixels)
                        {
                            string most = maxPixels % 1000000 == 0 ? maxPixels / 1000000 + " million" : maxPixels.ToString();
                            throw new FormatException("it is " + width + " x " + height + " pixels, more than the " + most + " UsaBanner reads; make it smaller first");
                        }
                        haveHeader = true;
                        break;
                    case "PLTE":
                        if (size == 0 || size % 3 != 0 || size > 768) throw new FormatException("its palette (PLTE) chunk is " + size + " bytes, not 1 to 256 colours of 3");
                        layout.Palette = new byte[size];
                        Buffer.BlockCopy(data, body, layout.Palette, 0, size);
                        break;
                    case "tRNS":
                        if (layout.ColorType == 3)
                        {
                            layout.PaletteAlpha = new byte[Math.Min(size, 256)];
                            Buffer.BlockCopy(data, body, layout.PaletteAlpha, 0, layout.PaletteAlpha.Length);
                        }
                        else if (layout.ColorType == 0 && size >= 2) layout.Key = new[] { data[body] << 8 | data[body + 1] };
                        else if (layout.ColorType == 2 && size >= 6) layout.Key = new[] { data[body] << 8 | data[body + 1], data[body + 2] << 8 | data[body + 3], data[body + 4] << 8 | data[body + 5] };
                        break;
                    case "IDAT":
                        compressed.Write(data, body, size);
                        break;
                    default:
                        // A chunk whose name starts with a capital is critical: an image cannot be read without it.
                        if ((data[at + 4] & 0x20) == 0) throw new FormatException("it needs its " + type + " chunk read, and UsaBanner's PNG reader does not know it");
                        break;
                }
                at = body + size + 4;
            }
            if (!haveHeader) throw new FormatException("it is cut short before its header");
            if (layout.ColorType == 3 && layout.Palette == null) throw new FormatException("it has no palette (PLTE chunk)");
            if (compressed.Length == 0) throw new FormatException("it has no image data (IDAT chunk)");

            int channels = layout.ColorType == 2 ? 3 : layout.ColorType == 4 ? 2 : layout.ColorType == 6 ? 4 : 1;
            int bitsPerPixel = channels * layout.Depth;
            int step = Math.Max(1, bitsPerPixel / 8);   // the filters' distance back to "the pixel to the left"
            int passes = interlace == 1 ? 7 : 1;
            long total = 0;
            for (int p = 0; p < passes; p++)
            {
                long pw = PassSize(width, interlace == 1 ? PassX[p] : 0, interlace == 1 ? PassStepX[p] : 1);
                long ph = PassSize(height, interlace == 1 ? PassY[p] : 0, interlace == 1 ? PassStepY[p] : 1);
                if (pw > 0 && ph > 0) total += ph * (1 + (pw * bitsPerPixel + 7) / 8);
            }
            if (total > int.MaxValue) throw new FormatException("its image data is too large to read");
            byte[] raw = Inflate(compressed, (int)total);

            var pixels = new byte[(long)width * height * 4];
            int offset = 0;
            for (int p = 0; p < passes; p++)
            {
                int x0 = interlace == 1 ? PassX[p] : 0, y0 = interlace == 1 ? PassY[p] : 0;
                int dx = interlace == 1 ? PassStepX[p] : 1, dy = interlace == 1 ? PassStepY[p] : 1;
                int pw = PassSize(width, x0, dx), ph = PassSize(height, y0, dy);
                if (pw == 0 || ph == 0) continue;
                int rowBytes = (int)(((long)pw * bitsPerPixel + 7) / 8);
                var previous = new byte[rowBytes];
                var current = new byte[rowBytes];
                for (int j = 0; j < ph; j++)
                {
                    Unfilter(raw[offset], raw, offset + 1, current, previous, rowBytes, step, y0 + j * dy);
                    offset += 1 + rowBytes;
                    long rowStart = (long)(y0 + j * dy) * width;
                    for (int i = 0; i < pw; i++) layout.Store(current, i, pixels, (rowStart + x0 + (long)i * dx) * 4);
                    var swap = previous;
                    previous = current;
                    current = swap;
                }
            }
            return new ImageRgba(width, height, pixels);
        }

        static int PassSize(int size, int first, int stepBy)
        {
            return size > first ? (size - first + stepBy - 1) / stepBy : 0;
        }

        static byte[] Inflate(MemoryStream compressed, int size)
        {
            var raw = new byte[size];
            int got = 0;
            try
            {
                compressed.Position = 0;
                using (var z = new ZLibStream(compressed, CompressionMode.Decompress, true))
                {
                    while (got < size)
                    {
                        int n = z.Read(raw, got, size - got);
                        if (n == 0) break;
                        got += n;
                    }
                }
            }
            catch (InvalidDataException e)
            {
                throw new FormatException("its image data is damaged: " + e.Message);
            }
            if (got < size) throw new FormatException("its image data is cut short: " + got + " of " + size + " bytes");
            return raw;
        }

        // Undoes one row's filter (PNG section 7.3). Each byte was stored as its difference from a
        // guess, because differences compress better: a smooth gradient becomes +3, +3, +3. The
        // row's first byte names the guess; this adds it back:
        //
        //   +---+---------+---------------------------------------------------------+
        //   | 0 | None    | no guess: the bytes as they are                         |
        //   | 1 | Sub     | the byte one pixel to the left                          |
        //   | 2 | Up      | the byte above, in the row before                       |
        //   | 3 | Average | (left + above) / 2, rounded down                        |
        //   | 4 | Paeth   | whichever of left, above and above-left is nearest to   |
        //   |   |         | left + above - above-left                               |
        //   +---+---------+---------------------------------------------------------+
        //
        // The (byte) casts wrap at 256 on purpose: PNG does this arithmetic mod 256.
        static void Unfilter(int filter, byte[] raw, int from, byte[] row, byte[] above, int rowBytes, int step, int y)
        {
            switch (filter)
            {
                case 0:
                    Buffer.BlockCopy(raw, from, row, 0, rowBytes);
                    break;
                case 1:
                    for (int i = 0; i < rowBytes; i++) row[i] = (byte)(raw[from + i] + (i >= step ? row[i - step] : 0));
                    break;
                case 2:
                    for (int i = 0; i < rowBytes; i++) row[i] = (byte)(raw[from + i] + above[i]);
                    break;
                case 3:
                    for (int i = 0; i < rowBytes; i++) row[i] = (byte)(raw[from + i] + (((i >= step ? row[i - step] : 0) + above[i]) >> 1));
                    break;
                case 4:
                    for (int i = 0; i < rowBytes; i++)
                    {
                        int a = i >= step ? row[i - step] : 0, b = above[i], c = i >= step ? above[i - step] : 0;
                        int p = a + b - c, pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c);
                        row[i] = (byte)(raw[from + i] + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c));
                    }
                    break;
                default:
                    throw new FormatException("row " + y + " names filter " + filter + ", which PNG does not have: the file is damaged");
            }
        }

        // How samples lie in a row, and how they become RGBA.
        sealed class Layout
        {
            public int ColorType, Depth;
            public byte[] Palette, PaletteAlpha;
            public int[] Key;   // tRNS for colour types 0 and 2: the sample values drawn transparent

            int Sample(byte[] row, int index)
            {
                if (Depth == 8) return row[index];
                if (Depth == 16) return row[2 * index] << 8 | row[2 * index + 1];
                // 1, 2 and 4 bits pack from the high end of each byte: at 2 bits, the byte
                // 11 01 00 10 holds the samples 3, 1, 0 and 2; To8 then makes them 255, 85, 0, 170.
                int bit = index * Depth;
                return row[bit >> 3] >> (8 - Depth - (bit & 7)) & ((1 << Depth) - 1);
            }

            int To8(int value)
            {
                if (Depth == 8) return value;
                if (Depth == 16) return value >> 8;
                return value * 255 / ((1 << Depth) - 1);
            }

            public void Store(byte[] row, int i, byte[] pixels, long at)
            {
                int r, g, b, a = 255;
                switch (ColorType)
                {
                    case 0:
                        int grey = Sample(row, i);
                        r = g = b = To8(grey);
                        if (Key != null && grey == Key[0]) a = 0;
                        break;
                    case 2:
                        int sr = Sample(row, 3 * i), sg = Sample(row, 3 * i + 1), sb = Sample(row, 3 * i + 2);
                        r = To8(sr);
                        g = To8(sg);
                        b = To8(sb);
                        if (Key != null && sr == Key[0] && sg == Key[1] && sb == Key[2]) a = 0;
                        break;
                    case 3:
                        int index = Sample(row, i);
                        if (3 * index + 2 < Palette.Length)
                        {
                            r = Palette[3 * index];
                            g = Palette[3 * index + 1];
                            b = Palette[3 * index + 2];
                        }
                        else r = g = b = 0;   // an index past the end of the palette: black
                        if (PaletteAlpha != null && index < PaletteAlpha.Length) a = PaletteAlpha[index];
                        break;
                    case 4:
                        r = g = b = To8(Sample(row, 2 * i));
                        a = To8(Sample(row, 2 * i + 1));
                        break;
                    default:
                        r = To8(Sample(row, 4 * i));
                        g = To8(Sample(row, 4 * i + 1));
                        b = To8(Sample(row, 4 * i + 2));
                        a = To8(Sample(row, 4 * i + 3));
                        break;
                }
                pixels[at] = (byte)r;
                pixels[at + 1] = (byte)g;
                pixels[at + 2] = (byte)b;
                pixels[at + 3] = (byte)a;
            }
        }
    }

    public sealed class ArtSettings
    {
        public int Columns;                 // 0: from Rows and the picture's shape, or DefaultColumns
        public int Rows;                    // 0: from Columns and the picture's shape
        public int DefaultColumns = 40;
        public int Colors = 6;              // the most colour classes, 1 to 16
        public string Background = "auto";  // auto, none or color
        public int BackgroundRgb = -1;      // for color: 0xRRGGBB
        public string Fill = "auto";        // auto, none or color
        public int FillRgb = -1;            // for color: 0xRRGGBB
        public string Style = "auto";       // auto, shape or ramp
    }

    public sealed class ArtResult
    {
        public string[] Art;
        public string[] Mask;
        public int[] Rgb;           // each class's colour as drawn, 0xRRGGBB; class k is the letter 'a' + k
        public int[] ImageRgb;      // each class's colour in the image; not Rgb where a dark one was lifted
        public double[] Share;      // each class's share of the picture, 0 to 1
        public int FillClass = -1;  // the class drawn as fill, or -1
        public string Style;        // shape or ramp
        public string Background;   // transparent, #RRGGBB or none
        public string Fitted;       // why the size asked for was changed, or null
        public double ColorError;   // how far, as an RMS RGB distance, pixels are from their class's colour
    }

    public static class ArtMaker
    {
        // Each character's ink as 2 columns x 4 rows of dots, row by row from the top. On a tie
        // the earlier one wins, so the plainest comes first.
        static readonly string[] Chars = { " ", "8", ".", ",", "'", "'", "\"", "_", "o", "Y", "P", "9", "b", "d", "p", "q", "/", "\\", "(", ")", "|", "|" };
        static readonly string[] Dots = {
            "00000000", "11111111", "00000001", "00000010", "10000000", "01000000", "11000000", "00000011",
            "00001111", "11110000", "11111010", "11110101", "10101111", "01011111", "00111110", "00111101",
            "01011010", "10100101", "01101001", "10010110", "10101010", "01010101" };
        const string Ramp = ".:-=+*#%@";      // ramp style's characters, dimmest first
        public const char FillChar = '8';     // a fill cell's character in colour: the whole cell, as Tux's belly
        public const int MaxColumns = 64, MaxRows = 30;
        const double Tolerance = 40;          // the RGB distance within which a pixel is the background colour
        const double MergeDistance = 32;      // classes closer than this become one
        const double LiftLuma = 80;           // a class darker than this is mixed toward white until it is not
        const double BlendShare = 0.03;       // shape style: a class this small, between two others, joins one
        const double BlendDistance = 12;      // ... when within this of the line between them
        const double HaloShare = 0.15;        // shape style: a class this small, ringing a part, joins it
        const double HaloContact = 0.2;       // ... when this share of its pixels touch the background, and the part
        const double HaloDistance = 48;       // ... and it lies within this of the line from the part to the background
        const double PhotoError = 18;         // auto style is ramp when pixels miss their class by more
        const double MinBackground = 0.02;    // auto style is shape when at least this share is background

        public static ArtResult Convert(ImageRgba image, ArtSettings settings)
        {
            int w = image.Width, h = image.Height, n = w * h;
            byte[] px = image.Pixels;

            // 1. The background. ink: how much of each pixel is picture, 0 to 255.
            var ink = new byte[n];
            for (int i = 0; i < n; i++)
            {
                byte a = px[4 * i + 3];
                ink[i] = a < 8 ? (byte)0 : a;
            }
            int[] border = BorderPixels(w, h);
            bool clearBorder = false;
            foreach (int i in border)
                if (px[4 * i + 3] < 128) { clearBorder = true; break; }
            int bg = -1;
            if (settings.Background == "color") bg = settings.BackgroundRgb;
            else if (settings.Background == "auto" && !clearBorder) bg = BorderColour(px, border);
            int flooded = bg >= 0 ? Flood(px, w, h, ink, bg, border) : 0;
            int clear = 0;
            for (int i = 0; i < n; i++) if (ink[i] == 0) clear++;

            // 2. Crop to the picture, and size the art.
            int x0 = w, y0 = h, x1 = -1, y1 = -1;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    if (ink[y * w + x] == 0) continue;
                    if (x < x0) x0 = x;
                    if (x > x1) x1 = x;
                    if (y < y0) y0 = y;
                    y1 = y;
                }
            if (x1 < 0) throw new ArgumentException("all of it is background (" + (flooded > 0 ? Hex(bg) : "transparent") + "), so there is nothing to draw" + (flooded > 0 ? "; -Background none keeps it" : ""));
            int cw = x1 - x0 + 1, ch = y1 - y0 + 1;
            int cols = settings.Columns, rows = settings.Rows;
            string fitted = null;
            if (cols > MaxColumns || rows > MaxRows) throw new ArgumentException("art may take " + MaxColumns + " columns and " + MaxRows + " rows");
            if (cols <= 0 && rows <= 0) cols = Math.Min(settings.DefaultColumns, Math.Max(1, (cw + 1) / 2));
            if (rows <= 0)
            {
                rows = RowsFor(cols, cw, ch);
                if (rows > MaxRows)
                {
                    int asked = cols;
                    cols = ColumnsFor(MaxRows, cw, ch);
                    if (settings.Columns > 0) fitted = "at " + asked + " columns the picture takes " + rows + " rows, and art may take " + MaxRows + ", so it is " + cols + " columns wide";
                    rows = MaxRows;
                }
            }
            else if (cols <= 0)
            {
                cols = ColumnsFor(rows, cw, ch);
                if (cols > MaxColumns)
                {
                    int asked = rows;
                    rows = RowsFor(MaxColumns, cw, ch);
                    fitted = "at " + asked + " rows the picture takes " + cols + " columns, and art may take " + MaxColumns + ", so it is " + rows + " rows tall";
                    cols = MaxColumns;
                }
            }

            // 3. Colours: a histogram at 32 levels a channel, cut into classes.
            var binWeight = new double[32768];
            var binSum = new double[32768 * 3];
            for (int y = y0; y <= y1; y++)
                for (int x = x0; x <= x1; x++)
                {
                    int i = y * w + x;
                    if (ink[i] == 0) continue;
                    int r = px[4 * i], g = px[4 * i + 1], b = px[4 * i + 2];
                    // 32 levels a channel (r >> 3 is r / 8), packed as one 15-bit number, rrrrrgggggbbbbb:
                    // near-identical colours share a bin, which keeps their sum and weight.
                    int bin = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3);
                    double weight = ink[i] / 255.0;
                    binWeight[bin] += weight;
                    binSum[3 * bin] += r * weight;
                    binSum[3 * bin + 1] += g * weight;
                    binSum[3 * bin + 2] += b * weight;
                }
            var colours = new List<double[]>();
            for (int bin = 0; bin < binWeight.Length; bin++)
                if (binWeight[bin] > 0)
                    colours.Add(new[] { binSum[3 * bin] / binWeight[bin], binSum[3 * bin + 1] / binWeight[bin], binSum[3 * bin + 2] / binWeight[bin], binWeight[bin] });
            List<double[]> centres = MedianCut(colours, Math.Max(1, Math.Min(16, settings.Colors)));
            centres = KMeans(colours, centres, 8);
            centres = MergeClose(colours, centres);

            // Each pixel's class, 1 + its index; 0 for the background.
            var cls = new byte[cw * ch];
            var held = new double[centres.Count];
            double inkTotal = 0, squaredError = 0;
            int lastRgb = -1, lastClass = 0;
            for (int y = y0; y <= y1; y++)
                for (int x = x0; x <= x1; x++)
                {
                    int i = y * w + x;
                    if (ink[i] == 0) continue;
                    int rgb = px[4 * i] << 16 | px[4 * i + 1] << 8 | px[4 * i + 2];
                    if (rgb != lastRgb)
                    {
                        lastClass = Nearest(centres, rgb);
                        lastRgb = rgb;
                    }
                    cls[(y - y0) * cw + x - x0] = (byte)(lastClass + 1);
                    double weight = ink[i] / 255.0;
                    held[lastClass] += weight;
                    inkTotal += weight;
                    squaredError += weight * Distance2(centres[lastClass], rgb);
                }
            var classColour = new List<double[]>(centres);
            var classWeight = new List<double>(held);
            SortByWeight(cls, classColour, classWeight);
            double colorError = Math.Sqrt(squaredError / inkTotal);
            string style = settings.Style;
            if (style == "auto") style = clear >= MinBackground * n && colorError <= PhotoError ? "shape" : "ramp";
            if (style == "shape") MergeBlends(cls, classColour, classWeight, bg);
            if (style == "shape" && flooded > 0) MergeHalos(cls, cw, ch, classColour, classWeight, bg);
            int classes = classColour.Count;
            int fill = -1;
            if (style == "shape" && classes > 1)
            {
                if (settings.Fill == "color") fill = Nearest(classColour, settings.FillRgb);
                else if (settings.Fill == "auto") fill = Enclosed(cls, cw, ch, classes);
            }
            var result = new ArtResult
            {
                Rgb = new int[classes],
                ImageRgb = new int[classes],
                Share = new double[classes],
                FillClass = fill,
                Style = style,
                Background = flooded > 0 ? Hex(bg) : clearBorder ? "transparent" : "none",
                Fitted = fitted,
                ColorError = colorError
            };
            for (int k = 0; k < classes; k++)
            {
                result.ImageRgb[k] = Pack(classColour[k][0], classColour[k][1], classColour[k][2]);
                result.Rgb[k] = Lift(result.ImageRgb[k]);
                result.Share[k] = classWeight[k] / inkTotal;
            }

            // 4. Dots: each a half of a cell across and a quarter down, and how much of each class
            // covers it.
            int dotsX = 2 * cols, dotsY = 4 * rows;
            Overlap[][] across = Spans(cw, dotsX), down = Spans(ch, dotsY);
            var cover = new double[dotsX * dotsY * classes];
            var area = new double[dotsX * dotsY];
            var inkOf = new double[dotsX * dotsY];
            var lumaOf = new double[dotsX * dotsY];
            for (int dy = 0; dy < dotsY; dy++)
                for (int dx = 0; dx < dotsX; dx++)
                {
                    int d = dy * dotsX + dx;
                    foreach (Overlap oy in down[dy])
                        foreach (Overlap ox in across[dx])
                        {
                            double part = ox.Weight * oy.Weight;
                            area[d] += part;
                            int c = cls[oy.Index * cw + ox.Index];
                            if (c == 0) continue;
                            int i = (y0 + oy.Index) * w + x0 + ox.Index;
                            double amount = ink[i] / 255.0 * part;
                            cover[d * classes + c - 1] += amount;
                            inkOf[d] += amount;
                            lumaOf[d] += amount * Luma(px[4 * i], px[4 * i + 1], px[4 * i + 2]);
                        }
                }

            // 5. A character and a class for each cell.
            var artRows = new string[rows];
            var maskRows = new string[rows];
            var level = new double[rows * cols];
            var lit = new bool[rows * cols];
            if (style == "ramp")
            {
                // Brightness is stretched so the dimmest 2% and the brightest 2% of the lit cells
                // take the ends of the ramp.
                var seen = new List<double>();
                for (int r = 0; r < rows; r++)
                    for (int c = 0; c < cols; c++)
                    {
                        double inkSum = 0, areaSum = 0, lumaSum = 0;
                        for (int t = 0; t < 8; t++)
                        {
                            int d = (4 * r + t / 2) * dotsX + 2 * c + t % 2;
                            inkSum += inkOf[d];
                            areaSum += area[d];
                            lumaSum += lumaOf[d];
                        }
                        if (inkSum < 0.25 * areaSum) continue;
                        lit[r * cols + c] = true;
                        level[r * cols + c] = lumaSum / inkSum;
                        seen.Add(lumaSum / inkSum);
                    }
                seen.Sort();
                double low = 0, high = 255;
                if (seen.Count > 0)
                {
                    low = seen[(int)Math.Round(0.02 * (seen.Count - 1))];
                    high = seen[(int)Math.Round(0.98 * (seen.Count - 1))];
                }
                if (high - low < 8)
                {
                    low = 0;
                    high = 255;
                }
                for (int i = 0; i < level.Length; i++) level[i] = Math.Max(0, Math.Min(1, (level[i] - low) / (high - low)));
            }
            for (int r = 0; r < rows; r++)
            {
                var artRow = new StringBuilder(cols);
                var maskRow = new StringBuilder(cols);
                for (int c = 0; c < cols; c++)
                {
                    var dot = new double[8];
                    var byClass = new double[classes];
                    double hollow = 0;
                    for (int t = 0; t < 8; t++)
                    {
                        int d = (4 * r + t / 2) * dotsX + 2 * c + t % 2;
                        for (int k = 0; k < classes; k++)
                        {
                            double v = cover[d * classes + k] / area[d];
                            if (k == fill) hollow += v;
                            else
                            {
                                dot[t] += v;
                                byClass[k] += v;
                            }
                        }
                    }
                    char chr;
                    if (style == "ramp") chr = lit[r * cols + c] ? Ramp[(int)Math.Round(level[r * cols + c] * (Ramp.Length - 1))] : ' ';
                    else chr = Chars[BestFit(dot)][0];
                    if (chr != ' ')
                    {
                        artRow.Append(chr);
                        maskRow.Append((char)('a' + ArgMax(byClass)));
                    }
                    else
                    {
                        artRow.Append(' ');
                        maskRow.Append(fill >= 0 && hollow > 4 ? (char)('a' + fill) : ' ');
                    }
                }
                artRows[r] = artRow.ToString();
                maskRows[r] = maskRow.ToString();
            }
            Trim(artRows, maskRows, result);
            return result;
        }

        static int RowsFor(int cols, int cw, int ch)
        {
            return Math.Max(1, (int)Math.Round(cols * (double)ch / (2.0 * cw), MidpointRounding.AwayFromZero));
        }

        static int ColumnsFor(int rows, int cw, int ch)
        {
            return Math.Max(1, (int)Math.Round(rows * 2.0 * cw / ch, MidpointRounding.AwayFromZero));
        }

        // The template whose ink pattern is nearest a cell's 8 dot coverages, each 0 to 1: the sum
        // of |coverage - template| over the 8 dots, smallest wins. A cell on a ring's lower edge:
        //
        //   0   0       'o' 00001111: 0 + 0 + 0 + 0.4 + 0.7 + 0 + 0 + 0 = 1.1, the nearest
        //   0   0.4     'd' 01011111: 2.3
        //   0.3 1       ',' 00000010: 2.7
        //   1   1
        static int BestFit(double[] dot)
        {
            int best = 0;
            double bestDistance = double.MaxValue;
            for (int t = 0; t < Chars.Length; t++)
            {
                double distance = 0;
                for (int s = 0; s < 8; s++) distance += Math.Abs(dot[s] - (Dots[t][s] == '1' ? 1.0 : 0.0));
                if (distance < bestDistance - 1e-9)
                {
                    bestDistance = distance;
                    best = t;
                }
            }
            return best;
        }

        static int ArgMax(double[] values)
        {
            int best = 0;
            for (int k = 1; k < values.Length; k++) if (values[k] > values[best]) best = k;
            return best;
        }

        // Blank rows above and below, the columns blank in every row on the left, and each row's
        // blank end go; a cell is blank when the art and the mask both have a space there.
        static void Trim(string[] art, string[] mask, ArtResult result)
        {
            int top = 0, bottom = art.Length - 1;
            while (top <= bottom && art[top].Trim().Length == 0 && mask[top].Trim().Length == 0) top++;
            while (bottom >= top && art[bottom].Trim().Length == 0 && mask[bottom].Trim().Length == 0) bottom--;
            bool shows = false;
            for (int r = top; r <= bottom; r++) if (art[r].Trim().Length > 0) shows = true;
            if (!shows) throw new ArgumentException("at " + art[0].Length + " x " + art.Length + " nothing of it shows before login; make it larger");
            int left = int.MaxValue;
            for (int r = top; r <= bottom; r++)
                for (int c = 0; c < art[r].Length; c++)
                    if (art[r][c] != ' ' || mask[r][c] != ' ')
                    {
                        left = Math.Min(left, c);
                        break;
                    }
            result.Art = new string[bottom - top + 1];
            result.Mask = new string[bottom - top + 1];
            for (int r = top; r <= bottom; r++)
            {
                int end = art[r].Length;
                while (end > 0 && art[r][end - 1] == ' ' && mask[r][end - 1] == ' ') end--;
                result.Art[r - top] = end > left ? art[r].Substring(left, end - left) : "";
                result.Mask[r - top] = end > left ? mask[r].Substring(left, end - left) : "";
            }
        }

        struct Overlap
        {
            public int Index;
            public double Weight;
        }

        // n pixels cut into parts equal spans: for each span, the pixels it overlaps and by how much.
        // 5 pixels in 2 spans: span 0 is pixels 0 and 1 and half of 2; span 1 is the other half of
        // 2, then 3 and 4. A dot is a span across times a span down.
        static Overlap[][] Spans(int n, int parts)
        {
            var spans = new Overlap[parts][];
            for (int p = 0; p < parts; p++)
            {
                double start = (double)p * n / parts, end = (double)(p + 1) * n / parts;
                var list = new List<Overlap>();
                for (int q = (int)Math.Floor(start); q < end && q < n; q++)
                {
                    double weight = Math.Min(end, q + 1) - Math.Max(start, q);
                    if (weight > 1e-12) list.Add(new Overlap { Index = q, Weight = weight });
                }
                spans[p] = list.ToArray();
            }
            return spans;
        }

        static int[] BorderPixels(int w, int h)
        {
            var list = new List<int>();
            for (int x = 0; x < w; x++)
            {
                list.Add(x);
                if (h > 1) list.Add((h - 1) * w + x);
            }
            for (int y = 1; y < h - 1; y++)
            {
                list.Add(y * w);
                if (w > 1) list.Add(y * w + w - 1);
            }
            return list.ToArray();
        }

        // The colour of half the border or more, within Tolerance; -1 when no colour holds that much.
        static int BorderColour(byte[] px, int[] border)
        {
            var counts = new Dictionary<int, int>();
            foreach (int i in border)
            {
                int bin = (px[4 * i] >> 3) << 10 | (px[4 * i + 1] >> 3) << 5 | (px[4 * i + 2] >> 3);
                int count;
                counts.TryGetValue(bin, out count);
                counts[bin] = count + 1;
            }
            int best = -1, most = 0;
            foreach (KeyValuePair<int, int> pair in counts)
                if (pair.Value > most || (pair.Value == most && pair.Key < best))
                {
                    most = pair.Value;
                    best = pair.Key;
                }
            double r = 0, g = 0, b = 0;
            int inBin = 0;
            foreach (int i in border)
            {
                int bin = (px[4 * i] >> 3) << 10 | (px[4 * i + 1] >> 3) << 5 | (px[4 * i + 2] >> 3);
                if (bin != best) continue;
                r += px[4 * i];
                g += px[4 * i + 1];
                b += px[4 * i + 2];
                inBin++;
            }
            int colour = Pack(r / inBin, g / inBin, b / inBin);
            int near = 0;
            foreach (int i in border) if (Matches(px, i, colour)) near++;
            return 2 * near >= border.Length ? colour : -1;
        }

        static bool Matches(byte[] px, int i, int rgb)
        {
            if (px[4 * i + 3] < 128) return true;
            double dr = px[4 * i] - (rgb >> 16 & 255), dg = px[4 * i + 1] - (rgb >> 8 & 255), db = px[4 * i + 2] - (rgb & 255);
            return dr * dr + dg * dg + db * db <= Tolerance * Tolerance;
        }

        // Clears the pixels of about the colour rgb, and transparent ones, that the border reaches
        // through each other: the paint-bucket tool, started from every edge pixel, so the same
        // colour inside the picture (Tux's white belly) stays. A scanline fill clears a whole run
        // from left to right at once, then queues the runs above and below it: far fewer steps
        // than one pixel at a time. Returns how many it cleared.
        static int Flood(byte[] px, int w, int h, byte[] ink, int rgb, int[] border)
        {
            var done = new bool[w * h];
            var stack = new Stack<int>(border);
            int cleared = 0;
            while (stack.Count > 0)
            {
                int i = stack.Pop();
                if (done[i] || !Matches(px, i, rgb)) continue;
                int y = i / w, rowStart = y * w, left = i - rowStart, right = left;
                while (left > 0 && !done[rowStart + left - 1] && Matches(px, rowStart + left - 1, rgb)) left--;
                while (right < w - 1 && !done[rowStart + right + 1] && Matches(px, rowStart + right + 1, rgb)) right++;
                for (int x = left; x <= right; x++)
                {
                    done[rowStart + x] = true;
                    ink[rowStart + x] = 0;
                    cleared++;
                }
                for (int ny = y - 1; ny <= y + 1; ny += 2)
                {
                    if (ny < 0 || ny >= h) continue;
                    bool inRun = false;
                    for (int x = left; x <= right; x++)
                    {
                        int j = ny * w + x;
                        if (!done[j] && Matches(px, j, rgb))
                        {
                            if (!inRun) stack.Push(j);
                            inRun = true;
                        }
                        else inRun = false;
                    }
                }
            }
            return cleared;
        }

        // The class drawn as fill: the largest the picture encloses, under a third of whose edge
        // meets the background, as the disc inside a badge's ring or Tux's belly; -1 when none is.
        // Classes are in share order, so the first found is the largest.
        static int Enclosed(byte[] cls, int cw, int ch, int classes)
        {
            var outer = new long[classes + 1];
            var inner = new long[classes + 1];
            for (int y = 0; y < ch; y++)
                for (int x = 0; x < cw; x++)
                {
                    int mine = cls[y * cw + x];
                    if (mine == 0) continue;
                    bool meetsClear = false, meetsInk = false;
                    for (int s = 0; s < 4; s++)
                    {
                        int nx = x + (s == 0 ? -1 : s == 1 ? 1 : 0), ny = y + (s == 2 ? -1 : s == 3 ? 1 : 0);
                        int next = nx < 0 || ny < 0 || nx >= cw || ny >= ch ? 0 : cls[ny * cw + nx];
                        if (next == 0) meetsClear = true;
                        else if (next != mine) meetsInk = true;
                    }
                    if (meetsClear) outer[mine]++;
                    else if (meetsInk) inner[mine]++;
                }
            for (int k = 1; k <= classes; k++)
                if (3 * outer[k] < outer[k] + inner[k]) return k - 1;
            return -1;
        }

        // Classes in order of weight, the heaviest first, a tie in the order they are in; a class
        // no pixel took goes. cls is renumbered to match.
        static void SortByWeight(byte[] cls, List<double[]> colour, List<double> weight)
        {
            var order = new List<int>();
            for (int k = 0; k < colour.Count; k++) if (weight[k] > 0) order.Add(k);
            order.Sort((a, b) => weight[a] != weight[b] ? weight[b].CompareTo(weight[a]) : a.CompareTo(b));
            var renumber = new byte[colour.Count];
            for (int k = 0; k < order.Count; k++) renumber[order[k]] = (byte)(k + 1);
            for (int i = 0; i < cls.Length; i++) if (cls[i] != 0) cls[i] = renumber[cls[i] - 1];
            var sortedColour = new List<double[]>();
            var sortedWeight = new List<double>();
            foreach (int k in order)
            {
                sortedColour.Add(colour[k]);
                sortedWeight.Add(weight[k]);
            }
            colour.Clear();
            colour.AddRange(sortedColour);
            weight.Clear();
            weight.AddRange(sortedWeight);
        }

        // Anti-aliased edges leave thin classes of the colours between two others, or between one
        // and the background colour. In shape style a class under BlendShare of the picture that
        // lies within BlendDistance of the line between two heavier classes joins the nearer of
        // the two; one on the line from a heavier class to the background joins that class.
        static void MergeBlends(byte[] cls, List<double[]> colour, List<double> weight, int bg)
        {
            double total = 0;
            foreach (double w in weight) total += w;
            double[] background = bg >= 0 ? new double[] { bg >> 16 & 255, bg >> 8 & 255, bg & 255 } : null;
            // The lightest first. Merging adds to a heavier class, never to one already passed.
            for (int c = colour.Count - 1; c > 0; c--)
            {
                if (weight[c] >= BlendShare * total) continue;
                int into = -1;
                double t;
                for (int a = 0; a < c && into < 0; a++)
                {
                    if (background != null && Between(colour[c], colour[a], background, BlendDistance, out t)) into = a;
                    for (int b = a + 1; b < c && into < 0; b++)
                        if (Between(colour[c], colour[a], colour[b], BlendDistance, out t)) into = t < 0.5 ? a : b;
                }
                if (into < 0) continue;
                weight[into] += weight[c];
                colour.RemoveAt(c);
                weight.RemoveAt(c);
                for (int i = 0; i < cls.Length; i++)
                {
                    if (cls[i] == c + 1) cls[i] = (byte)(into + 1);
                    else if (cls[i] > c + 1) cls[i]--;
                }
            }
            SortByWeight(cls, colour, weight);
        }

        // A JPEG, or another lossy format, leaves a thin halo of off colours where a part meets the
        // background colour; it can ring a part so the part looks enclosed and is drawn as fill.
        // In shape style, with a background colour cleared, a class under HaloShare of the picture
        // joins a heavier class when HaloContact or more of its pixels touch the background, as
        // many touch that class, and its colour lies within HaloDistance of the line from that
        // class's colour to the background's.
        static void MergeHalos(byte[] cls, int cw, int ch, List<double[]> colour, List<double> weight, int bg)
        {
            int classes = colour.Count;
            if (classes < 2) return;
            double total = 0;
            foreach (double w in weight) total += w;
            int n = classes + 1;   // class numbers in cls run 1 to classes; 0 is the background
            var pixels = new long[n];
            var touchClear = new long[n];
            var touch = new long[n * n];
            var met = new bool[n];
            for (int y = 0; y < ch; y++)
                for (int x = 0; x < cw; x++)
                {
                    int mine = cls[y * cw + x];
                    if (mine == 0) continue;
                    pixels[mine]++;
                    bool clear = false;
                    for (int s = 0; s < 4; s++)
                    {
                        int nx = x + (s == 0 ? -1 : s == 1 ? 1 : 0), ny = y + (s == 2 ? -1 : s == 3 ? 1 : 0);
                        int next = nx < 0 || ny < 0 || nx >= cw || ny >= ch ? 0 : cls[ny * cw + nx];
                        if (next == 0) clear = true;
                        else if (next != mine && !met[next])
                        {
                            met[next] = true;
                            touch[mine * n + next]++;
                        }
                    }
                    if (clear) touchClear[mine]++;
                    for (int k = 1; k < n; k++) met[k] = false;
                }
            double[] background = { bg >> 16 & 255, bg >> 8 & 255, bg & 255 };
            var into = new int[n];
            // Classes are in share order, so a heavier class has a lower number; the heaviest stays.
            for (int k = n - 1; k > 1; k--)
            {
                if (weight[k - 1] >= HaloShare * total || touchClear[k] < HaloContact * pixels[k]) continue;
                int best = 0;
                long most = 0;
                for (int j = 1; j < k; j++)
                    if (touch[k * n + j] > most)
                    {
                        most = touch[k * n + j];
                        best = j;
                    }
                double t;
                if (best == 0 || most < HaloContact * pixels[k] || !Between(colour[k - 1], colour[best - 1], background, HaloDistance, out t)) continue;
                into[k] = best;
            }
            bool any = false;
            for (int k = 1; k < n; k++)
            {
                if (into[k] == 0) continue;
                int end = into[k];
                while (into[end] != 0) end = into[end];
                into[k] = end;
                weight[end - 1] += weight[k - 1];
                weight[k - 1] = 0;
                any = true;
            }
            if (!any) return;
            for (int i = 0; i < cls.Length; i++)
                if (cls[i] != 0 && into[cls[i]] != 0) cls[i] = (byte)into[cls[i]];
            SortByWeight(cls, colour, weight);
        }

        // Whether colour p lies on the line from a to b, within the distance given and strictly
        // between the two; t is how far along it, 0 at a and 1 at b. Colours are points in a cube
        // of red, green and blue, and a blend of two lies on the straight line between them.
        // (120,175,250) from blue (30,111,217) to white: t = 0.42, 18 off the line. That is too far
        // for a blend (BlendDistance, 12), near enough for a halo (HaloDistance, 48).
        static bool Between(double[] p, double[] a, double[] b, double within, out double t)
        {
            double length2 = 0, dot = 0;
            for (int k = 0; k < 3; k++)
            {
                length2 += (b[k] - a[k]) * (b[k] - a[k]);
                dot += (p[k] - a[k]) * (b[k] - a[k]);
            }
            t = length2 > 0 ? dot / length2 : 0;
            if (t <= 0 || t >= 1) return false;
            double distance2 = 0;
            for (int k = 0; k < 3; k++)
            {
                double off = a[k] + t * (b[k] - a[k]) - p[k];
                distance2 += off * off;
            }
            return distance2 <= within * within;
        }

        // Median cut: the box of colours with the most weighted spread along one channel splits at
        // that channel's weighted median, until there are most boxes or none can split.
        // Out: each box's weighted mean. A colour is r, g, b and its weight.
        static List<double[]> MedianCut(List<double[]> colours, int most)
        {
            double[][] items = colours.ToArray();
            var boxes = new List<int[]> { new[] { 0, items.Length } };
            while (boxes.Count < most)
            {
                int pick = -1, channel = 0;
                double widest = 0;
                for (int bi = 0; bi < boxes.Count; bi++)
                    for (int c = 0; c < 3; c++)
                    {
                        double spread = Spread(items, boxes[bi][0], boxes[bi][1], c);
                        if (spread > widest)
                        {
                            widest = spread;
                            pick = bi;
                            channel = c;
                        }
                    }
                if (pick < 0) break;
                int start = boxes[pick][0], end = boxes[pick][1], along = channel;
                Array.Sort(items, start, end - start, Comparer<double[]>.Create((a, b) => CompareAlong(a, b, along)));
                double half = 0;
                for (int i = start; i < end; i++) half += items[i][3];
                half /= 2;
                int cut = end - 1;
                double run = 0;
                for (int i = start; i < end - 1; i++)
                {
                    run += items[i][3];
                    if (run >= half)
                    {
                        cut = i + 1;
                        break;
                    }
                }
                boxes[pick] = new[] { start, cut };
                boxes.Insert(pick + 1, new[] { cut, end });
            }
            var centres = new List<double[]>();
            foreach (int[] box in boxes)
            {
                double r = 0, g = 0, b = 0, total = 0;
                for (int i = box[0]; i < box[1]; i++)
                {
                    double weight = items[i][3];
                    r += items[i][0] * weight;
                    g += items[i][1] * weight;
                    b += items[i][2] * weight;
                    total += weight;
                }
                centres.Add(new[] { r / total, g / total, b / total });
            }
            return centres;
        }

        static double Spread(double[][] items, int start, int end, int channel)
        {
            if (end - start < 2) return 0;
            double total = 0, mean = 0;
            for (int i = start; i < end; i++)
            {
                total += items[i][3];
                mean += items[i][channel] * items[i][3];
            }
            mean /= total;
            double spread = 0;
            for (int i = start; i < end; i++)
            {
                double d = items[i][channel] - mean;
                spread += items[i][3] * d * d;
            }
            return spread;
        }

        static int CompareAlong(double[] a, double[] b, int channel)
        {
            int c = a[channel].CompareTo(b[channel]);
            for (int k = 0; c == 0 && k < 3; k++) c = a[k].CompareTo(b[k]);
            return c;
        }

        // Moves each centre to the weighted mean of the colours nearest it, a few rounds or until
        // none moves; a centre no colour is nearest goes.
        static List<double[]> KMeans(List<double[]> colours, List<double[]> centres, int rounds)
        {
            for (int round = 0; round < rounds; round++)
            {
                int k = centres.Count;
                var sum = new double[3 * k];
                var total = new double[k];
                foreach (double[] c in colours)
                {
                    int j = NearestCentre(centres, c);
                    sum[3 * j] += c[0] * c[3];
                    sum[3 * j + 1] += c[1] * c[3];
                    sum[3 * j + 2] += c[2] * c[3];
                    total[j] += c[3];
                }
                var next = new List<double[]>();
                double moved = 0;
                for (int j = 0; j < k; j++)
                {
                    if (total[j] <= 0) continue;
                    var centre = new[] { sum[3 * j] / total[j], sum[3 * j + 1] / total[j], sum[3 * j + 2] / total[j] };
                    moved = Math.Max(moved, Math.Abs(centre[0] - centres[j][0]) + Math.Abs(centre[1] - centres[j][1]) + Math.Abs(centre[2] - centres[j][2]));
                    next.Add(centre);
                }
                bool settled = next.Count == k && moved < 0.01;
                centres = next;
                if (settled) break;
            }
            return centres;
        }

        // Centres closer than MergeDistance become one, the closest pair first, at their mean
        // weighted by the colours nearest each.
        static List<double[]> MergeClose(List<double[]> colours, List<double[]> centres)
        {
            while (centres.Count > 1)
            {
                var held = new double[centres.Count];
                foreach (double[] c in colours) held[NearestCentre(centres, c)] += c[3];
                int a = -1, b = -1;
                double closest = MergeDistance * MergeDistance;
                for (int i = 0; i < centres.Count; i++)
                    for (int j = i + 1; j < centres.Count; j++)
                    {
                        double d = 0;
                        for (int k = 0; k < 3; k++) d += (centres[i][k] - centres[j][k]) * (centres[i][k] - centres[j][k]);
                        if (d < closest)
                        {
                            closest = d;
                            a = i;
                            b = j;
                        }
                    }
                if (a < 0) break;
                double total = held[a] + held[b];
                if (total > 0)
                {
                    var merged = new double[3];
                    for (int k = 0; k < 3; k++) merged[k] = (centres[a][k] * held[a] + centres[b][k] * held[b]) / total;
                    centres[a] = merged;
                }
                centres.RemoveAt(b);
            }
            return centres;
        }

        static int NearestCentre(List<double[]> centres, double[] colour)
        {
            int best = 0;
            double bestDistance = double.MaxValue;
            for (int k = 0; k < centres.Count; k++)
            {
                double d = 0;
                for (int c = 0; c < 3; c++) d += (centres[k][c] - colour[c]) * (centres[k][c] - colour[c]);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = k;
                }
            }
            return best;
        }

        static int Nearest(List<double[]> centres, int rgb)
        {
            int best = 0;
            double bestDistance = double.MaxValue;
            for (int k = 0; k < centres.Count; k++)
            {
                double d = Distance2(centres[k], rgb);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    best = k;
                }
            }
            return best;
        }

        static double Distance2(double[] centre, int rgb)
        {
            double dr = centre[0] - (rgb >> 16 & 255), dg = centre[1] - (rgb >> 8 & 255), db = centre[2] - (rgb & 255);
            return dr * dr + dg * dg + db * db;
        }

        // Brightness as the eye weighs it (ITU-R BT.709): green counts most, blue least.
        static double Luma(int r, int g, int b)
        {
            return 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }

        static int Channel(double value)
        {
            return (int)Math.Max(0, Math.Min(255, Math.Round(value, MidpointRounding.AwayFromZero)));
        }

        static int Pack(double r, double g, double b)
        {
            return Channel(r) << 16 | Channel(g) << 8 | Channel(b);
        }

        // A colour darker than LiftLuma, mixed toward white until it is that light, so a dark
        // terminal shows it: black becomes #505050, #C81E28 becomes #CC2E37. A lighter colour comes
        // back as it is.
        public static int Lift(int rgb)
        {
            int r = rgb >> 16 & 255, g = rgb >> 8 & 255, b = rgb & 255;
            double luma = Luma(r, g, b);
            if (luma >= LiftLuma) return rgb;
            double t = (LiftLuma - luma) / (255 - luma);
            return Pack(r + (255 - r) * t, g + (255 - g) * t, b + (255 - b) * t);
        }

        public static string Hex(int rgb)
        {
            return "#" + rgb.ToString("X6");
        }
    }
}
