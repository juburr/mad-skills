# Trace a raster tiling pipeline

## The path from source pixels to a tile

1. Validate georeferencing and sample semantics. Decide how to handle
   source footprints, masks, overlap, and imagery with GCPs or RPCs.
2. Describe the output grid in the requested CRS. For each target tile,
   determine the source footprint with the inverse transform. Densify
   curved edges where needed and expand the resulting source windows
   for the selected resampling kernel. Bound the windows and handle
   invalid transforms and antimeridian crossings explicitly.
3. Select a source resolution appropriate for the output and read the
   intersecting blocks. Warp and resample sample values with their
   validity information, then apply the mosaic policy. For display
   output apply the band mapping or style and encode the tile.
4. Choose which work to do ahead of serving. Pre-render fixed grids when
   the expected reuse justifies it. Keep a georeferenced raster and
   render on demand for arbitrary CRSs, styles, or request windows.
   COG storage blocks can be aligned to a tile matrix with the GDAL COG
   driver's `TILING_SCHEME` and `ALIGNED_LEVELS` options, subject to
   coverage, grid, and padding. Check alignment before enabling a fast
   path. Passing compressed blocks through requires that the grid,
   encoding, and response representation all match.

GDAL's warp application sets up the source/target transform and warp
options. The warper processes destination chunks, and the raster I/O
implementation can select overviews on reads. Treat overview selection
and warp resampling as separate decisions when comparing output. The
COG writer can generate new overview and mask data or reuse source
overviews, then write the output through the GTiff driver.

[Pinned warp application](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/apps/gdalwarp_lib.cpp),
[warp operation](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/alg/gdalwarpoperation.cpp),
[raster I/O and overview selection](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/gcore/rasterio.cpp),
[COG writer](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/frmts/gtiff/cogdriver.cpp).

If GDAL is available only during ingest, define the raster layout, CRS,
and metadata that the serving reader accepts. Compare the serving output
against GDAL on the same grid with the same validity rules and kernel.
Use a numeric tolerance when the algorithms differ in floating-point
rounding.

## What a COG byte-range read does

A COG reader fetches TIFF metadata and locates the IFDs, CRS and transform,
offset and byte-count arrays, and masks. Given the requested footprint
and output resolution, it chooses the image or overview and computes
which stored blocks intersect that window. It fetches the corresponding
ranges, decodes those blocks, and crops or resamples as needed. HTTP
requests may include prefetched or coalesced bytes. The number of reads
depends on the file layout, window, and cache state.

For example, one Web Mercator request can read parts of several blocks
from a UTM source, even when both use 256-pixel tiles. Inspect the
requested source window and selected overview before tuning range size
or changing block dimensions. Keep ranged reads of metadata and blocks
bound to the same object version during publication or replacement.

[Pinned COG tests](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/autotest/gcore/cog.py),
[GDAL HTTP tests](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/autotest/gcore/vsicurl.py),
[OGC COG standard](https://docs.ogc.org/is/21-026/21-026.html).
