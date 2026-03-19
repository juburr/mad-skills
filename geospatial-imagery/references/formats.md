# Geospatial Imagery File Formats Reference

This reference covers the major file formats used in geospatial imagery workflows, including archival formats, cloud-native formats, scientific data formats, and tile serving formats.

---

## GeoTIFF / Cloud-Optimized GeoTIFF (COG)

GeoTIFF is the most widely used raster format in geospatial work. It extends the TIFF image format with embedded georeferencing metadata through GeoKeys. Cloud-Optimized GeoTIFF (COG) is a GeoTIFF with a specific internal layout optimized for HTTP range request access.

**GDAL Driver:** `GTiff` (reading/writing), `COG` (write-only, generates COG files)

### Internal Structure

A GeoTIFF file uses the standard TIFF structure:

- **TIFF Header**: 8 bytes (classic) or 16 bytes (BigTIFF). Contains byte order mark, magic number, and offset to the first IFD.
- **Image File Directory (IFD)**: A list of tag entries describing the image. Each IFD represents one image or overview level. Tags include dimensions, bit depth, compression, tile/strip offsets, and byte counts.
- **Tag Data**: Values too large to fit inline in the IFD entry (e.g., TileOffsets, TileByteCounts arrays) are stored at offsets referenced by the IFD.
- **Image Data**: Actual pixel data stored as either strips (rows) or tiles (rectangular blocks).

#### GeoTIFF-Specific Tags and GeoKeys

GeoTIFF encodes coordinate reference information into six TIFF tags:

| Tag | Code | Purpose |
|-----|------|---------|
| `ModelTiepointTag` | 33922 | Raster-to-model tiepoint pairs (I, J, K, X, Y, Z) |
| `ModelPixelScaleTag` | 33550 | Pixel size in model units (ScaleX, ScaleY, ScaleZ) |
| `ModelTransformationTag` | 34264 | Full 4x4 affine transformation matrix (alternative to tiepoint+scale) |
| `GeoKeyDirectoryTag` | 34735 | Directory of GeoKeys referencing CRS parameters |
| `GeoDoubleParamsTag` | 34736 | Double-precision values referenced by GeoKeys |
| `GeoAsciiParamsTag` | 34737 | ASCII strings referenced by GeoKeys (e.g., CRS names) |

Key GeoKeys (from `geokeys.inc` in libgeotiff):

| GeoKey | ID | Purpose |
|--------|----|---------|
| `GTModelTypeGeoKey` | 1024 | Model type: projected (1), geographic (2), geocentric (3) |
| `GTRasterTypeGeoKey` | 1025 | Raster type: PixelIsArea (1) or PixelIsPoint (2) |
| `GTCitationGeoKey` | 1026 | Human-readable CRS description |
| `GeographicTypeGeoKey` | 2048 | Geographic CRS code (e.g., EPSG:4326) |
| `GeogGeodeticDatumGeoKey` | 2050 | Geodetic datum code |
| `GeogEllipsoidGeoKey` | 2056 | Ellipsoid code |
| `GeogSemiMajorAxisGeoKey` | 2057 | Semi-major axis length |
| `ProjectedCSTypeGeoKey` | 3072 | Projected CRS code (e.g., EPSG:32618) |
| `ProjectionGeoKey` | 3074 | Map projection code |
| `ProjCoordTransGeoKey` | 3075 | Coordinate transformation method |
| `VerticalCSTypeGeoKey` | 4096 | Vertical CRS code |
| `VerticalDatumGeoKey` | 4098 | Vertical datum code |
| `CoordinateEpochGeoKey` | 5120 | Coordinate epoch (GeoTIFF 1.1) |

GeoTIFF specification versions: 1.0 (original 1995, Ritter & Ruth) and 1.1 (OGC standard 19-008, clarifies vertical CRS handling).

### Tiling vs. Striping

| Layout | Description | Best For |
|--------|-------------|----------|
| **Stripped** | Data stored in horizontal rows (strips). Default TIFF layout. | Sequential full-image reads, streaming |
| **Tiled** | Data stored in rectangular blocks (e.g., 256x256 or 512x512). | Random access to sub-regions, COGs, large images |

Tile dimensions must be multiples of 16. Common sizes are 256x256 (COGs, web tiles) and 512x512 (large imagery).

### Overview / Pyramid Levels

Overviews are reduced-resolution copies of the image stored as additional IFDs in the same file. They enable fast rendering at small zoom levels without reading the full-resolution data.

- Overview factors are typically powers of 2: 2, 4, 8, 16, ...
- Created with `gdaladdo` or automatically by the COG driver
- Can use different compression than the base image
- Internal overviews reside in the same file; external overviews use `.ovr` sidecar files
- Resampling methods: NEAREST, AVERAGE, BILINEAR, CUBIC, CUBICSPLINE, LANCZOS, MODE, RMS

### Compression Options

| Compression | Type | Notes |
|-------------|------|-------|
| **NONE** | Uncompressed | Largest files, fastest read/write |
| **LZW** | Lossless | Good general-purpose default. Widely supported. |
| **DEFLATE** | Lossless | Slightly better ratio than LZW, slower. Levels 1-9 (or 12 with libdeflate). |
| **ZSTD** | Lossless | Better ratio and faster than DEFLATE at equivalent levels. Levels 1-22. Less universally supported. |
| **LZMA** | Lossless | Best ratio among lossless codecs but very slow. |
| **PACKBITS** | Lossless | Simple run-length encoding. Fast but poor ratio. |
| **JPEG** | Lossy | Good for 8-bit RGB imagery (visualization only). Use PHOTOMETRIC=YCBCR for 2-3x better compression. Quality 1-100. |
| **WEBP** | Lossy/Lossless | Smaller and faster than JPEG. Supports lossless mode. Quality 1-100. |
| **JXL** | Lossy/Lossless | Next-generation. Excellent ratio in both modes. Effort 1-9. |
| **LERC** | Quantized | Purpose-built for floating-point data (e.g., DEMs). Rounds values to user-specified precision (MAX_Z_ERROR). |
| **LERC_DEFLATE** | Quantized+Lossless | LERC with DEFLATE second pass. |
| **LERC_ZSTD** | Quantized+Lossless | LERC with ZSTD second pass. Best for DEM data. |

**Predictor options** (for LZW, DEFLATE, ZSTD):
- `PREDICTOR=1`: No prediction (default)
- `PREDICTOR=2`: Horizontal differencing (good for integer data)
- `PREDICTOR=3`: Floating-point prediction (good for float32/float64 data)

### BigTIFF

Classic TIFF uses 32-bit offsets, limiting files to ~4 GB. BigTIFF uses 64-bit offsets, removing this limit.

```
GDAL creation option: BIGTIFF=YES|NO|IF_NEEDED|IF_SAFER
```

- `IF_NEEDED`: Creates BigTIFF only if uncompressed data exceeds 4 GB
- `IF_SAFER`: Creates BigTIFF if the file *might* exceed 4 GB

### Multi-Band and Bit Depth Support

**Supported data types:** Byte, UInt16, Int16, UInt32, Int32, Float32, Float64, CInt16, CInt32, CFloat32, CFloat64

**Sub-byte data:** NBITS creation option supports 1-7 bits for Byte type, 9-15 for UInt16, 9-31 for UInt32, and 16-bit float.

**Interleave modes:**
- `PIXEL` (BIP): Bands interleaved by pixel. Best for multi-band access of small regions. Required for JPEG YCBCR and WebP compression.
- `BAND` (BSQ): Bands stored sequentially. Best for single-band processing.
- `TILE` (GDAL 3.11+, COG driver only): Per-tile band interleave. A compromise between PIXEL and BAND where all bands for each spatial tile are written together before moving to the next tile. Useful for hyperspectral datasets (hundreds of bands).

### Cloud-Optimized GeoTIFF (COG) Layout

A COG is a valid GeoTIFF with a specific internal ordering designed for efficient HTTP range requests:

```
+-----------------------------------------------------+
| TIFF Header (8 or 16 bytes)                         |
+-----------------------------------------------------+
| IFD: Full resolution image                          |
| Tag values (TileOffsets, TileByteCounts, GeoKeys)   |
+-----------------------------------------------------+
| IFD: Full resolution mask (optional)                |
| Tag values                                          |
+-----------------------------------------------------+
| IFD: Overview level 1 (half resolution)             |
| Tag values                                          |
+-----------------------------------------------------+
| IFD: Overview level 2 (quarter resolution)          |
| Tag values                                          |
+-----------------------------------------------------+
| ...                                                 |
+-----------------------------------------------------+
| Tile data: Smallest overview (read first)           |
+-----------------------------------------------------+
| Tile data: Next overview                            |
+-----------------------------------------------------+
| ...                                                 |
+-----------------------------------------------------+
| Tile data: Full resolution (read last)              |
+-----------------------------------------------------+
```

Key COG properties:
- All IFDs and their tag data are at the file beginning (typically first ~6 KB for moderate images)
- Tile data is ordered from smallest overview to full resolution (progressive rendering)
- A client can read the IFDs with one HTTP request, then fetch specific tiles with targeted range requests
- GDAL includes `validate_cloud_optimized_geotiff.py` for compliance checking

**Ghost header area** (GDAL-specific COG optimization): Immediately after the TIFF header, before the first IFD, GDAL writes ASCII metadata describing the structural layout:

```
GDAL_STRUCTURAL_METADATA_SIZE=000174 bytes
LAYOUT=IFDS_BEFORE_DATA
BLOCK_ORDER=ROW_MAJOR
BLOCK_LEADER=SIZE_AS_UINT4
BLOCK_TRAILER=LAST_4_BYTES_REPEATED
KNOWN_INCOMPATIBLE_EDITION=NO
MASK_INTERLEAVED_WITH_IMAGERY=YES
```

- `BLOCK_LEADER=SIZE_AS_UINT4`: Each tile is preceded by a 4-byte little-endian size field (at TileOffset[i]-4), enabling optimized readers to fetch tile data and its neighbor in a single range request.
- `BLOCK_TRAILER=LAST_4_BYTES_REPEATED`: The last 4 bytes of each tile are repeated after it, allowing integrity verification if the file has been modified by a non-COG-aware writer.
- `KNOWN_INCOMPATIBLE_EDITION`: Set to `YES` by GDAL if the COG is modified in a way that breaks optimization.
- `MASK_INTERLEAVED_WITH_IMAGERY`: When present, mask tile data immediately follows the corresponding imagery tile data, enabling a single range request to fetch both.

**COG creation example:**
```bash
gdal_translate input.tif output.tif \
  -of COG \
  -co COMPRESS=DEFLATE \
  -co BLOCKSIZE=512 \
  -co OVERVIEW_RESAMPLING=LANCZOS \
  -co NUM_THREADS=ALL_CPUS
```

### Strengths and Weaknesses

**Strengths:**
- Universal support across all GIS software and libraries
- COG variant is the de facto cloud-native raster standard
- Supports all data types, band counts, and compression codecs
- Mature ecosystem with extensive GDAL support
- No licensing restrictions

**Weaknesses:**
- No native support for multidimensional data (time series, multiple variables)
- Classic TIFF limited to 4 GB without BigTIFF
- No built-in support for complex metadata hierarchies
- Lossy JPEG compression limited to 8-bit data

---

## NITF / NSIF (National Imagery Transmission Format)

NITF is the standard format used by the U.S. Department of Defense and Intelligence Community for exchanging, storing, and transmitting digital imagery. NSIF (NATO Secondary Imagery Format) is the NATO-standardized variant. The current version is NITF 2.1 (MIL-STD-2500C).

**GDAL Driver:** `NITF` (read: NITF 1.1, 2.0, 2.1, NSIF 1.0; write: NITF 2.0, 2.1, NSIF 1.0)

Related product drivers: CIB (Controlled Image Base), CADRG (Compressed ARC Digitized Raster Graphics), ECRG (Enhanced Compressed Raster Graphics), HRE (High Resolution Elevation). CADRG write support requires GDAL 3.13+.

### File Structure

A NITF file is a segmented container format with a well-defined structure:

```
+---------------------------------------------------+
| File Header                                       |
|   - Version (NITF 2.1 / NSIF 1.0)                |
|   - Security classification                       |
|   - Segment counts and lengths                    |
+---------------------------------------------------+
| Image Segment 1                                   |
|   - Image Subheader (dimensions, bands, CRS)      |
|   - Image Data (compressed or raw)                |
+---------------------------------------------------+
| Image Segment 2 (optional, multi-image support)   |
+---------------------------------------------------+
| ...                                               |
+---------------------------------------------------+
| Graphic Segment (CGM vector graphics, optional)   |
+---------------------------------------------------+
| Text Segment (free-text annotations, optional)    |
+---------------------------------------------------+
| Data Extension Segment (DES, optional)            |
|   - Overflow TREs                                 |
|   - User-defined extensions                       |
+---------------------------------------------------+
| Reserved Extension Segment (RES, optional)        |
+---------------------------------------------------+
```

### Security Markings

Security classification is embedded at both the file and segment level:

| Code | Classification |
|------|---------------|
| T | Top Secret |
| S | Secret |
| C | Confidential |
| R | Restricted |
| U | Unclassified |

Additional fields: codewords, control/handling markings, releasing instructions, declassification type/date, downgrade information, classification authority.

### Compression Options

| Code | Method | Notes |
|------|--------|-------|
| NC | No compression | Default |
| C3 | JPEG | Lossy, 8-bit |
| M3 | JPEG with block map | Multi-block JPEG |
| C8 | JPEG2000 | Lossy or lossless, via Kakadu/ECW/OpenJPEG |
| NM | Uncompressed with block map | |
| VQ | Vector Quantization | Read-only in GDAL |
| ARIDPCM | Adaptive Recursive Interpolated DPCM | Read-only in GDAL |

### RPC (Rational Polynomial Coefficients)

NITF files carry sensor model information via the **RPC00B** (or RPC00A) Tagged Record Extension. RPCs define a mathematical mapping between image pixel coordinates and ground coordinates (latitude, longitude, height) using rational polynomial functions. This enables orthorectification without a full physical camera model.

### Tagged Record Extensions (TREs)

TREs are the primary extensibility mechanism in NITF. They can be attached to the file header, image segments, or data extension segments.

Common TREs (from GDAL's `nitf_spec.xml`, which defines 40+ TRE parsers):

| TRE | Purpose |
|-----|---------|
| RPC00B / RPC00A | Rational Polynomial Coefficients for sensor model (1041 bytes) |
| BLOCKA | High-precision image corner coordinates (123 bytes) |
| ICHIPB | Image chipping (sub-image extraction) parameters (224 bytes) |
| USE00A | Exploitation metadata (sun angle, cloud cover) |
| ACFTB | Aircraft/sensor identification (207 bytes) |
| AIMIDB | Additional image ID metadata (89 bytes) |
| BANDSB | Band-specific metadata (variable length) |
| CSEXRA / CSEXRB | Exploitation reference metadata |
| CSDIDA | Dataset identification (70 bytes) |
| GEOLOB / GEOPSB | Geodetic reference data |
| HISTOA | Image processing history |
| J2KLRA | JPEG2000 layer rate allocation |
| MENSRB | Mensuration parameters |
| MSTGTA | Mission targeting information (101 bytes) |
| PIAIMB / PIAIMC | Imagery metadata (337 / 362 bytes) |
| PRJPSB | Map projection parameters |
| ILLUMB | Illumination conditions |

GDAL exposes TREs in the `TRE` metadata domain (raw backslash-escaped) and `xml:TRE` domain (structured XML with parsed fields). Multiple TREs of the same type are suffixed: `TRENAME`, `TRENAME_2`, `TRENAME_3`, etc.

### Georeferencing

- **IGEOLO**: Image corners in geographic or UTM coordinates (always present in image subheader)
- **BLOCKA TRE**: Higher-precision corner coordinates
- **GeoSDE TRE**: Full coordinate reference system definition
- **RPC00B TRE**: Sensor model for orthorectification

### Multi-Band and Bit Depth

NITF supports arbitrary band counts. Common configurations:
- Panchromatic: 1 band, 8 or 16 bit
- RGB: 3 bands, 8 bit
- Multispectral: 4-8+ bands, 8 or 16 bit
- SAR: Complex I/Q data (represented as complex types in GDAL 3.11+)

### Strengths and Weaknesses

**Strengths:**
- Standard for military/intelligence imagery worldwide
- Rich metadata model with security markings
- Extensible through TREs and DES segments
- Multi-image container support
- Supports JPEG2000 for high compression ratios

**Weaknesses:**
- Complex specification (MIL-STD-2500C is extensive)
- Limited support outside defense/intelligence ecosystems
- Writing support in GDAL is limited to simple NITF 2.1 files
- Many TRE types are specific to defense use cases

---

## JPEG2000

JPEG2000 (ISO/IEC 15444-1) is a wavelet-based image compression standard that offers both lossy and lossless modes with built-in multi-resolution support. It is used in geospatial applications for satellite imagery distribution and as the compression codec inside NITF C8.

**GDAL Drivers:**

| Driver | SDK | License | Notes |
|--------|-----|---------|-------|
| `JP2OpenJPEG` | OpenJPEG | BSD (open source) | Recommended default, multi-threaded since 2.3.2 |
| `JP2KAK` | Kakadu | Commercial | Fastest, best quality, most features |
| `JP2ECW` | ERDAS ECW SDK | Commercial | Also handles ECW format |
| `JP2MrSID` | MrSID DSDK | Commercial | Read-only, also handles MrSID format |

### Compression Architecture

JPEG2000 uses a Discrete Wavelet Transform (DWT) instead of JPEG's Discrete Cosine Transform (DCT):

1. **Color transform**: Optional RGB-to-YCbCr conversion (irreversible for lossy, reversible 5/3 for lossless)
2. **Wavelet transform**: Image decomposed into frequency subbands at multiple resolution levels
3. **Quantization**: Subband coefficients quantized (lossy) or left intact (lossless)
4. **Entropy coding**: EBCOT (Embedded Block Coding with Optimized Truncation) encodes code-blocks independently
5. **Packet assembly**: Code-block bitstreams assembled into packets organized by layer, resolution, component, and position

### Code-Stream Structure

```
Main Header
  - SIZ marker: Image and tile dimensions, components, bit depths
  - COD marker: Coding style (wavelet levels, progression, layers)
  - QCD marker: Quantization parameters
Tile-Part Headers
  Packets (organized by progression order)
    Code-Blocks (independently decodable units)
```

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Tiles** | Independent rectangular regions (e.g., 1024x1024). Each tile compressed separately. |
| **Resolution levels** | Wavelet decomposition levels. Each level halves resolution. Overviews are intrinsic. |
| **Quality layers** | Progressive quality refinement. Client can request lower quality for faster display. |
| **Code-blocks** | Smallest independently decodable units (e.g., 64x64). Enable region-of-interest access. |
| **Precincts** | Groupings of code-blocks. Control spatial locality of packets. |
| **Progression order** | Order of packet transmission: LRCP, RLCP, RPCL, PCRL, CPRL. LRCP (Layer-Resolution-Component-Position) is default. |

### Georeferencing Methods

| Method | Description |
|--------|-------------|
| **GeoJP2** | UUID box containing a GeoTIFF structure (tiepoints, scale, GeoKeys). De facto standard. |
| **GMLJP2** | XML box containing OGC GML with CRS and extent. OGC standard. Supports complex geometries. |
| **World file** | External `.j2w` or `.wld` sidecar file with affine transform parameters. |

GDAL priority (configurable): PAM > GeoJP2 > GMLJP2 > WORLDFILE

### Lossless vs. Lossy

| Mode | Wavelet | Transform | Use Case |
|------|---------|-----------|----------|
| Lossless | 5/3 (Le Gall) | Reversible | Archival, scientific analysis |
| Lossy | 9/7 (CDF) | Irreversible | Distribution, visualization |

Lossless JPEG2000 typically achieves 2:1 to 5:1 compression (worse than GeoTIFF+DEFLATE for many datasets). Lossy mode can achieve 20:1 to 50:1+ with acceptable visual quality.

### Strengths and Weaknesses

**Strengths:**
- Built-in multi-resolution access without separate overview files
- Progressive quality/resolution decoding
- Both lossy and lossless in one format
- Region-of-interest access via code-blocks and precincts
- Standard compression codec in NITF (C8)

**NITF JPEG2000 Profiles (NPJE):**
When using JPEG2000 inside NITF (IC=C8), the NPJE profile (STDI-0006 NCDRD) ensures interoperability. Available profiles via JP2OpenJPEG (GDAL 3.4+ with OpenJPEG 2.5+): `NPJE_VISUALLY_LOSSLESS` (default 3.9 bpp) and `NPJE_NUMERICALLY_LOSSLESS`. These automatically set block size to 1024x1024 and write the J2KLRA TRE.

**Weaknesses:**
- Slower encode/decode than GeoTIFF+DEFLATE or GeoTIFF+ZSTD
- Best implementations (Kakadu) are commercially licensed
- Less universal software support than GeoTIFF
- Not cloud-optimized by default (no COG equivalent, though HTJP2/JPH is emerging)
- Complex specification with many parameters to tune

---

## MrSID (Multi-resolution Seamless Image Database)

MrSID is a proprietary wavelet-based compression format developed at Los Alamos National Laboratory and commercialized by LizardTech (now owned by GeoWGS84 Corp as of 2025). It was designed for very large aerial and satellite images.

**GDAL Driver:** `MrSID` (read-only, requires proprietary DSDK)

### Generations

| Generation | Year | Features |
|------------|------|----------|
| MG2 | 1998 | First commercial release. Lossy wavelet compression. |
| MG3 | 2003 | Improved compression and encoding speed. Supports lossless mode. |
| MG4 | 2009 | Supports lossless, lossy, and "visually lossless." Includes LiDAR point cloud support. Metadata improvements. |

### Compression Technology

MrSID uses wavelet compression similar to JPEG2000 but with proprietary algorithms:

1. Image divided into zoom levels, subbands, subblocks, and bitplanes
2. Multi-resolution structure is intrinsic (like JPEG2000)
3. Selective decompression: any sub-region at any resolution can be extracted without decompressing the entire file
4. Typical compression ratios: 20:1 to 50:1 (lossy), ~2:1 (lossless)

### Licensing Constraints

| Operation | Cost |
|-----------|------|
| Decoding (DSDK) | Free download from Extensis, but proprietary SDK required |
| Encoding (GeoExpress) | Commercial license required |
| GDAL integration | Requires building against proprietary DSDK; GCC version must match SDK |

### Georeferencing

MrSID stores georeferencing using embedded GeoTIFF GeoKeys. Older encoders (pre-1.5) had bugs producing incorrect GeoKeys.

### Strengths and Weaknesses

**Strengths:**
- Excellent compression ratios for large aerial/satellite imagery
- Fast selective decompression of sub-regions
- Intrinsic multi-resolution without separate overviews
- Widely supported in commercial GIS (ArcGIS, Global Mapper, ERDAS)

**Weaknesses:**
- Proprietary format requiring commercial SDK for encoding
- GDAL support is read-only
- No open-source encoder
- Declining usage as COG and other open formats gain adoption
- SDK build compatibility issues (C++ ABI matching)

---

## ECW (Enhanced Compressed Wavelet)

ECW is a proprietary wavelet compression format developed by Earth Resource Mapping (later acquired by ERDAS, then Hexagon Geospatial). Like MrSID, it targets large aerial and satellite imagery.

**GDAL Driver:** `ECW` (read/write, requires proprietary ERDAS ECW/JP2 SDK)

### Compression Technology

ECW uses wavelet compression with characteristics similar to MrSID and JPEG2000:
- Designed for very large images (multi-gigabyte)
- Inherent multi-resolution access
- Selective decompression of arbitrary regions and resolutions
- Streaming support via the ECWP protocol

### Bit Depth Support

| Version | Bit Depth |
|---------|-----------|
| ECW v2 | 8 bits per channel only |
| ECW v3 | Up to 16 bits per channel (UInt16) |

### Licensing Constraints

| Operation | SDK Version | Restriction |
|-----------|-------------|-------------|
| Decompression (desktop) | v5.x | Free for any size |
| Compression (desktop) | v5.x | Requires commercial license |
| Server deployment | v5.x | Requires commercial license |
| Compression | v3.3 | Free for files < 500 MB, commercial for larger |

### Key Creation Options

| Option | Description |
|--------|-------------|
| `TARGET` | Compression target percentage (default 90% grayscale, 95% RGB) |
| `ECW_FORMAT_VERSION` | 2 (default, 8-bit) or 3 (16-bit support) |
| `LARGE_OK` | Enable files exceeding 500 MB (v3.x SDK) |
| `ECW_ENCODE_KEY` | License key for v4.x+ SDKs |
| `PROJ`, `DATUM`, `UNITS` | Coordinate system metadata |

### Streaming Support

ECW supports network streaming via the `ECWP://` protocol (ERDAS APOLLO server). GDAL can read ECW imagery over the network using this protocol.

### Strengths and Weaknesses

**Strengths:**
- Excellent compression ratios for large imagery
- Fast decompression and multi-resolution access
- Network streaming via ECWP protocol
- Regional update capability (ECW v3)

**Weaknesses:**
- Proprietary format with commercial licensing requirements
- ECW v2 limited to 8-bit data
- Minimum image size 128x128 pixels
- Declining usage in favor of open formats
- Complex SDK licensing model

---

## HDF5 / HDF-EOS

HDF5 (Hierarchical Data Format version 5) is a self-describing scientific data format designed for complex, large-scale datasets. HDF-EOS5 extends HDF5 with geospatial data types developed for NASA's Earth Observing System.

**GDAL Driver:** `HDF5` / `HDF5Image` (read-only)

### Hierarchical Structure

```
HDF5 File
  /
  +-- Group: "HDFEOS"
  |   +-- Group: "GRIDS"
  |   |   +-- Dataset: "temperature"     [360 x 720] float32
  |   |   +-- Dataset: "pressure"        [360 x 720] float32
  |   +-- Group: "SWATHS"
  |       +-- Dataset: "radiance"        [2030 x 1354] float32
  |       +-- Dataset: "latitude"        [2030 x 1354] float32
  |       +-- Dataset: "longitude"       [2030 x 1354] float32
  +-- Group: "HDFEOS INFORMATION"
  |   +-- Attribute: StructMetadata.0    (ECS metadata)
  +-- Attributes (global metadata)
```

Key structural elements:
- **Groups**: Hierarchical containers (like directories)
- **Datasets**: N-dimensional arrays of a single data type
- **Attributes**: Metadata attached to groups, datasets, or the file itself
- **Datatypes**: Self-describing, supports integers, floats, strings, compound types

### HDF-EOS5 Data Types

| Type | Description | Georeferencing |
|------|-------------|----------------|
| **Grid** | Regularly spaced data on a map projection | Projection parameters + grid dimensions |
| **Swath** | Satellite track data with irregular spacing | Geolocation arrays (lat/lon per pixel) |
| **Point** | Sparse point observations | Per-point coordinates |

### Compression

HDF5 supports chunked storage with filter pipelines:
- **GZIP/DEFLATE**: Standard lossless compression
- **SZIP**: Fast compression developed by NASA (licensing constraints for encoding)
- **Shuffle filter**: Byte reordering to improve compression of typed data
- **Fletcher32**: Checksum for data integrity
- **Chunk sizes**: User-defined, critical for access pattern performance

### Common Satellite Datasets

| Satellite/Sensor | Format | Example Products |
|-------------------|--------|-----------------|
| MODIS (Terra/Aqua) | HDF4-EOS | Surface reflectance, LST, NDVI |
| OMI (Aura) | HDF-EOS5 | Ozone, aerosol, NO2 columns |
| Sentinel-5P (TROPOMI) | NetCDF-4 (HDF5-based) | Atmospheric composition |
| ICESat-2 | HDF5 | Ice sheet elevation, canopy height |
| GEDI | HDF5 | LiDAR waveforms, canopy height |

### GDAL Access Pattern

HDF5 files containing multiple datasets are accessed via subdataset syntax:

```bash
# List all subdatasets
gdalinfo HDF5:"MOD09GA.hdf5"

# Open a specific subdataset
gdal_translate HDF5:"MOD09GA.hdf5"://HDFEOS/GRIDS/sur_refl_b01 output.tif
```

GDAL 3.1+ implements the multidimensional raster data model for HDF5.

### Strengths and Weaknesses

**Strengths:**
- Self-describing with rich metadata model
- Supports arbitrary-dimensional arrays and complex data types
- Efficient chunked I/O for large datasets
- Standard for NASA/ESA satellite data
- Open specification with open-source library (libhdf5)

**Weaknesses:**
- Not optimized for random spatial access (not tiled like GeoTIFF)
- GDAL support is read-only
- Complex API and file structure
- No single standard for georeferencing (varies by mission/convention)
- Not cloud-optimized; Zarr and Kerchunk are emerging alternatives

---

## NetCDF (Network Common Data Form)

NetCDF is a self-describing, array-oriented scientific data format widely used for climate, weather, and oceanographic data. NetCDF-4 is built on HDF5 and adds compression, chunking, and groups.

**GDAL Driver:** `netCDF` (read/write)

### Versions and Formats

| Version | Based On | Features |
|---------|----------|----------|
| NetCDF-3 (Classic) | Custom binary | Simple arrays, unlimited dimension, no compression |
| NetCDF-3 (64-bit Offset) | Custom binary | Larger variable sizes |
| NetCDF-4 | HDF5 | Groups, compression, chunking, user-defined types |
| NetCDF-4 Classic | HDF5 | NetCDF-4 features with classic data model constraints |

GDAL creation format codes: `NC` (classic), `NC2` (64-bit offset), `NC4` (full), `NC4C` (classic model on HDF5).

### CF (Climate and Forecast) Conventions

CF conventions (CF-1.0 through CF-1.11+) standardize how geospatial and temporal metadata is encoded in NetCDF attributes:

- **`grid_mapping`**: References a variable containing CRS parameters (projection name, ellipsoid, false easting/northing, etc.)
- **Coordinate variables**: 1D arrays sharing dimension names, storing latitude/longitude or projected x/y values
- **`standard_name`**: Standardized vocabulary for variable names (e.g., `air_temperature`, `sea_surface_height`)
- **`units`**: Physical units following UDUNITS library (e.g., `K`, `m/s`, `days since 1850-01-01`)
- **`calendar`**: Time calendar type (standard, gregorian, noleap, 360_day, etc.)
- **`_FillValue`** / **`missing_value`**: NoData indicators
- **Bounds variables**: Cell boundary coordinates for area-weighted operations

### Multidimensional Data Model

NetCDF naturally represents multidimensional arrays. A typical climate dataset:

```
dimensions:
  time = UNLIMITED ;    // e.g., 365 daily steps
  lat = 180 ;
  lon = 360 ;
  level = 37 ;          // pressure levels

variables:
  float temperature(time, level, lat, lon) ;
    temperature:standard_name = "air_temperature" ;
    temperature:units = "K" ;
    temperature:_FillValue = -9999.0f ;

  double time(time) ;
    time:units = "days since 1850-01-01" ;
    time:calendar = "standard" ;

  float lat(lat) ;
    lat:units = "degrees_north" ;

  float lon(lon) ;
    lon:units = "degrees_east" ;
```

GDAL dimension ordering convention: (Z/T, Y, X) per CF recommendations. Extra dimensions beyond X/Y are mapped to bands.

### Serving with THREDDS and OPeNDAP

| Technology | Description |
|------------|-------------|
| **OPeNDAP** | Protocol for remote subsetting of NetCDF data without downloading entire files. Clients request specific variables, spatial subsets, or time slices. |
| **THREDDS Data Server (TDS)** | Java-based server that publishes NetCDF catalogs via OPeNDAP, WMS, WCS, and HTTP. Standard for climate data distribution. |
| **Hyrax** | Alternative OPeNDAP server implementation. |

GDAL can read OPeNDAP endpoints directly if built with OPeNDAP client support.

### GDAL Compression Options

| Option | Values | Notes |
|--------|--------|-------|
| `FORMAT` | NC, NC2, NC4, NC4C | NC4/NC4C required for compression |
| `COMPRESS` | NONE, DEFLATE | DEFLATE only for NC4/NC4C |
| `ZLEVEL` | 1-9 | Compression level |
| `CHUNKING` | YES/NO | Enable HDF5 chunking |
| `WRITE_LONLAT` | YES/NO/IF_NEEDED | Write CF-compliant coordinate variables |
| `WRITE_BOTTOMUP` | YES/NO | Y-axis direction |

### Strengths and Weaknesses

**Strengths:**
- Self-describing with CF conventions providing rich semantic metadata
- Natural support for time series and multidimensional data
- OPeNDAP enables remote subsetting without full downloads
- NetCDF-4 supports compression and chunking via HDF5
- Open format with open-source library (libnetcdf)
- Huge ecosystem in climate/weather science

**Weaknesses:**
- Not spatially tiled; optimized for time-series access, not spatial queries
- GDAL driver treats each 2D slice as a separate band (awkward for >2D data)
- CF convention compliance varies across data providers
- Not cloud-optimized (Zarr is the emerging cloud-native alternative)
- Virtual file system support limited on some platforms

---

## Tile Image Formats for Web Serving

Web map tile services serve pre-rendered image tiles to clients. The choice of tile image format affects bandwidth, visual quality, and browser compatibility.

### Format Comparison

| Format | Type | Transparency | Bit Depth | Typical Size (256x256 tile) | Browser Support |
|--------|------|-------------|-----------|---------------------------|-----------------|
| **PNG** | Lossless | Yes (alpha) | 8/16-bit per channel | 20-80 KB | Universal |
| **JPEG** | Lossy | No | 8-bit | 5-20 KB | Universal |
| **WebP** | Both | Yes (alpha) | 8-bit | 3-15 KB | Wide (check caniuse.com) |
| **AVIF** | Both | Yes (alpha) | 8/10/12-bit | 2-12 KB | Growing (check caniuse.com) |

### Detailed Characteristics

#### PNG (Portable Network Graphics)

- **Compression**: DEFLATE-based, lossless
- **Best for**: Cartographic tiles (sharp lines, text, solid colors), overlays requiring transparency
- **Indexed mode (PNG8)**: 256-color palette reduces size 50-70% vs. truecolor; supports binary transparency
- **Tradeoffs**: Largest files for photographic content; lossless quality

#### JPEG

- **Compression**: DCT-based, lossy. Quality 1-100.
- **Best for**: Satellite/aerial imagery tiles, basemaps with photographic content
- **Tradeoffs**: No transparency support. Artifacts visible at low quality or with sharp edges/text. Smallest files for photographic content. Universal decoding support.

#### WebP

- **Compression**: VP8-based (lossy) or lossless mode
- **Size savings**: 25-34% smaller than JPEG at equivalent quality
- **Best for**: Modern tile services wanting smaller files with transparency support
- **Tradeoffs**: Slightly higher encode/decode CPU cost than JPEG. Wide browser support (check caniuse.com for current coverage).

#### AVIF

- **Compression**: AV1-based, lossy or lossless
- **Size savings**: ~50% smaller than JPEG at equivalent quality
- **Best for**: Next-generation tile services optimizing for bandwidth
- **Tradeoffs**: Significantly slower encoding. Higher decode CPU cost. Browser support is growing (check caniuse.com for current coverage). Not yet supported by all tile serving infrastructure.

### Recommended Strategy

| Use Case | Recommended Format | Fallback |
|----------|--------------------|----------|
| Satellite/aerial basemap | WebP (lossy) | JPEG |
| Cartographic/vector-style tiles | WebP (lossless) or PNG8 | PNG |
| Overlays with transparency | WebP | PNG |
| Maximum compression | AVIF | WebP |
| Maximum compatibility | JPEG (opaque) / PNG (transparent) | - |

Many tile servers implement content negotiation: serve AVIF to clients that accept it, fall back to WebP, then JPEG/PNG.

---

## MBTiles

MBTiles is a specification for storing tiled map data in a SQLite database. Created by Mapbox, it packages map tiles into a single portable file for offline use and efficient distribution.

**GDAL Driver:** `MBTiles` (read/write for raster; read/write for vector via MVT)

### Database Schema

#### Metadata Table

```sql
CREATE TABLE metadata (name TEXT, value TEXT);
```

Required entries:

| Key | Value |
|-----|-------|
| `name` | Human-readable tileset name |
| `format` | Tile format: `jpg`, `png`, `webp`, or `pbf` (vector) |

Recommended entries:

| Key | Value |
|-----|-------|
| `bounds` | WGS 84 bounding box: `left,bottom,right,top` |
| `center` | Default view: `longitude,latitude,zoom` |
| `minzoom` | Minimum zoom level |
| `maxzoom` | Maximum zoom level |
| `attribution` | Data source credits |
| `description` | Tileset description |
| `type` | `overlay` or `baselayer` |
| `version` | Tileset version number |

For vector tilesets (`format=pbf`), a `json` metadata entry is required containing a `vector_layers` array describing layer IDs, field names, and field types.

#### Tiles Table

```sql
CREATE TABLE tiles (
  zoom_level INTEGER,
  tile_column INTEGER,
  tile_row INTEGER,
  tile_data BLOB
);
CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
```

- Tile coordinates follow TMS (Tile Map Service) convention with Y-axis flipped relative to XYZ (slippy map) convention
- Projection is always Web Mercator (EPSG:3857)
- `tile_data` contains the raw image bytes (PNG, JPEG, WebP) or gzip-compressed PBF for vector tiles

#### Optional Grid Tables (UTFGrid)

```sql
CREATE TABLE grids (
  zoom_level INTEGER,
  tile_column INTEGER,
  tile_row INTEGER,
  grid BLOB           -- gzip-compressed UTFGrid JSON
);

CREATE TABLE grid_data (
  zoom_level INTEGER,
  tile_column INTEGER,
  tile_row INTEGER,
  key_name TEXT,
  key_json TEXT        -- JSON object with feature properties
);
```

### GDAL Creation Options

| Option | Default | Description |
|--------|---------|-------------|
| `TILE_FORMAT` | PNG | Output tile format: PNG, PNG8, JPEG, WEBP |
| `QUALITY` | 75 | JPEG/WEBP quality (1-100) |
| `ZLEVEL` | 6 | PNG compression level (1-9) |
| `BLOCKSIZE` | 256 | Tile size in pixels (max 4096) |
| `WRITE_BOUNDS` | YES | Write bounds to metadata |

### Strengths and Weaknesses

**Strengths:**
- Single-file distribution (SQLite database)
- Portable and self-contained for offline use
- Simple, well-defined schema
- Supported by Mapbox GL JS, MapLibre GL JS, and many mobile SDKs
- Efficient random access by zoom/column/row

**Weaknesses:**
- Fixed to Web Mercator (EPSG:3857) projection
- No native support for non-standard tile grids
- TMS Y-axis convention can cause confusion with XYZ tile URLs
- SQLite write concurrency limitations
- Not designed for server-side dynamic rendering (pre-rendered tiles only)

---

## Format Selection Guide

### By Use Case

| Use Case | Recommended Format | Alternative |
|----------|--------------------|-------------|
| Cloud-native raster storage | COG (GeoTIFF) | JPEG2000 |
| Military/intelligence imagery | NITF | - |
| Large aerial photo archives | COG | ECW, MrSID (legacy) |
| Climate/weather data | NetCDF (CF) | HDF5 |
| Satellite instrument data | HDF5/HDF-EOS | NetCDF-4 |
| DEM/elevation data | COG (LERC compression) | GeoTIFF (DEFLATE+Predictor) |
| Offline map tiles | MBTiles | GeoPackage |
| Web map tile serving | PNG / JPEG / WebP tiles | MBTiles, AVIF |
| Maximum compression (lossy) | JPEG2000, ECW, MrSID | COG+JPEG |
| Archival (lossless) | COG (DEFLATE/ZSTD) | JPEG2000 (lossless) |

### By Licensing

| License | Formats |
|---------|---------|
| Fully open / no restrictions | GeoTIFF/COG, PNG, JPEG, NetCDF, HDF5, MBTiles |
| Open read, commercial write | ECW, MrSID |
| Open source + commercial options | JPEG2000 (OpenJPEG free; Kakadu commercial) |
| Military/government standard | NITF/NSIF |

### GDAL Driver Summary

| Format | Driver | Read | Write | Licensing |
|--------|--------|------|-------|-----------|
| GeoTIFF | GTiff | Yes | Yes | Open |
| COG | COG | (via GTiff) | Yes | Open |
| NITF | NITF | Yes | Yes (basic) | Open |
| JPEG2000 | JP2OpenJPEG | Yes | Yes | Open (BSD) |
| JPEG2000 | JP2KAK | Yes | Yes | Commercial |
| JPEG2000 | JP2ECW | Yes | Yes | Commercial |
| JPEG2000 | JP2MrSID | Yes | No | Commercial |
| MrSID | MrSID | Yes | No | Proprietary SDK |
| ECW | ECW | Yes | Yes | Proprietary SDK |
| HDF5 | HDF5 | Yes | No | Open |
| NetCDF | netCDF | Yes | Yes | Open |
| MBTiles | MBTiles | Yes | Yes | Open |
