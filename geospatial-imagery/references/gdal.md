# GDAL workflows

## Check the installed build

Run `gdalinfo --version`, `gdalinfo --formats`, and
`gdalinfo --format COG` to check the installed driver and options.
`gdalinfo -json input.tif` reports the transform, CRS, bands, masks and
overviews available to the reader. Check
`coordinateSystem.dataAxisToSRSAxisMapping` when you need to map the dataset
axes to the CRS authority order. Use `-stats` only when needed. It can scan
the raster and GDAL may persist statistics in a PAM sidecar.

The unified CLI starts in GDAL 3.11. Check the help for the specific
subcommand on the target build. Legacy utilities remain useful on older
builds such as 3.8. The commands below write fresh output paths.
[GDAL raster commands](https://gdal.org/en/stable/programs/index.html).

## Translate, warp, and mosaic

```bash
# Preserve the samples and generate fresh overviews for continuous data.
# Choose NEAREST or MODE for class overviews.
gdal_translate -of COG -co COMPRESS=DEFLATE -co OVERVIEWS=IGNORE_EXISTING \
  -co OVERVIEW_RESAMPLING=AVERAGE source.tif scene_cog.tif

# Reproject continuous data to a 10 m grid in the applicable UTM zone.
# This example assumes EPSG:32632 is appropriate for the source footprint.
gdalwarp -of GTiff -t_srs EPSG:32632 -tr 10 10 -tap -r bilinear \
  source.tif aligned.tif

# Mosaic compatible sources in a deliberate order. Inspect overlaps and holes.
gdalbuildvrt -strict mosaic.vrt first.tif second.tif
gdal_translate -of COG -co COMPRESS=DEFLATE mosaic.vrt mosaic_cog.tif
```

- `gdal_translate -a_srs` assigns metadata. Use `gdalwarp -t_srs` to
  transform the samples. Pass `-s_srs` only when the input CRS is known and
  needs an override. For clipping, distinguish the CRS of the extent
  (`-te_srs`) from the output CRS.
- `-tap` aligns the bounds to multiples of the target resolution. A fixed
  tile matrix can require an explicit extent and grid origin. Decide
  `-srcnodata`, `-dstnodata`, mask or alpha handling, and the kernel together.
  Warping may use source overviews. Compare with `-ovr NONE` when overview
  resampling or quality is part of the comparison.
- A VRT references sources. Reproject mixed-CRS inputs to compatible
  grids before building a mosaic with `gdalbuildvrt`. In an ordinary mosaic
  later sources take priority and nodata can reveal earlier sources. Check
  mask and alpha handling with an overlap fixture. Use a separate blend
  operation when you need fractional-alpha compositing.
- Use `gdaladdo -r nearest source.tif 2 4 8 16` for categorical overviews on
  a normal TIFF. Generate COG overviews during creation or explicitly select
  which source overviews to use. The default `OVERVIEWS=AUTO` can reuse
  existing source overviews. Since GDAL 3.8, the GTiff driver rejects
  opening a COG for update by default to preserve its layout. Write a new
  COG and validate it before replacing the existing asset.
- For a coverage workflow using Python, use the target binding's
  `gdal.WarpOptions` and `gdal.TranslateOptions`. Close output datasets
  before reopening or validating them. Handle errors explicitly and retain
  diagnostic warnings about skipped sources or driver capabilities.

[Warp](https://gdal.org/en/stable/programs/gdalwarp.html),
[BuildVRT](https://gdal.org/en/stable/programs/gdalbuildvrt.html),
[COG driver](https://gdal.org/en/stable/drivers/raster/cog.html),
[GTiff update option](https://gdal.org/en/stable/drivers/raster/gtiff.html#open-options),
[pinned warp implementation](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/apps/gdalwarp_lib.cpp).

## Validate COG layout and HTTP delivery

For GDAL 3.13+ with the GDAL Python bindings available, run
`gdal driver cog validate scene_cog.tif`. On older builds use the
`validate_cloud_optimized_geotiff.py` sample with compatible GDAL
Python bindings. For example, run
`python3 /path/to/validate_cloud_optimized_geotiff.py scene_cog.tif`.
For remote use, request a small byte range on the actual asset URL.
Expect `206 Partial Content` with the matching `Content-Range` on an eligible
byte-range request. Inspect range-read behavior with
`gdalinfo /vsicurl/https://example.com/scene_cog.tif`. For S3, use
`/vsis3/bucket/key` with the intended credentials. Keep signed URLs and
credentials out of shared logs.
[COG validator](https://gdal.org/en/stable/programs/gdal_driver_cog_validate.html),
[validator sample source](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/swig/python/gdal-utils/osgeo_utils/samples/validate_cloud_optimized_geotiff.py),
[VSI handlers](https://gdal.org/en/stable/user/virtual_file_systems.html).

## Generate pre-rendered tiles

```bash
# GDAL 3.11+
gdal raster tile --convention xyz --min-zoom 0 --max-zoom 5 source.tif tiles

# Older utility. --xyz is available from GDAL 3.1.
gdal2tiles.py --xyz --zoom=0-5 --webviewer=none source.tif tiles_legacy
```

The legacy tool defaults to TMS rows. Since 3.13 it is deprecated and
delegates to `gdal raster tile` by default. Specify the convention and
verify the grid, tile size, zoom limits, and data type. For display tiles, choose
the color mapping and scaling for non-byte data explicitly.
[Unified tile command](https://gdal.org/en/stable/programs/gdal_raster_tile.html),
[gdal2tiles](https://gdal.org/en/stable/programs/gdal2tiles.html),
[pinned unified tile implementation](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/apps/gdalalg_raster_tile.cpp).
