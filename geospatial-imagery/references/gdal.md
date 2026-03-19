# GDAL/OGR Command-Line Reference

GDAL (Geospatial Data Abstraction Library) provides raster and vector geospatial data tools. This reference covers core commands, workflows, configuration, and Python bindings.

## Core Raster Commands

### gdalinfo -- Inspect Raster Metadata

Displays metadata, coordinate reference system (CRS), bounds, band info, statistics, and overviews.

```bash
# Basic metadata
gdalinfo input.tif

# Show computed min/max values
gdalinfo -mm input.tif

# Show statistics (compute if missing)
gdalinfo -stats input.tif

# JSON output
gdalinfo -json input.tif

# Show only min/max
gdalinfo -mm input.tif | grep "Min/Max"

# Check if file is a valid COG
python validate_cloud_optimized_geotiff.py input.tif
```

Key information returned: driver/format, size (pixels), CRS (WKT and EPSG), geotransform (origin + pixel size), corner coordinates, band count, data type, nodata value, color interpretation, overview levels, metadata domains.

### gdal_translate -- Format Conversion and Manipulation

Converts between raster formats, selects bands, subsets, rescales, and applies compression.

```bash
# Basic format conversion
gdal_translate -of GTiff input.grd output.tif

# Convert to Cloud Optimized GeoTIFF (COG) with the COG driver
gdal_translate -of COG input.tif output_cog.tif

# COG with JPEG compression
gdal_translate -of COG -co COMPRESS=JPEG -co QUALITY=85 input.tif output_cog.tif

# Apply LZW compression with predictor
gdal_translate -co COMPRESS=LZW -co PREDICTOR=2 -co TILED=YES input.tif output.tif

# Select specific bands (extract bands 4,3,2 for false-color)
gdal_translate -b 4 -b 3 -b 2 input.tif rgb_432.tif

# Rescale 16-bit to 8-bit
gdal_translate -ot Byte -scale 0 65535 0 255 -co COMPRESS=LZW input_uint16.tif output_byte.tif

# Subset by pixel coordinates
gdal_translate -srcwin 0 0 512 512 input.tif subset.tif

# Subset by georeferenced coordinates
gdal_translate -projwin -180 90 0 0 input.tif subset.tif

# Downsample to 10% size
gdal_translate -outsize 10% 10% -r cubic input.tif thumbnail.tif

# Assign CRS and bounds to an unreferenced image
gdal_translate -of GTiff -a_ullr <ulx> <uly> <lrx> <lry> -a_srs EPSG:4326 input.png output.tif
```

#### Common Creation Options (-co) for GeoTIFF

| Option | Values | Notes |
|--------|--------|-------|
| `COMPRESS` | `NONE`, `LZW`, `DEFLATE`, `ZSTD`, `JPEG`, `WEBP`, `LERC`, `LZMA`, `JXL` | See compression comparison below |
| `PREDICTOR` | `1` (none), `2` (horizontal), `3` (floating point) | Use with LZW/DEFLATE/ZSTD |
| `TILED` | `YES`/`NO` | Tiled layout required for COGs |
| `BLOCKXSIZE` | pixels (default 256) | Tile width |
| `BLOCKYSIZE` | pixels (default 256) | Tile height |
| `BIGTIFF` | `YES`/`NO`/`IF_NEEDED`/`IF_SAFER` | For files > 4 GB |
| `NUM_THREADS` | integer or `ALL_CPUS` | Multi-threaded compression |
| `COPY_SRC_OVERVIEWS` | `YES`/`NO` | Copy existing overviews |

### gdalwarp -- Reprojection, Resampling, and Clipping

Reprojects, resamples, clips, and mosaics raster data in a single operation.

```bash
# Reproject to Web Mercator
gdalwarp -t_srs EPSG:3857 input.tif output_mercator.tif

# Reproject from geographic to UTM zone 18N
gdalwarp -s_srs EPSG:4326 -t_srs EPSG:32618 input.tif output_utm.tif

# Reproject with bilinear resampling
gdalwarp -t_srs EPSG:3857 -r bilinear input.tif output.tif

# Clip to bounding box
gdalwarp -te <xmin> <ymin> <xmax> <ymax> input.tif clipped.tif

# Clip to vector boundary
gdalwarp -cutline boundary.shp -crop_to_cutline input.tif clipped.tif

# Clip with nodata fill outside boundary
gdalwarp -cutline boundary.shp -crop_to_cutline -dstnodata 0 input.tif clipped.tif

# Resample to specific resolution (30m)
gdalwarp -tr 30 30 -r cubic input.tif resampled.tif

# Resample to specific pixel dimensions
gdalwarp -ts 1024 1024 -r cubic input.tif resampled.tif

# Mosaic multiple files (last file takes priority in overlaps)
gdalwarp input1.tif input2.tif input3.tif mosaic.tif

# Multi-threaded warping
gdalwarp -multi -wo NUM_THREADS=ALL_CPUS -t_srs EPSG:3857 input.tif output.tif

# Use specific overview level
gdalwarp -ovr 2 -t_srs EPSG:3857 input.tif output.tif
```

#### Resampling Methods (-r)

| Method | Best For | Speed | Quality |
|--------|----------|-------|---------|
| `near` | Categorical/thematic data | Fastest | Preserves exact values, may alias |
| `bilinear` | General continuous data, reprojection | Fast | Good balance of speed and quality |
| `cubic` | Continuous data, smooth surfaces | Moderate | Better than bilinear, slight overshoot |
| `cubicspline` | Smooth continuous data | Slower | Very smooth, B-Spline convolution |
| `lanczos` | Overviews, downsampling | Slowest | Sharpest, best for downsampling |
| `average` | Overviews, area-weighted | Fast | Good for aggregation |
| `mode` | Categorical data overviews | Moderate | Most common value wins |
| `rms` | Continuous data | Moderate | Root mean square |
| `min`/`max`/`med` | Statistical analysis | Moderate | Min/max/median of contributing pixels |
| `q1`/`q3` | Statistical analysis | Moderate | First/third quartile |
| `sum` | Count/density data | Moderate | Sum of contributing pixels |

### gdaladdo -- Build Overviews (Pyramids)

Creates downsampled versions for fast rendering at multiple zoom levels.

```bash
# Build standard overview levels (2x, 4x, 8x, 16x reduction)
gdaladdo input.tif 2 4 8 16

# Auto-select appropriate levels (GDAL >= 2.3)
gdaladdo input.tif

# Specify resampling method
gdaladdo -r average input.tif 2 4 8 16

# Build external overviews (creates .ovr file, input remains read-only)
gdaladdo -ro input.tif 2 4 8 16

# Build with cubic resampling for elevation data
gdaladdo -r cubic dem.tif 2 4 8 16

# Specify minimum overview size
gdaladdo --minsize 256 input.tif

# Remove existing overviews
gdaladdo -clean input.tif
```

**Internal vs. External Overviews:**

| Type | Storage | Pros | Cons |
|------|---------|------|------|
| Internal | Inside the TIFF file | Single file, faster access | Increases file size, requires write access |
| External (.ovr) | Separate .ovr sidecar file | Original unchanged, shareable | Extra file to manage |

**Recommended resampling by data type:**
- Imagery/photos: `average` or `cubic`
- Elevation/continuous: `cubic` or `lanczos`
- Categorical/classified: `nearest` or `mode`

**NoData handling during resampling:**
- `nearest`: selects one source pixel; uses its value whether valid or invalid.
- `bilinear`, `cubic`, `cubicspline`, `lanczos`: contributing source pixels marked as nodata get zero weight and are ignored. For `cubic`, if valid pixels in any dimension are fewer than the kernel radius, the target pixel is set to nodata (avoids overshoot from negative kernel weights).
- All other methods (`average`, `mode`, etc.): masked source pixels are ignored; if no valid contributors exist, the target pixel is nodata.

### gdal_merge.py -- Mosaic Multiple Rasters

```bash
# Merge multiple files into one
gdal_merge.py -o mosaic.tif tile1.tif tile2.tif tile3.tif

# Merge with nodata handling
gdal_merge.py -o mosaic.tif -n 0 -a_nodata 0 tile*.tif

# Merge with specific output type and compression
gdal_merge.py -o mosaic.tif -ot Float32 -co COMPRESS=LZW tile*.tif

# Merge with specific pixel size
gdal_merge.py -o mosaic.tif -ps 30 30 tile*.tif
```

Note: All inputs must share the same CRS and band count. For inputs in different CRSes, use `gdalwarp` for mosaicking instead.

### gdal_retile.py -- Retile Large Rasters

```bash
# Retile into 256x256 tiles
gdal_retile.py -ps 256 256 -targetDir output_tiles/ input.tif

# Retile with pyramid levels
gdal_retile.py -ps 512 512 -levels 4 -targetDir output_tiles/ input.tif

# Retile with specific output format
gdal_retile.py -ps 256 256 -of PNG -targetDir output_tiles/ input.tif
```

### gdaltindex -- Create Tile Index

Creates a vector dataset with footprint polygons of raster files, useful for MapServer tileindex layers and managing large collections.

```bash
# Create shapefile tile index
gdaltindex doq_index.shp imagery/*.tif

# Create GeoPackage tile index (recommended)
gdaltindex -f GPKG tile_index.gpkg imagery/*.tif

# Reproject footprints to a common CRS
gdaltindex -t_srs EPSG:4326 tile_index.gpkg imagery/*.tif

# Recursive directory scan (GDAL >= 3.9)
gdaltindex -recursive tile_index.gpkg imagery/
```

### gdal_calc.py -- Raster Band Algebra

Performs pixel-wise math using NumPy syntax.

```bash
# NDVI from a multi-band file (NIR=band 4, Red=band 3)
gdal_calc.py -A input.tif --A_band=4 -B input.tif --B_band=3 \
  --outfile=ndvi.tif --calc="(A.astype(float)-B)/(A.astype(float)+B)" \
  --type=Float32 --NoDataValue=-9999

# NDVI from separate band files
gdal_calc.py -A nir.tif -B red.tif --outfile=ndvi.tif \
  --calc="(A.astype(float)-B)/(A.astype(float)+B)" --type=Float32

# Average two rasters
gdal_calc.py -A input1.tif -B input2.tif --outfile=avg.tif --calc="(A+B)/2"

# Threshold/mask (set values > 100 to 1, else 0)
gdal_calc.py -A input.tif --outfile=mask.tif --calc="(A>100)*1" --type=Byte

# Conditional replacement
gdal_calc.py -A input.tif --outfile=output.tif \
  --calc="numpy.where(A<0, 0, A)" --type=Float32

# Multi-band output (GDAL >= 3.2)
gdal_calc.py -A input.tif --A_band=1 --A_band=2 --A_band=3 \
  --outfile=output.tif --calc="A*2"
```

### gdaldem -- Terrain Analysis

Generates derived products from Digital Elevation Models (DEMs).

```bash
# Hillshade (default: azimuth 315, altitude 45)
gdaldem hillshade dem.tif hillshade.tif

# Hillshade with custom sun angle
gdaldem hillshade -az 135 -alt 30 -z 1.5 dem.tif hillshade.tif

# Multidirectional hillshade (removes directional bias)
gdaldem hillshade -multidirectional dem.tif hillshade_multi.tif

# Slope in degrees
gdaldem slope dem.tif slope.tif

# Slope in percent
gdaldem slope -p dem.tif slope_pct.tif

# Aspect (0-360 degrees, 0=North clockwise)
gdaldem aspect dem.tif aspect.tif

# Color relief (requires color text file)
gdaldem color-relief dem.tif color_ramp.txt color_relief.tif

# Color relief with alpha channel
gdaldem color-relief -alpha dem.tif color_ramp.txt color_relief_rgba.tif

# Terrain Ruggedness Index
gdaldem TRI dem.tif tri.tif

# Topographic Position Index
gdaldem TPI dem.tif tpi.tif

# Roughness
gdaldem roughness dem.tif roughness.tif
```

**Color ramp file format** (space-separated: elevation R G B [alpha]):
```
0     0   0   128
500   0   128 0
1000  128 128 0
2000  128 0   0
4000  255 255 255
nv    0   0   0   0
```

### gdal_contour -- Generate Contour Lines

```bash
# 10-meter contour lines with elevation attribute
gdal_contour -a elev -i 10.0 dem.tif contours.shp

# 100-meter contours to GeoPackage
gdal_contour -a elev -i 100.0 -f GPKG dem.tif contours.gpkg

# Contours at specific elevation levels
gdal_contour -a elev -fl 100 200 500 1000 dem.tif contours.shp

# 3D contour lines (include Z coordinate)
gdal_contour -a elev -i 50 -3d dem.tif contours_3d.shp

# Contour polygons (filled) with min/max attributes
gdal_contour -a elev -amin min_elev -amax max_elev -i 50 -p dem.tif contour_polys.gpkg
```

### gdal2tiles.py -- Generate Web Tile Pyramids

Creates XYZ or TMS tile pyramids from rasters for web map serving.

```bash
# Generate TMS tiles (default Mercator profile)
gdal2tiles.py -z 2-15 input.tif output_tiles/

# Generate XYZ tiles (OpenStreetMap/Slippy Map convention)
gdal2tiles.py --xyz -z 5-18 input.tif output_tiles/

# With specific resampling and parallel processing
gdal2tiles.py --xyz -z 0-16 -r bilinear --processes=4 input.tif output_tiles/

# Geodetic (EPSG:4326) tile profile
gdal2tiles.py --xyz -p geodetic -z 0-10 input.tif output_tiles/

# Generate tiles with Leaflet viewer
gdal2tiles.py --xyz -z 5-15 -w leaflet input.tif output_tiles/

# Generate tiles with OpenLayers viewer
gdal2tiles.py --xyz -z 5-15 -w openlayers input.tif output_tiles/

# Resume a partial tile generation
gdal2tiles.py --xyz -z 5-15 -e input.tif output_tiles/
```

**Tile profile options:** `mercator` (default, Google Maps compatible), `geodetic` (EPSG:4326), `raster` (non-georeferenced).

## OGR Vector Commands (Imagery-Related)

### ogrinfo -- Inspect Vector Data

```bash
# List layers
ogrinfo input.shp

# Layer summary (geometry type, feature count, extent, fields)
ogrinfo -so input.shp layer_name

# All layers summary
ogrinfo -al -so input.gpkg

# Get extent only
ogrinfo input.shp layer_name | grep Extent
```

### ogr2ogr -- Vector Conversion and Operations

Used with imagery workflows for clipping boundaries, footprint management, and format conversion.

```bash
# Format conversion
ogr2ogr -f GeoJSON output.json input.shp
ogr2ogr -f GPKG output.gpkg input.shp

# Reproject vector
ogr2ogr -t_srs EPSG:4326 output.shp input.shp

# Clip vector by bounding box
ogr2ogr -spat <xmin> <ymin> <xmax> <ymax> output.shp input.shp

# Clip vector by polygon
ogr2ogr -clipsrc clipping_polygon.shp output.shp input.shp

# Filter by attribute
ogr2ogr -where "type = 'forest'" output.shp input.shp

# Dissolve features by attribute
ogr2ogr -f GPKG dissolved.gpkg input.gpkg \
  -dialect sqlite -sql "SELECT ST_Union(geom), attr FROM layer GROUP BY attr"
```

## Key Workflows

### 1. Format Conversion

```bash
# GeoTIFF to COG
gdal_translate -of COG -co COMPRESS=DEFLATE input.tif output_cog.tif

# NITF to GeoTIFF
gdal_translate -of GTiff -co COMPRESS=LZW -co TILED=YES input.ntf output.tif

# JPEG2000 to COG
gdal_translate -of COG -co COMPRESS=LZW input.jp2 output_cog.tif

# ECW to GeoTIFF
gdal_translate -of GTiff -co COMPRESS=DEFLATE -co TILED=YES input.ecw output.tif

# HDF5/NetCDF subdataset to GeoTIFF
gdal_translate -of GTiff "HDF5:input.h5://dataset_name" output.tif
gdal_translate -of GTiff "NETCDF:input.nc:variable" output.tif
```

### 2. Reprojection

```bash
# Geographic (EPSG:4326) to Web Mercator (EPSG:3857)
gdalwarp -s_srs EPSG:4326 -t_srs EPSG:3857 -r bilinear input.tif output.tif

# To UTM zone (auto-detect zone for a known area)
gdalwarp -t_srs EPSG:32633 -r bilinear input.tif output_utm33n.tif

# Reproject with target resolution
gdalwarp -t_srs EPSG:3857 -tr 10 10 -r bilinear input.tif output.tif

# Reproject and clip in one step
gdalwarp -t_srs EPSG:3857 -te -8800000 4800000 -8600000 5000000 \
  -r bilinear input.tif output.tif
```

### 3. Building Overviews for Fast Rendering

```bash
# Standard overview pipeline
gdaladdo -r average input.tif 2 4 8 16 32

# Verify overviews were created
gdalinfo input.tif | grep "Overview"

# For elevation data, use cubic
gdaladdo -r cubic dem.tif 2 4 8 16

# For categorical data, use nearest
gdaladdo -r nearest classified.tif 2 4 8 16
```

### 4. COG Creation Pipeline

The COG driver (GDAL >= 3.1) handles overviews, tiling, and layout automatically.

```bash
# Simple COG creation (automatic overviews and tiling)
gdal_translate -of COG input.tif output_cog.tif

# COG with DEFLATE compression (good general-purpose)
gdal_translate -of COG \
  -co COMPRESS=DEFLATE \
  -co LEVEL=6 \
  -co NUM_THREADS=ALL_CPUS \
  -co BLOCKSIZE=512 \
  -co OVERVIEW_RESAMPLING=LANCZOS \
  input.tif output_cog.tif

# COG with JPEG compression (for RGB imagery, smaller size)
gdal_translate -of COG \
  -co COMPRESS=JPEG \
  -co QUALITY=85 \
  -co NUM_THREADS=ALL_CPUS \
  -co OVERVIEW_RESAMPLING=BILINEAR \
  input.tif output_cog.tif

# COG with reprojection to Web Mercator
gdal_translate -of COG \
  -co COMPRESS=DEFLATE \
  -co TARGET_SRS=EPSG:3857 \
  -co RESAMPLING=BILINEAR \
  -co OVERVIEW_RESAMPLING=LANCZOS \
  input.tif output_cog.tif

# Legacy COG creation without the COG driver (pre GDAL 3.1)
gdal_translate -co TILED=YES -co COMPRESS=LZW input.tif temp.tif
gdaladdo -r average temp.tif 2 4 8 16
gdal_translate -co TILED=YES -co COMPRESS=LZW -co COPY_SRC_OVERVIEWS=YES \
  temp.tif output_cog.tif

# Validate COG structure
python validate_cloud_optimized_geotiff.py output_cog.tif
```

**COG Driver Creation Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `COMPRESS` | `LZW` | `NONE`, `LZW`, `JPEG`, `DEFLATE`, `ZSTD`, `WEBP`, `LERC`, `LERC_DEFLATE`, `LERC_ZSTD`, `LZMA`, `JXL` |
| `LEVEL` | 6 (DEFLATE/LZMA), 9 (ZSTD) | Compression level (1-9 DEFLATE, 1-22 ZSTD) |
| `QUALITY` | 75 | JPEG/WEBP quality (1-100) |
| `BLOCKSIZE` | 512 | Tile size in pixels (must be divisible by 16) |
| `INTERLEAVE` | `PIXEL` | `PIXEL` (BIP), `BAND` (BSQ), `TILE` (per-tile band interleave, since 3.11) |
| `OVERVIEWS` | `AUTO` | `AUTO`, `NONE`, `IGNORE_EXISTING`, `FORCE_USE_EXISTING` |
| `OVERVIEW_COUNT` | (auto) | Number of overview levels to generate (since 3.6) |
| `RESAMPLING` | `CUBIC` | Resampling for both overviews and reprojection |
| `OVERVIEW_RESAMPLING` | (from RESAMPLING) | Override resampling for overview generation (since 3.2) |
| `WARP_RESAMPLING` | (from RESAMPLING) | Override resampling for reprojection (since 3.2) |
| `OVERVIEW_COMPRESS` | `AUTO` | Compression for overviews (defaults to same as main) |
| `OVERVIEW_QUALITY` | (from QUALITY) | JPEG/WEBP quality for overviews |
| `TARGET_SRS` | (none) | Reproject during COG creation |
| `RES` | (auto) | Target resolution in TARGET_SRS units |
| `EXTENT` | (auto) | Target extent (minx,miny,maxx,maxy) |
| `TILING_SCHEME` | `CUSTOM` | `CUSTOM`, `GoogleMapsCompatible`, or JSON file |
| `NUM_THREADS` | 1 | Multi-threaded compression and reprojection |
| `PREDICTOR` | `FALSE` | `YES`/`NO`/`STANDARD`/`FLOATING_POINT` |
| `BIGTIFF` | `IF_NEEDED` | `YES`/`NO`/`IF_NEEDED`/`IF_SAFER` |
| `SPARSE_OK` | `FALSE` | Omit empty blocks on disk (since 3.2) |
| `STATISTICS` | `AUTO` | Include band statistics: `AUTO`, `YES`, `NO` (since 3.8) |
| `ADD_ALPHA` | `YES` | Add alpha band when reprojecting |
| `MAX_Z_ERROR` | 0 | LERC max error threshold (0 = lossless) |

### 5. Mosaicking

```bash
# Mosaic with gdal_merge.py (all same CRS)
gdal_merge.py -o mosaic.tif -n 0 -a_nodata 0 tiles/*.tif

# Mosaic with gdalwarp (handles different CRS)
gdalwarp tiles/*.tif mosaic.tif

# Mosaic via VRT (lightweight, no data duplication)
gdalbuildvrt mosaic.vrt tiles/*.tif
# Then optionally materialize:
gdal_translate mosaic.vrt mosaic.tif
```

### 6. Clipping / Subsetting

```bash
# Clip by bounding box (georeferenced coordinates)
gdalwarp -te -105.5 39.5 -104.5 40.5 input.tif clipped.tif

# Clip by vector boundary
gdalwarp -cutline boundary.shp -crop_to_cutline -dstnodata 0 input.tif clipped.tif

# Clip by GeoJSON boundary
gdalwarp -cutline boundary.geojson -crop_to_cutline input.tif clipped.tif

# Subset by pixel window
gdal_translate -srcwin <xoff> <yoff> <xsize> <ysize> input.tif subset.tif

# Subset by projected coordinates
gdal_translate -projwin <ulx> <uly> <lrx> <lry> input.tif subset.tif
```

### 7. Band Extraction and Index Computation

```bash
# Extract single band
gdal_translate -b 1 input.tif band1.tif

# Extract RGB from multi-band (bands 3,2,1)
gdal_translate -b 3 -b 2 -b 1 input.tif rgb.tif

# Compute NDVI
gdal_calc.py -A input.tif --A_band=4 -B input.tif --B_band=3 \
  --outfile=ndvi.tif --calc="(A.astype(float)-B)/(A.astype(float)+B)" \
  --type=Float32

# Compute NDWI (Normalized Difference Water Index)
gdal_calc.py -A input.tif --A_band=3 -B input.tif --B_band=5 \
  --outfile=ndwi.tif --calc="(A.astype(float)-B)/(A.astype(float)+B)" \
  --type=Float32

# Combine separate bands into one file via VRT
gdalbuildvrt -separate combined.vrt red.tif green.tif blue.tif
gdal_translate combined.vrt combined.tif
```

### 8. Computing and Viewing Statistics

```bash
# Compute and embed statistics
gdalinfo -stats input.tif

# View existing statistics
gdalinfo input.tif | grep "STATISTICS"

# Compute approximate statistics (faster for large files)
gdalinfo -approx_ok -stats input.tif

# Compute histogram
gdalinfo -hist input.tif

# Get value at specific coordinate
gdallocationinfo -wgs84 input.tif <lon> <lat>
gdallocationinfo -geoloc input.tif <x> <y>
```

### 9. Tile Pyramid Generation for Web Serving

```bash
# Full pipeline: raw raster to web tiles
# Step 1: Reproject to Web Mercator
gdalwarp -t_srs EPSG:3857 -r bilinear input.tif reprojected.tif

# Step 2: Generate XYZ tile pyramid with viewer
gdal2tiles.py --xyz -z 5-18 -r average --processes=4 -w leaflet \
  reprojected.tif output_tiles/

# One-step COG (alternative to tile pyramid for modern clients)
gdal_translate -of COG -co COMPRESS=JPEG -co QUALITY=80 \
  -co TARGET_SRS=EPSG:3857 -co RESAMPLING=BILINEAR \
  input.tif output_cog.tif
```

### 10. Compression Comparison

| Compression | Type | Ratio | Write Speed | Read Speed | Best For |
|-------------|------|-------|-------------|------------|----------|
| `LZW` | Lossless | Good | Fast | Moderate | General purpose, integer data |
| `DEFLATE` | Lossless | Better | Moderate | Moderate | Archival, smaller files |
| `ZSTD` | Lossless | Better | Fast | Fast | Modern systems (GDAL >= 2.3) |
| `LZMA` | Lossless | Best | Slow | Slow | Maximum compression, archival |
| `JPEG` | Lossy | Excellent | Fast | Fast | RGB imagery, visualization only |
| `WEBP` | Lossy | Excellent | Fast | Fast | Web imagery (GDAL >= 2.4) |
| `LERC` | Lossy* | Excellent | Fast | Fast | Float/elevation data |
| `LERC_ZSTD` | Lossy* | Best | Fast | Fast | Float data, modern systems |
| `JXL` | Both | Excellent | Moderate | Fast | Next-gen, GDAL >= 3.6 |
| `PACKBITS` | Lossless | Poor | Fastest | Fastest | Legacy compatibility |

\* LERC is lossless when `MAX_Z_ERROR=0` (default).

**Predictor options** for LZW, DEFLATE, and ZSTD:
- `PREDICTOR=1`: No prediction (default)
- `PREDICTOR=2`: Horizontal differencing (good for integer data)
- `PREDICTOR=3`: Floating-point prediction (significantly better for float data)

```bash
# Compare compression sizes
for c in NONE LZW DEFLATE ZSTD JPEG; do
  gdal_translate -co COMPRESS=$c -co TILED=YES input.tif test_${c}.tif
  ls -lh test_${c}.tif
done
```

### 11. Virtual Rasters (VRT)

VRT files are lightweight XML descriptors that reference source rasters without copying data.

```bash
# Build mosaic VRT from multiple tiles
gdalbuildvrt mosaic.vrt tiles/*.tif

# Build VRT from file list
gdalbuildvrt -input_file_list filelist.txt mosaic.vrt

# Stack separate bands into multi-band VRT
gdalbuildvrt -separate multiband.vrt band1.tif band2.tif band3.tif

# VRT with specific output resolution
gdalbuildvrt -resolution highest mosaic.vrt tiles/*.tif

# VRT with nodata handling
gdalbuildvrt -srcnodata 0 -vrtnodata 0 mosaic.vrt tiles/*.tif

# Materialize VRT to actual file
gdal_translate mosaic.vrt mosaic.tif

# VRT to COG
gdal_translate -of COG mosaic.vrt mosaic_cog.tif
```

**VRT advantages:**
- No data duplication; references original files
- Instant creation regardless of data volume
- Works as input to all GDAL tools
- Useful for band stacking, mosaicking, and on-the-fly reprojection
- Can reference cloud-hosted files via /vsicurl/, /vsis3/

## Configuration and Environment Variables

### Performance Tuning

| Variable | Default | Description |
|----------|---------|-------------|
| `GDAL_CACHEMAX` | 5% RAM | Block cache size (MB or percentage, e.g., `512` or `30%`) |
| `GDAL_NUM_THREADS` | 1 | Threads for compression/decompression (`ALL_CPUS` or integer) |
| `GDAL_DISABLE_READDIR_ON_OPEN` | `NO` | Set to `EMPTY_DIR` for cloud access to avoid directory listing |
| `VSI_CACHE` | `FALSE` | Enable per-file caching for network access |
| `VSI_CACHE_SIZE` | 25 MB | Per-file cache size in bytes (e.g., `200000000` for 200 MB) |
| `GDAL_HTTP_MULTIPLEX` | `YES` | HTTP/2 multiplexing for parallel range requests |
| `GDAL_HTTP_MERGE_CONSECUTIVE_RANGES` | `YES` | Merge consecutive HTTP range requests |
| `CPL_VSIL_CURL_CHUNK_SIZE` | 16384 | Bytes per partial download chunk |
| `CPL_VSIL_CURL_CACHE_SIZE` | 16 MB | Global LRU cache for curl requests |

**Recommended settings for cloud data access:**
```bash
export GDAL_CACHEMAX=512
export GDAL_NUM_THREADS=ALL_CPUS
export GDAL_DISABLE_READDIR_ON_OPEN=EMPTY_DIR
export VSI_CACHE=TRUE
export VSI_CACHE_SIZE=200000000
export GDAL_HTTP_MULTIPLEX=YES
export CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif,.tiff,.vrt,.ovr"
```

### Virtual Filesystem Handlers

Access remote data without downloading entire files.

| Handler | Service | Example Path |
|---------|---------|-------------|
| `/vsicurl/` | Any HTTP/HTTPS/FTP | `/vsicurl/https://example.com/data.tif` |
| `/vsis3/` | AWS S3 | `/vsis3/bucket-name/path/to/file.tif` |
| `/vsigs/` | Google Cloud Storage | `/vsigs/bucket-name/path/to/file.tif` |
| `/vsiaz/` | Azure Blob Storage | `/vsiaz/container/path/to/file.tif` |
| `/vsioss/` | Alibaba Cloud OSS | `/vsioss/bucket/path/to/file.tif` |
| `/vsiswift/` | OpenStack Swift | `/vsiswift/container/path/to/file.tif` |
| `/vsimem/` | In-memory filesystem | `/vsimem/temp.tif` |
| `/vsizip/` | ZIP archives | `/vsizip/archive.zip/data.tif` |
| `/vsigzip/` | GZip files | `/vsigzip/data.tif.gz` |
| `/vsitar/` | TAR archives | `/vsitar/archive.tar/data.tif` |

**Cloud authentication environment variables:**

AWS S3 (`/vsis3/`):
```bash
export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_REGION=us-east-1
# Or for public buckets:
export AWS_NO_SIGN_REQUEST=YES
# For S3-compatible endpoints (MinIO, etc.):
export AWS_S3_ENDPOINT=minio.example.com
```

Google Cloud Storage (`/vsigs/`):
```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
# Or for public buckets:
export GS_NO_SIGN_REQUEST=YES
```

Azure Blob Storage (`/vsiaz/`):
```bash
export AZURE_STORAGE_ACCOUNT=<account>
export AZURE_STORAGE_ACCESS_KEY=<key>
# Or with SAS token:
export AZURE_STORAGE_SAS_TOKEN=<token>
# Or for public access:
export AZURE_NO_SIGN_REQUEST=YES
```

**Using virtual filesystems with GDAL commands:**
```bash
# Read metadata from S3
gdalinfo /vsis3/landsat-pds/c1/L8/139/045/LC08_L1TP_139045_20170304_20170316_01_T1/LC08_L1TP_139045_20170304_20170316_01_T1_B4.TIF

# Read from HTTP
gdalinfo /vsicurl/https://example.com/raster.tif

# Convert S3 file to local COG
gdal_translate -of COG /vsis3/my-bucket/input.tif local_output_cog.tif

# Build VRT from S3 files
gdalbuildvrt mosaic.vrt \
  /vsis3/bucket/tile1.tif \
  /vsis3/bucket/tile2.tif

# Clip a cloud-hosted COG
gdalwarp -te -105 39 -104 40 /vsicurl/https://example.com/cog.tif local_clip.tif
```

## Unified `gdal` CLI (GDAL >= 3.11)

GDAL 3.11 introduces a unified `gdal` command-line interface that replaces the traditional separate utilities with a structured subcommand hierarchy. The traditional utilities still work but the new CLI is the recommended approach going forward.

### Migration Examples

| Traditional Command | Unified CLI Equivalent |
|---|---|
| `gdalinfo my.tif` | `gdal raster info my.tif` |
| `gdal_translate -of COG in.nc out.tif` | `gdal raster convert --of=COG in.nc out.tif` |
| `gdalwarp -t_srs EPSG:4326 -co TILED=YES in.tif out.tif` | `gdal raster reproject --dst-crs=EPSG:4326 --co=TILED=YES in.tif out.tif` |
| `gdaladdo -r average my.tif 2 4 8 16` | `gdal raster overview add -r average --levels=2,4,8,16 my.tif` |
| `gdalbuildvrt out.vrt src/*.tif` | `gdal raster mosaic src/*.tif out.vrt` |
| `gdalbuildvrt -separate out.vrt r.tif g.tif b.tif` | `gdal raster stack r.tif g.tif b.tif out.tif` |
| `gdal_translate -b 3 -b 2 -b 1 bgr.tif rgb.tif` | `gdal raster select --band 3,2,1 bgr.tif rgb.tif` |
| `gdal_translate -projwin 2 50 3 49 in.tif out.tif` | `gdal raster clip --bbox=2,49,3,50 in.tif out.tif` |
| `gdal2tiles --zoom=2-5 in.tif out/` | `gdal raster tile --min-zoom=2 --max-zoom=5 in.tif out/` |
| `ogrinfo -al -so my.gpkg` | `gdal vector info my.gpkg` |
| `ogr2ogr out.gpkg in.shp` | `gdal vector convert in.shp out.gpkg` |
| `ogr2ogr -t_srs EPSG:4326 out.gpkg in.shp` | `gdal vector reproject --dst-crs=EPSG:4326 in.shp out.gpkg` |
| `ogr2ogr -clipsrc 2 49 3 50 out.gpkg in.gpkg` | `gdal vector clip --bbox=2,49,3,50 in.gpkg out.gpkg` |

### Raster Pipeline

The `gdal raster pipeline` command chains multiple processing steps with `!` separators, enabling complex multi-step operations in a single command without intermediate files.

```bash
# Read, reproject, and write in one pipeline
gdal raster pipeline read in.tif ! reproject --dst-crs=EPSG:3857 ! write out.tif

# Read, clip, add hillshade, and write
gdal raster pipeline read dem.tif ! clip --bbox=2,49,3,50 ! hillshade ! write hillshade.tif

# Read, edit CRS/bounds, add metadata, and write with creation options
gdal raster pipeline read in.png \
  ! edit --crs=EPSG:4326 --bbox=-180,-90,180,90 --metadata=DESCRIPTION=Temperature \
  ! write --co=TILED=YES out.tif

# Create mosaic as COG directly
gdal raster mosaic --of=COG src/*.tif out.tif
```

Available pipeline steps: `read`, `calc`, `create`, `mosaic`, `stack`, `aspect`, `blend`, `clip`, `color-map`, `edit`, `fill-nodata`, `hillshade`, `materialize`, `neighbors`, `nodata-to-alpha`, `overview`, `pansharpen`, `proximity`, `reclassify`, `reproject`, `resize`, `rgb-to-palette`, `roughness`, `scale`, `select`, `set-type`, `sieve`, `slope`, `tpi`, `tri`, `unscale`, `update`, `viewshed`, `write`, `info`, `tile`.

## Python GDAL Bindings (osgeo.gdal)

### Installation

```bash
pip install GDAL
# Must match system GDAL version:
pip install GDAL==$(gdal-config --version)
```

### Common Patterns

```python
from osgeo import gdal, osr
import numpy as np

# Enable exceptions instead of silent error codes
gdal.UseExceptions()

# Open a dataset
ds = gdal.Open("input.tif")
print(f"Size: {ds.RasterXSize} x {ds.RasterYSize}")
print(f"Bands: {ds.RasterCount}")
print(f"CRS: {ds.GetProjection()}")
print(f"GeoTransform: {ds.GetGeoTransform()}")

# Read a single band as numpy array
band = ds.GetRasterBand(1)
arr = band.ReadAsArray()
nodata = band.GetNoDataValue()
stats = band.GetStatistics(True, True)  # (min, max, mean, stddev)

# Read all bands at once
data = ds.ReadAsArray()  # shape: (bands, rows, cols)

# Context manager (GDAL >= 3.8)
with gdal.Open("input.tif") as ds:
    arr = ds.ReadAsArray()
```

```python
# Create a new raster
driver = gdal.GetDriverByName("GTiff")
out_ds = driver.Create("output.tif", xsize=1024, ysize=1024,
                        bands=1, eType=gdal.GDT_Float32,
                        options=["COMPRESS=LZW", "TILED=YES"])

# Set geotransform and projection
out_ds.SetGeoTransform((xmin, pixel_width, 0, ymax, 0, -pixel_height))
srs = osr.SpatialReference()
srs.ImportFromEPSG(4326)
out_ds.SetProjection(srs.ExportToWkt())

# Write array to band
out_band = out_ds.GetRasterBand(1)
out_band.WriteArray(data_array)
out_band.SetNoDataValue(-9999)
out_band.FlushCache()
out_band.ComputeStatistics(False)

# Close and flush
out_ds = None
```

```python
# Warp (reproject) programmatically
gdal.Warp("output.tif", "input.tif",
          dstSRS="EPSG:3857",
          resampleAlg="bilinear",
          creationOptions=["COMPRESS=LZW", "TILED=YES"])

# Translate programmatically
gdal.Translate("output_cog.tif", "input.tif",
               format="COG",
               creationOptions=["COMPRESS=DEFLATE", "NUM_THREADS=ALL_CPUS"])

# Build VRT
gdal.BuildVRT("mosaic.vrt", ["tile1.tif", "tile2.tif"])

# Compute NDVI
nir_ds = gdal.Open("nir.tif")
red_ds = gdal.Open("red.tif")
nir = nir_ds.GetRasterBand(1).ReadAsArray().astype(float)
red = red_ds.GetRasterBand(1).ReadAsArray().astype(float)
ndvi = np.where((nir + red) > 0, (nir - red) / (nir + red), -9999)
```

### gdal.Warp() Options

```python
gdal.Warp(destName, srcDS,
    format="GTiff",
    dstSRS="EPSG:3857",
    srcSRS="EPSG:4326",
    resampleAlg="bilinear",       # near, bilinear, cubic, lanczos, etc.
    outputBounds=(xmin, ymin, xmax, ymax),
    xRes=10, yRes=10,
    cutlineDSName="boundary.shp",
    cropToCutline=True,
    dstNodata=0,
    multithread=True,
    warpMemoryLimit=512,
    creationOptions=["COMPRESS=LZW", "TILED=YES"],
    warpOptions=["NUM_THREADS=ALL_CPUS"])
```

### gdal.Translate() Options

```python
gdal.Translate(destName, srcDS,
    format="COG",
    bandList=[4, 3, 2],
    outputType=gdal.GDT_Byte,
    scaleParams=[[0, 10000, 0, 255]],
    projWin=[ulx, uly, lrx, lry],
    creationOptions=["COMPRESS=JPEG", "QUALITY=85"])
```
