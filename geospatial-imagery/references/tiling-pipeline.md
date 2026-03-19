# Tiling Pipeline: Under the Hood

A comprehensive narrative covering the complete lifecycle of geospatial imagery, from raw
acquisition to a tile appearing in a user's browser. This document explains the math, the
data structures, and the critical code paths that make tile serving work.

---

## Table of Contents

1. [The Complete Tiling Pipeline](#the-complete-tiling-pipeline)
2. [What GDAL Does Under the Hood](#what-gdal-does-under-the-hood)
3. [Building a Pipeline Without GDAL](#building-a-pipeline-without-gdal)
4. [Runtime vs Build-Time Operations](#runtime-vs-build-time-operations)
5. [The COG Range Request Story](#the-cog-range-request-story)
6. [Hot Path Analysis](#hot-path-analysis)

---

## The Complete Tiling Pipeline

### Step 1: Raw Image Ingestion

Satellite and aerial imagery arrives in a variety of formats depending on the sensor and
provider:

- **Satellite sensors** (Landsat, Sentinel, WorldView) typically deliver GeoTIFF, JPEG 2000,
  or NITF files. Multispectral data arrives as multiple bands (e.g., Landsat 8 delivers 11
  bands as separate GeoTIFFs). Metadata accompanies the imagery in XML or JSON sidecar files
  containing acquisition time, solar angles, sensor calibration, and ephemeris data.

- **Aerial cameras** (UltraCam, DMC, Leica ADS) produce TIFF or proprietary raw formats.
  Frame cameras capture a single image per exposure; pushbroom sensors produce long strips.

- **Drone/UAS platforms** generate standard JPEG or TIFF from consumer cameras, sometimes
  with embedded EXIF GPS coordinates rather than rigorous georeferencing.

At ingestion, each file contains or references:
- **Pixel data** in some arrangement (band-interleaved-by-pixel, band-sequential, etc.)
- **Spatial metadata**: a coordinate reference system (CRS), ground control points (GCPs),
  or rational polynomial coefficients (RPCs) relating pixel coordinates to Earth coordinates
- **Radiometric metadata**: bit depth, nodata values, gain/offset calibration

### Step 2: Georeferencing and Coordinate System Assignment

Every raster needs a mapping from pixel coordinates `(column, row)` to Earth coordinates
`(X, Y)`. This is the **geotransform**, a 6-parameter affine transformation:

```
X_geo = GT[0] + column * GT[1] + row * GT[2]
Y_geo = GT[3] + column * GT[4] + row * GT[5]
```

Where:
- `GT[0]`, `GT[3]`: origin (upper-left corner X, Y in the CRS)
- `GT[1]`: pixel width (X resolution, positive = east)
- `GT[5]`: pixel height (Y resolution, typically negative = north-up)
- `GT[2]`, `GT[4]`: rotation terms (zero for north-up images)

For imagery with only GCPs or RPCs (no affine geotransform), GDAL computes the transform
by fitting a polynomial through the control points. RPCs use a ratio of cubic polynomials
to model sensor geometry, particularly for pushbroom satellites.

The CRS may be any of thousands of projections. Common source CRSs include:
- **EPSG:4326** (WGS 84 geographic): latitude/longitude on the WGS 84 ellipsoid
- **UTM zones** (EPSG:326xx / 327xx): transverse Mercator projections in 6-degree strips
- **Sensor-native** projections specific to the acquisition geometry

### Step 3: Reprojection to Web Mercator (EPSG:3857)

Web maps universally use Web Mercator (EPSG:3857), a Spherical Mercator projection. The
reprojection pipeline transforms pixel values from the source CRS to EPSG:3857.

#### The Math

Web Mercator projects the WGS 84 ellipsoid **as if it were a sphere** (radius = semi-major
axis = 6,378,137 m). The forward projection from geographic coordinates is:

```
x = R * longitude_rad
y = R * ln(tan(pi/4 + latitude_rad/2))
```

Where `R = 6378137.0` meters. The result is in meters, with the coordinate origin at the
intersection of the prime meridian and equator. The full extent of the Web Mercator map is:

```
x: [-20037508.342789244, 20037508.342789244]
y: [-20037508.342789244, 20037508.342789244]
```

This constant comes from `2 * pi * 6378137 / 2 = 20037508.342789244`.

Latitudes beyond approximately 85.051129 degrees are clipped because the Mercator
projection stretches to infinity at the poles. The GDAL COG driver explicitly clamps to
`MAX_LAT = 85.0511287798066` (see `cogdriver.cpp` line 239).

#### The Transformation Pipeline

Reprojection is not a simple formula applied to each pixel. The actual pipeline involves:

1. **Coordinate transformation setup**: GDAL creates a `GenImgProjTransformer` that chains
   together:
   - Source pixel/line to source georeference (via the affine geotransform or GCP polynomial)
   - Source CRS to target CRS (via PROJ library datum transforms and map projections)
   - Target georeference to target pixel/line (via the destination geotransform)

2. **Output bounds estimation**: `GDALSuggestedWarpOutput2()` samples the edges of the
   source image, transforms those coordinates to the target CRS, and computes the bounding
   rectangle and optimal pixel resolution.

3. **Chunk-based warping**: The `GDALWarpOperation` divides the output into chunks that fit
   within a memory budget (`dfWarpMemoryLimit`). For each chunk:
   - The edges of the output chunk are transformed back to source coordinates to identify the
     required source region
   - Source pixels are loaded into memory
   - For each output pixel, the transformer maps its position back to the source image
   - The resampling kernel interpolates the source pixel values

4. **Resampling**: For every output pixel, the inverse transformation yields a fractional
   source coordinate. The resampling algorithm computes the output value from neighboring
   source pixels:

   | Algorithm | Kernel Size | Formula |
   |-----------|------------|---------|
   | Nearest | 1x1 | Picks the closest source pixel |
   | Bilinear | 2x2 | Weighted average by distance: `f(x) = 1 - |x|` |
   | Cubic | 4x4 | Catmull-Rom: `f(x) = (3|x|^3 - 5|x|^2 + 2) / 2` for `|x|<=1`, `(-|x|^3 + 5|x|^2 - 8|x| + 4) / 2` for `1<|x|<=2` |
   | Lanczos | 6x6 | Windowed sinc: `f(x) = sinc(x) * sinc(x/3)` for `|x|<=3` |

   GDAL implements these in `gdalwarpkernel.cpp` with SSE2/NEON SIMD optimizations. The
   kernel functions are registered in `apfGWKFilter[]` (see `gdalwarpkernel.cpp` lines 84-123).
   Multi-threaded warping splits the output into horizontal strips processed by a thread pool
   (`GWKThreadsCreate()` allocates per-thread transformer clones).

### Step 4: Compression

After reprojection, pixel data must be compressed for storage and serving. The choice
depends on the imagery type:

- **JPEG** (lossy): Best for natural imagery (RGB satellite/aerial photos). Typically
  quality 75-85. With YCbCr color space encoding, the chrominance channels are subsampled
  2:1, effectively halving color resolution while preserving luminance detail. COG + JPEG
  tiles are typically 15-30 KB each.

- **DEFLATE/ZSTD** (lossless): Best for classified data, elevation, or any data where
  every pixel value matters. DEFLATE uses LZ77 + Huffman coding. ZSTD provides similar
  ratios with faster decompression. Predictors improve compression by storing differences
  between adjacent pixels: predictor 2 (horizontal differencing) for integer data, predictor
  3 (floating-point differencing) for float data.

- **LZW** (lossless): Dictionary-based compression. Widely supported. Good default for
  mixed workloads.

- **WebP** (lossy or lossless): Better compression ratios than JPEG at equivalent quality.
  Requires relatively recent GDAL builds. Only supports INTERLEAVE=PIXEL.

- **JPEG XL** (lossy or lossless): Next-generation codec with excellent compression ratios.
  Emerging support in GDAL.

At the byte level, a JPEG-compressed tile in a TIFF file stores the JPEG bitstream
directly in the tile data region. The TIFF tag `JPEGTABLES` (tag 347) holds the shared
Huffman and quantization tables, and each tile contains a JPEG abbreviated image data
stream referencing those tables.

### Step 5: Overview / Pyramid Generation

Overviews are reduced-resolution copies of the image. They enable fast rendering at low zoom
levels without reading the full-resolution data.

#### How Overview Levels Are Computed

For a standard power-of-two pyramid (non-tiling-scheme), overview dimensions are computed by
repeatedly halving:

```
Level 0 (full res): 40960 x 20480
Level 1 (2x):       20480 x 10240
Level 2 (4x):       10240 x  5120
Level 3 (8x):        5120 x  2560
Level 4 (16x):       2560 x  1280
Level 5 (32x):       1280 x   640
Level 6 (64x):        640 x   320
```

Generation stops when both dimensions fall below the tile block size (typically 512 for COGs).
This means the coarsest overview fits in a single tile, which becomes the "thumbnail" level.

For tiling-scheme-aligned COGs (e.g., `TILING_SCHEME=GoogleMapsCompatible`), overview
dimensions are computed from the tile matrix set resolution ratios. The COG driver walks
backward through zoom levels from the selected `nZoomLevel` (see `cogdriver.cpp` lines
1032-1062), computing dimensions from the ratio of resolutions at each level rather than
assuming power-of-two.

#### The Resampling Process

Overview generation reads blocks of full-resolution pixels and produces a single overview
pixel from a window of source pixels. The core function is
`GDALRegenerateOverviewsMultiBand()` (in `gcore/overview.cpp`), which:

1. Iterates over the overview in chunks sized to match the overview's block dimensions
2. For each output chunk, reads the corresponding region from the source band (with the
   appropriate scale factor)
3. Applies the resampling kernel (`GDALResampleChunk_Near`, `GDALResampleChunk_Average`,
   etc.) to produce each overview pixel
4. Writes the completed overview chunk

For nearest-neighbor resampling, this is a simple indexed lookup: for each output pixel at
`(dstX, dstY)`, pick the source pixel at `(floor(0.5 + dstX * srcWidth/dstWidth), ...)`.
For average resampling, every source pixel in the contributing window is averaged with equal
weight. GDAL uses SSE2/AVX2 intrinsics for byte and uint16 average computation on x86.

The total extra storage for a complete power-of-two pyramid is `1/3` of the full-resolution
data (the geometric series `1/4 + 1/16 + 1/64 + ... = 1/3`).

### Step 6: Tiling / Grid Alignment

The image is divided into a grid of fixed-size tiles, typically 256x256 or 512x512 pixels.
In a TIFF file, tiles are defined by the `TILEWIDTH` and `TILELENGTH` tags. Each tile is
independently compressed and stored at an offset recorded in the `TileOffsets` (tag 324)
array, with its compressed size in `TileByteCounts` (tag 325).

#### Web Mercator Tile Grid

The global Web Mercator tile grid maps the full Earth extent onto a square:

```
At zoom level z:
  - Grid is 2^z x 2^z tiles
  - Each tile is 256 (or 512) pixels
  - Total pixels: 256 * 2^z per axis
  - Resolution (at equator): 2 * pi * 6378137 / (256 * 2^z) meters/pixel
```

At zoom 0, the entire world fits in one 256x256 tile at ~156543 m/pixel resolution. At
zoom 18, each tile covers about 0.6 m/pixel (sub-meter resolution).

The tile at position `(x, y)` at zoom `z` covers the geographic region:

```
Resolution = 2 * pi * 6378137 / (256 * 2^z)
OriginShift = 2 * pi * 6378137 / 2  (= 20037508.342789244)

Tile bounds in meters:
  minX = x * 256 * resolution - originShift
  minY = y * 256 * resolution - originShift
  maxX = (x + 1) * 256 * resolution - originShift
  maxY = (y + 1) * 256 * resolution - originShift
```

(These formulas are from `gdal2tiles.py`'s `GlobalMercator` class.)

For a COG aligned to the Google Maps tiling scheme, the COG driver computes which tiles the
imagery overlaps (lines 415-497 in `cogdriver.cpp`):

```
tileExtent = resolution * blockSize
nTLTileX = floor((minX - originX + epsilon) / tileExtent)
nTLTileY = floor((originY - maxY + epsilon) / tileExtent)
nBRTileX = ceil((maxX - originX - epsilon) / tileExtent)
nBRTileY = ceil((originY - minY - epsilon) / tileExtent)
```

The image is then padded to align with tile boundaries, ensuring that internal tiles align
exactly with the global grid. This is critical for COGs that will be served alongside other
COGs -- tile boundaries must match.

### Step 7: Storage and Indexing

The tiled, compressed, pyramided image is stored in one of several forms:

- **COG (Cloud Optimized GeoTIFF)**: A single file with IFDs (Image File Directories) chained
  from full-resolution to coarsest overview, but tile data ordered coarsest-first on disk.
  The file layout is specifically ordered so that a reader can:
  1. Read the TIFF header (first 8-16 bytes)
  2. Follow IFD pointers to find the desired overview level
  3. Read `TileOffsets` and `TileByteCounts` arrays for that IFD
  4. Issue a byte-range read for the specific tile

- **Tile directory** (z/x/y structure): Individual tile images stored as
  `{z}/{x}/{y}.{format}` in a filesystem or object store. Generated by tools like
  `gdal2tiles.py`. Each tile is a standalone PNG, JPEG, or WebP file.

- **MBTiles**: SQLite database with a `tiles` table keyed by `(zoom_level, tile_column,
  tile_row)`. Tile data is stored as a blob. Uses TMS y-axis convention (origin at
  bottom-left).

- **Flat-file tile stores** (GeoPackage, PMTiles): Binary containers with their own tile
  index structures. PMTiles uses a compact Hilbert-curve-ordered index for HTTP range
  requests.

### Step 8: Runtime Serving

When a user pans their web map to a new area, the client library (Leaflet, OpenLayers,
Cesium, Mapbox GL JS) computes which tiles are visible:

1. **Viewport to tile coordinates**: The client converts the visible extent (in geographic
   or projected coordinates) to tile indices at the current zoom level
2. **Tile request**: For each needed tile, an HTTP request is sent to the tile server:
   `GET /tiles/{z}/{x}/{y}.png`
3. **Server processing**: The server locates the tile data (from a COG, tile directory,
   MBTiles, or generates it on the fly) and returns the compressed image bytes
4. **Client rendering**: The browser's image decoder decompresses the tile and the mapping
   library composites it into the canvas at the correct geographic position

---

## What GDAL Does Under the Hood

### `gdal_translate -of COG`: The COG Creation Pipeline

When you run `gdal_translate -of COG input.tif output.tif`, the COG driver
(`frmts/gtiff/cogdriver.cpp`) orchestrates a multi-stage pipeline:

**Stage 1: Warping (conditional)**

If `TARGET_SRS` or `TILING_SCHEME` is specified, the driver runs `COGGetWarpingCharacteristics()`
to compute the output bounds, resolution, and zoom level in the target tiling scheme. It then
calls `CreateReprojectedDS()` which:
- Builds a `gdalwarp` argument list (target SRS, extent, size, resampling method)
- Invokes `GDALWarp()` internally to produce a temporary reprojected GeoTIFF
- Uses ZSTD or LZW compression on the temporary file to reduce I/O

If the source already matches the target CRS and bounds, this stage is skipped entirely
(see `cogdriver.cpp` lines 865-875).

**Stage 2: Overview generation**

The driver computes overview dimensions. For tiling-scheme COGs, it walks the tile matrix
zoom levels backward. For custom COGs, it halves dimensions until both are below the block
size threshold (default 512).

It then calls `GTIFFBuildOverviewsEx()` to generate the overviews into a temporary `.ovr.tmp`
file. This function (in `gt_overview.cpp`) creates TIFF IFDs for each overview level, then
populates them using `GDALRegenerateOverviewsMultiBand()`.

If the source has a mask band, a separate `.msk.ovr.tmp` is generated.

**Stage 3: Final assembly**

The driver invokes `GDALCreateCopy()` with the GTiff driver and `COPY_SRC_OVERVIEWS=YES`.
This triggers the GTiff writer to:
1. Write a temporary file with the full-resolution image data (tiled, compressed)
2. Copy overview data from the `.ovr.tmp` file as additional IFDs
3. Rewrite the file in COG order: ghost IFD marker, overviews from coarsest to finest,
   then full-resolution data
4. Place `TileOffsets` and `TileByteCounts` at the beginning of each IFD so they can be
   read with minimal seek operations

The compression codec, quality, predictor, interleave, and block size are all set from the
creation options (`COMPRESS`, `QUALITY`, `PREDICTOR`, `BLOCKSIZE`, etc.).

### `gdalwarp`: How Reprojection Actually Works

The reprojection pipeline in GDAL consists of layered components:

**1. Transformer setup** (`alg/gdaltransformer.cpp`)

`GDALCreateGenImgProjTransformer2()` builds a chain:
- **Source pixel-to-georef**: The affine geotransform (or GCP/RPC polynomial)
- **Source CRS to target CRS**: Delegates to the PROJ library. PROJ handles datum
  transformations (e.g., NAD27 to WGS 84 via grid shifts), ellipsoid changes, and map
  projection math. This can be a multi-step pipeline (e.g., UTM inverse -> geographic on
  source datum -> datum transform -> geographic on target datum -> Web Mercator forward).
- **Target georef-to-pixel**: The inverse of the output geotransform

The transformer operates bidirectionally: given a destination pixel, it returns the
corresponding source pixel (and vice versa). The `bDstToSrc` flag controls direction.

**2. Approximate transformer** (`GDALCreateApproxTransformer2`)

Evaluating the full PROJ pipeline for every pixel is expensive. GDAL wraps the exact
transformer in an approximation: it evaluates exact coordinates at the endpoints of each
scanline chunk, then linearly interpolates between them. If the error exceeds a threshold
(default: 0.125 pixels), the chunk is subdivided. This reduces PROJ calls by orders of
magnitude.

**3. Warp operation** (`alg/gdalwarpoperation.cpp`)

`GDALWarpOperation::ChunkAndWarpImage()` implements the memory-managed chunking:
- Walks the edges of the output region, back-transforming to source coordinates
- Computes the bounding box of required source data
- Estimates memory for source buffers, destination buffers, and density/validity masks
- If memory exceeds `dfWarpMemoryLimit`, splits the output region and recurses
- Calls `WarpRegion()` for each chunk that fits

**4. Warp kernel** (`alg/gdalwarpkernel.cpp`)

The innermost loop. `GDALWarpKernel::PerformWarp()` selects a specialized function based on
data type, resampling algorithm, and mask configuration. For example:
- `GWKCubicNoMasksOrDstDensityOnlyByte`: optimized cubic resampling for byte data without masks
- `GWKBilinearNoMasksOrDstDensityOnlyFloat`: bilinear for float data
- `GWKAverageOrMode`: average/mode resampling (processes arbitrary polygonal overlap)

Each specialized function iterates over output pixels, calls the transformer to get source
coordinates, applies the resampling kernel, and writes the result. Multi-threaded execution
splits the output vertically into strips, each processed by a thread from a pool
(`GWKThreadsCreate()`). Each thread gets a cloned transformer to avoid contention.

### `gdaladdo`: How Overviews Are Computed

`gdaladdo input.tif 2 4 8 16` adds internal overviews at 2x, 4x, 8x, and 16x reduction.

The tool (`apps/gdaladdo.cpp`) calls `GDALDataset::BuildOverviews()`, which delegates to
the format driver. For GeoTIFF, this calls `GTIFFBuildOverviewsEx()` which:

1. Creates new TIFF IFDs for each overview level with appropriate dimensions
2. Sets tile size, compression, and other tags matching the creation options
3. Calls `GDALRegenerateOverviewsMultiBand()` to populate pixel data
4. For partial refreshes (`PartialRefresh()`), only the specified rectangular region is
   recomputed -- useful for updating a small area of a large mosaic

The maximum number of overview levels is capped at 128 (`knMaxOverviews` in `gt_overview.cpp`).

The core resampling in `overview.cpp` supports:
- **Nearest**: direct index lookup (no interpolation)
- **Average**: mean of all contributing source pixels, with SIMD optimizations for common
  data types
- **Bilinear/Cubic/CubicSpline/Lanczos**: weighted kernel functions identical to those used
  in warping
- **Mode**: most common value (for classified/categorical data)
- **RMS**: root-mean-square (for elevation/DEM data)

### `gdal2tiles.py`: How the Tile Pyramid Is Generated

`gdal2tiles.py` generates a directory of individual tile images compatible with web mapping
libraries.

The script (`swig/python/gdal-utils/osgeo_utils/gdal2tiles.py`) defines coordinate
conversion classes:

- **`GlobalMercator`**: Handles EPSG:3857 tiles (Google/OSM compatible). Key formulas:
  ```python
  initialResolution = 2 * pi * 6378137 / tile_size  # 156543.03... for 256
  originShift = 2 * pi * 6378137 / 2.0              # 20037508.34...

  # Lat/lon to meters
  mx = lon * originShift / 180.0
  my = log(tan((90 + lat) * pi / 360.0)) / (pi / 180.0) * originShift / 180.0

  # Resolution at zoom z
  resolution = initialResolution / (2 ** z)

  # Meters to tile coordinates
  tx = int((mx + originShift) / (resolution * tile_size))
  ty = int((my + originShift) / (resolution * tile_size))
  ```

- **`GlobalGeodetic`**: Handles EPSG:4326 tiles (Google Earth compatible). The world is
  2 tiles wide at zoom 0 (360 degrees / tile_size resolution).

The generation process:
1. Open the input raster and determine its extent, CRS, and resolution
2. Compute the appropriate zoom level range (min zoom where the image covers at least one
   tile, max zoom matching the native resolution)
3. For each zoom level, iterate over every tile that overlaps the image extent
4. For each tile, compute its geographic bounds, read the corresponding region from the
   source raster (with reprojection if needed via a VRT), resample to tile_size x tile_size
   pixels, and write as PNG/JPEG/WebP
5. Optionally generate KML SuperOverlay files and HTML viewer pages

Multi-processing support splits tile generation across worker processes, each opening its own
copy of the source dataset to avoid GIL contention.

---

## Building a Pipeline Without GDAL

GDAL is a monolithic library that bundles projection, format I/O, resampling, and tiling into
one package. Here is what you need if you want to build equivalent functionality in individual
libraries.

### C/C++ Libraries

| Library | What It Provides |
|---------|-----------------|
| **PROJ** (`proj.org`) | Coordinate transformations and datum shifts. The same library GDAL uses internally. Provides `proj_create_crs_to_crs()` and `proj_trans()`. |
| **libtiff** | Reading and writing TIFF files (including BigTIFF). Handles IFDs, tags, compression codecs. Does not understand geospatial metadata. |
| **libgeotiff** | GeoTIFF extension for libtiff. Reads/writes GeoKeys (CRS, geotransform). |
| **GEOS** | Computational geometry (intersection, buffering). Not needed for basic tiling but useful for spatial queries and clipping. |
| **libjpeg-turbo / libpng / libwebp** | Image codec libraries for tile encoding. libjpeg-turbo provides SIMD-accelerated JPEG encoding/decoding. |
| **libdeflate** | Fast DEFLATE compression/decompression. Can replace zlib for GeoTIFF DEFLATE tiles. |
| **zstd** | Zstandard compression. Faster decompression than DEFLATE at similar ratios. |

**What you must implement yourself**:
- Resampling kernels (bilinear, cubic, Lanczos)
- Affine geotransform handling
- Overview generation loop
- Tile grid calculation and alignment
- COG file layout ordering (IFD placement, ghost IFDs)

### Rust Crates

| Crate | What It Provides |
|-------|-----------------|
| `gdal` | Rust bindings to the GDAL C library. Provides the full GDAL feature set but requires the GDAL shared library at runtime. |
| `proj` | Bindings to the PROJ library for coordinate transformations. |
| `tiff` | Pure-Rust TIFF reader/writer. Handles standard TIFF structure but limited GeoTIFF support. |
| `image` | General-purpose image processing (resize, encode/decode PNG/JPEG/WebP). |
| `geo` | Geometric types and algorithms (Point, Polygon, intersection). |
| `cogbuilder` | COG-specific TIFF writer handling overview ordering and tile layout. |
| `geotiff` | GeoTIFF metadata parsing (GeoKeys, CRS extraction). |

**Minimum viable Rust pipeline**: `tiff` (read source) + `proj` (reproject) + `image`
(resample/encode) + custom tile grid math + `tiff` or `cogbuilder` (write tiles/COG).

### Go Libraries

| Library | What It Provides |
|---------|-----------------|
| `golang.org/x/image/tiff` | Basic TIFF reading (not writing). Limited codec support. |
| Standard `image` package | PNG/JPEG encoding/decoding. Basic image manipulation. |
| `github.com/chai2010/tiff` | Extended TIFF support including writing. |

Go lacks mature pure-Go libraries for geospatial raster processing. Practical Go tile
servers typically use one of:
- CGo bindings to GDAL (e.g., `github.com/lukeroth/gdal`)
- Shell out to GDAL command-line tools for preprocessing
- Serve pre-tiled data (read COGs via HTTP range requests using pure Go HTTP + TIFF parsing)

**What you must implement yourself** (beyond what C/C++ requires):
- CRS handling and PROJ integration (no pure-Go PROJ equivalent exists)
- GeoTIFF metadata parsing
- All resampling and overview generation

### Python

| Library | What It Provides |
|---------|-----------------|
| **rasterio** | Pythonic GDAL wrapper. Read/write any GDAL-supported format. Windowed reading, reprojection, resampling. |
| **rio-tiler** | Dynamic tiling from COGs. Reads windowed regions, applies color maps, returns tile images. Powers many tile servers. |
| **rio-cogeo** | COG creation and validation. Wraps `gdal_translate -of COG` with sensible defaults. |
| **Pillow** | Image encoding/decoding (PNG, JPEG, WebP). No geospatial awareness. |
| **pyproj** | Python bindings to PROJ. Coordinate transformations without GDAL. |
| **numpy** | Array operations. Enables custom resampling kernels on raster arrays. |
| **mercantile** | Pure-Python tile coordinate calculations (lat/lon to tile x/y/z). |

**Minimum viable Python pipeline**: `rasterio` (handles everything through GDAL) or
`pyproj` (projections) + `Pillow` (image I/O) + `numpy` (resampling) + `mercantile`
(tile math).

### The Minimum Viable Set

For a basic tile server that serves pre-processed imagery, you need:

1. **A way to read the source format** (libtiff, rasterio, Rust `tiff` crate)
2. **Coordinate math** to convert tile x/y/z to geographic bounds (pure math, ~50 lines)
3. **Pixel extraction** to read the region of the source image corresponding to a tile
4. **Resampling** to scale extracted pixels to tile dimensions (bilinear is the practical
   minimum for acceptable visual quality)
5. **Image encoding** to compress the tile as PNG or JPEG
6. **An HTTP server** to route tile requests

If the source imagery is already in the target CRS and has overviews, you can skip
reprojection and overview generation entirely -- just extract and encode tiles.

---

## Runtime vs Build-Time Operations

### Build-Time Operations (Must Happen Before Serving)

These operations are too expensive to perform on every tile request:

| Operation | Why Build-Time | Typical Cost |
|-----------|---------------|--------------|
| **Format conversion** | Writing a COG requires reading the entire source, generating overviews, and rewriting in COG layout | Minutes to hours for large datasets |
| **Overview generation** | Requires reading every pixel of the full-resolution image | Proportional to image size; adds ~33% data |
| **Reprojection** (full) | Transforms every pixel through PROJ pipeline | CPU-intensive; the warp kernel is the bottleneck |
| **Mosaic assembly** | Combining multiple source images into a single seamless layer | I/O-bound; requires reading all sources |
| **Spatial indexing** | Building R-trees, tile index databases, MBTiles | O(n log n) for n tiles |
| **Lossy compression** | JPEG/WebP encoding with quality selection | Per-tile cost is small but total is large |

### Runtime Operations (Can Happen Per-Request)

These are fast enough to perform on every tile request, especially with COGs:

| Operation | How It Works | Typical Cost |
|-----------|-------------|--------------|
| **Tile slicing from COG** | HTTP range request to read one tile's compressed bytes directly from the file | Single I/O: 10-50 KB read |
| **Decompression** | Decode JPEG/DEFLATE/ZSTD for the requested tile only | 0.1-2 ms per tile |
| **Color mapping** | Apply a colormap or color ramp to single-band data | Array lookup, <1 ms |
| **Band math** | Compute indices (NDVI = (NIR-R)/(NIR+R)) from raw bands | Per-pixel arithmetic, 1-5 ms |
| **Reprojection** (lightweight) | Reproject a small tile-sized window (e.g., 256x256 pixels) | Feasible but slower than pre-projected |
| **Contrast stretching** | Linear or histogram stretch for visualization | Array math, <1 ms |
| **PNG/WebP encoding** | Compress the final tile for HTTP response | 1-10 ms depending on codec and tile size |

### Disk Space vs Memory vs Compute Tradeoffs

| Strategy | Disk | Memory | Compute | Best For |
|----------|------|--------|---------|----------|
| **Pre-tiled directory** (z/x/y) | Highest (every tile stored separately) | Lowest (serve static files) | Lowest (no processing) | Simple static hosting, CDN-friendly |
| **COG with overviews** | Medium (one file with overviews = ~1.33x source) | Low (read one tile at a time) | Low (decompress only) | Cloud storage, HTTP range requests |
| **COG without overviews** | Low (one file, no pyramid) | Higher (must read/resample at runtime) | Higher (must generate overview tiles on the fly) | Infrequently accessed data |
| **Raw source + runtime processing** | Lowest (source data only) | Highest (load regions, warp, resample) | Highest (full pipeline per request) | Dynamic visualization, interactive analysis |

### Why COGs Shift Work from Build-Time to Runtime

A traditional tile pipeline (e.g., `gdal2tiles.py`) pre-renders every tile at every zoom
level. This means:
- Build-time is proportional to the total number of tiles across all zoom levels
- Storage is proportional to the total tile count
- Serving is a simple static file lookup

A COG stores the imagery and overviews in a single file. The tile server reads just the
needed tile at runtime by:
1. Reading the IFD to find the tile offset and size
2. Issuing a byte-range read for that tile
3. Decompressing and encoding the response

**When COG runtime serving is good**:
- The imagery is accessed infrequently (pre-tiling wastes storage on tiles never viewed)
- The dataset is very large with sparse access patterns
- You need to support multiple visualizations (different band combinations, color maps) from
  the same source data
- You want to avoid the build-time cost of pre-tiling millions of tiles

**When COG runtime serving is bad**:
- The imagery is accessed at very high frequency (the per-request overhead adds up)
- You need guaranteed sub-10ms response times (decompression and encoding add latency)
- The client library does not support range requests (e.g., some legacy WMS clients)

---

## The COG Range Request Story

Here is exactly what happens when a web client requests tile `z=14, x=8192, y=5120` from a
Cloud Optimized GeoTIFF served via HTTP.

### 1. Client Determines Tile Coordinates

The web mapping library (e.g., OpenLayers, Cesium) computes which tiles are visible in the
current viewport. For a given geographic location and zoom level:

```
resolution = 2 * pi * 6378137 / (256 * 2^14) = 9.5546... m/pixel
originShift = 20037508.342789244

# Geographic point to Mercator meters
mx = lon * originShift / 180
my = log(tan((90 + lat) * pi / 360)) / (pi / 180) * originShift / 180

# Meters to tile coordinates
tileX = floor((mx + originShift) / (resolution * 256))
tileY = floor((originShift - my) / (resolution * 256))  # XYZ convention (top-origin)
```

### 2. HTTP Range Request to the COG

The tile server (or a client-side library like `geotiff.js`) knows that the COG file
contains tile data accessible via byte ranges. The initial metadata fetch happens once:

**Request 1**: Read the TIFF header (first 16 bytes for BigTIFF, 8 for classic TIFF):
```
GET /imagery.tif
Range: bytes=0-15
```

The header reveals the byte order (little-endian or big-endian), TIFF version (classic 42
or BigTIFF 43), and the offset to the first IFD.

**Request 2**: Read the first IFD (the **full-resolution image** in a COG). The IFD chain
links from finest to coarsest resolution. Each IFD's tags include `ImageWidth`,
`ImageLength`, `TileWidth`, `TileLength`, `TileOffsets`, and `TileByteCounts`.

### 3. Finding the Right IFD (Overview Level)

A COG stores IFDs in order from **finest to coarsest** resolution (full-resolution first,
then progressively smaller overviews). However, the actual **tile data bytes** on disk are
ordered coarsest-to-finest (smallest overview data first, full-resolution data last). This
separation of IFD metadata from tile data is what makes COGs efficient for HTTP range requests.

```
COG IFD chain (for a 40960x40960 image with 256x256 tiles):

IFD 0: 40960x40960 pixels (full res,         zoom ~14)  <-- first IFD
IFD 1: 20480x20480 pixels (overview level 1, zoom ~13)
IFD 2: 10240x10240 pixels (overview level 2, zoom ~12)
IFD 3: 5120x5120 pixels   (overview level 3, zoom ~11)
IFD 4: 2560x2560 pixels   (overview level 4, zoom ~10)
IFD 5: 1280x1280 pixels   (overview level 5, zoom ~9)
IFD 6: 640x640 pixels     (overview level 6, zoom ~8)
IFD 7: 320x320 pixels     (overview level 7, zoom ~7)
IFD 8: 160x160 pixels     (overview level 8, zoom ~6)

Tile data on disk (byte order):
[IFD metadata (all IFDs)] [overview 8 tiles] ... [overview 1 tiles] [full-res tiles]
```

For tile `z=14`, the full-resolution IFD (IFD 0) is selected.

### 4. Locating the Tile Within the IFD

The IFD's `TileOffsets` and `TileByteCounts` arrays are indexed linearly. For a tiled image:

```
tilesAcross = ceil(imageWidth / tileWidth)
tileIndex = tileRow * tilesAcross + tileCol
```

Where `tileCol` and `tileRow` are the tile's position within this IFD (derived from the
requested x/y minus the COG's origin tile). The server reads:

```
tileOffset = TileOffsets[tileIndex]
tileSize = TileByteCounts[tileIndex]
```

**Request 3**: Fetch the tile data:
```
GET /imagery.tif
Range: bytes={tileOffset}-{tileOffset + tileSize - 1}
```

This returns the raw compressed tile bytes (e.g., a JPEG bitstream).

### 5. Decompression and Delivery

The server (or client) decompresses the tile data according to the TIFF `Compression` tag:

| Compression Tag Value | Codec | Decompression |
|----------------------|-------|---------------|
| 1 | None | Copy raw bytes |
| 5 | LZW | Dictionary decode |
| 7 | JPEG (new-style) | JPEG DCT decode (uses shared tables from JPEGTABLES tag) |
| 8 | DEFLATE | zlib inflate |
| 50000 | ZSTD | ZSTD frame decode |
| 50001 | WebP | WebP decode |

For JPEG tiles, the shared quantization and Huffman tables from the TIFF `JPEGTABLES` tag
(tag 347) are prepended to each tile's abbreviated JPEG data to form a complete JPEG image.

The decompressed pixels are then encoded as the final delivery format (PNG, JPEG, or WebP)
and returned to the client. If the COG uses JPEG compression and the client accepts JPEG,
the tile can be served with minimal processing by reconstructing a standalone JPEG from the
abbreviated stream (splicing in tables from the `JPEGTABLES` tag) rather than fully
decoding and re-encoding.

### 6. Total Request Count

An optimized COG reader typically needs:
- **1 request** for the TIFF header and first IFD (can be combined into one large initial fetch)
- **1 request** for the `TileOffsets`/`TileByteCounts` arrays of the target IFD (if not
  already cached from the initial fetch)
- **1 request** for the actual tile data

In practice, a smart reader will prefetch the header, all IFDs, and all offset arrays in
the first 1-2 requests (the COG layout puts these at the beginning of the file), then each
subsequent tile request is a single byte-range fetch. Libraries like `geotiff.js` and
`rio-tiler` implement this caching.

---

## Hot Path Analysis

When a tile server handles a request, these operations are on the critical path. Understanding
their relative costs helps identify bottlenecks.

### The Request Lifecycle

```
Client Request (z/x/y)
    |
    v
[1] Route Parsing + Tile Coordinate Validation    ~0.01 ms
    |
    v
[2] Cache Lookup (in-memory or Redis)             ~0.05-0.5 ms
    |
    (cache miss)
    v
[3] I/O: Read Tile Data                           ~1-50 ms
    |
    v
[4] Decompression                                 ~0.1-2 ms
    |
    v
[5] Processing (if needed)                        ~0-10 ms
    |
    v
[6] Encoding for Response                         ~1-10 ms
    |
    v
[7] HTTP Response                                 ~0.1 ms
```

### I/O: The Dominant Bottleneck

I/O is almost always the bottleneck. The cost depends entirely on the storage backend:

| Backend | Latency per Tile Read | Notes |
|---------|----------------------|-------|
| Local SSD | 0.1-1 ms | Fastest. Seek + read of 10-50 KB compressed tile. |
| Local HDD | 2-10 ms | Seek time dominates. Random access pattern is worst case for HDDs. |
| Network filesystem (NFS/CIFS) | 5-20 ms | Network round-trip + disk I/O. |
| Object store (S3/GCS) | 20-100 ms | HTTP overhead + network latency. First-byte latency is the killer. |
| Object store + CDN (CloudFront) | 1-10 ms (cached) | CDN edge cache eliminates origin latency for popular tiles. |

For COGs on object storage, the key optimization is minimizing the number of HTTP requests.
Caching the IFD metadata and offset arrays after the first access reduces subsequent tile
fetches to a single range request.

### Decompression Cost by Codec

Benchmarked on a single 256x256 RGB tile (typical sizes in parentheses):

| Codec | Compressed Size | Decompress Time | Throughput |
|-------|----------------|-----------------|------------|
| None | ~192 KB | ~0 ms (memcpy) | Memory bandwidth limited |
| LZW | ~40-80 KB | ~0.2-0.5 ms | ~400-800 MB/s |
| DEFLATE | ~30-60 KB | ~0.2-0.5 ms | ~400-1000 MB/s (libdeflate) |
| ZSTD | ~25-50 KB | ~0.1-0.3 ms | ~800-1500 MB/s |
| JPEG | ~15-30 KB | ~0.3-0.8 ms | ~200-400 MB/s (libjpeg-turbo) |
| WebP | ~10-25 KB | ~0.5-1.5 ms | ~100-300 MB/s |

ZSTD offers the best decompression speed for lossless codecs. JPEG is slightly slower due to
DCT computation but produces much smaller tiles. WebP offers the smallest tiles but the
slowest decompression.

### Resampling Cost (If Needed at Runtime)

If the requested zoom level does not exactly match a stored overview, the server must
resample. Cost scales with the number of input pixels per output pixel:

| Algorithm | Cost per Output Pixel | Quality |
|-----------|----------------------|---------|
| Nearest | ~1 ns (index lookup) | Poor (aliasing artifacts) |
| Bilinear | ~4 ns (2x2 weighted average) | Good for continuous data |
| Cubic | ~16 ns (4x4 kernel) | Better for imagery |
| Lanczos | ~36 ns (6x6 kernel) | Best quality, highest cost |

For a 256x256 tile at cubic resampling: 65,536 pixels * 16 ns = ~1 ms. Bilinear is typically
sufficient for runtime resampling.

### Encoding Cost for HTTP Response

The final step is encoding the tile as a deliverable image format:

| Format | Encode Time (256x256 RGB) | Compressed Size | Notes |
|--------|--------------------------|-----------------|-------|
| PNG (compression=1) | ~1-2 ms | ~40-80 KB | Lossless. Fast at low compression levels. |
| PNG (compression=6) | ~5-10 ms | ~30-60 KB | Better compression, much slower. |
| JPEG (quality=85) | ~0.5-1 ms | ~15-30 KB | Fast with libjpeg-turbo SIMD. |
| WebP (quality=80) | ~2-5 ms | ~10-20 KB | Smaller than JPEG, slower to encode. |

**Practical optimization**: If the COG uses JPEG compression and the client accepts JPEG
tiles, it may be possible to avoid full decompression and re-encoding. However, JPEG tiles
inside a TIFF are **abbreviated JPEG streams** (per the TIFF JPEG "new-style" spec):
they reference shared Huffman and quantization tables stored in the TIFF `JPEGTABLES` tag
(tag 347) rather than containing their own. To serve a tile as a standalone JPEG, the
server must reconstruct a complete JPEG by splicing the tables from `JPEGTABLES` into the
tile's abbreviated stream (inserting the DQT/DHT segments after the SOI marker). This
reconstruction is far cheaper than full decode + re-encode, but serving the raw tile bytes
without reconstruction produces a malformed JPEG that most decoders will reject.

### Where Bottlenecks Typically Are

**Low-traffic tile server (local storage)**:
- Bottleneck: CPU (encoding + decompression)
- Solution: Use JPEG-passthrough for JPEG COGs; use fast codecs (ZSTD)

**High-traffic tile server (object storage)**:
- Bottleneck: I/O latency (object store round-trips)
- Solution: CDN caching, tile cache (Redis/memcached), pre-tile hot regions

**Dynamic tile server (on-the-fly processing)**:
- Bottleneck: CPU (band math + resampling + encoding)
- Solution: Cache processed tiles, use lower-quality resampling (bilinear over Lanczos),
  limit concurrent processing

**Memory pressure** is rarely the bottleneck for individual tile requests (a 256x256 RGB
tile is 192 KB uncompressed) but becomes significant when serving many concurrent requests
with runtime processing. A server handling 1000 concurrent tile requests with cubic
resampling uses approximately 1000 * 192 KB * 4 (source window) = ~750 MB.
