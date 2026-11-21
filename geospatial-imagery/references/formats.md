# Raster formats and georeferencing

## GeoTIFF and COG

- Read the CRS and raster-to-world transform together. For an affine transform,
  `X = GT[0] + p*GT[1] + l*GT[2]` and
  `Y = GT[3] + p*GT[4] + l*GT[5]` for pixel and line coordinates `(p, l)`.
  In GDAL the upper-left corner is `(0, 0)` and its center is `(0.5, 0.5)`.
  A native GeoTIFF reader must honor the raster type. By default, the GTiff
  driver converts PixelIsPoint tiepoints to the corner-based transform.
  Test rotated inputs as well as north-up bounds when implementing it.
  [Geotransforms](https://gdal.org/en/stable/tutorials/geotransforms_tut.html),
  [PixelIsPoint RFC](https://gdal.org/en/stable/development/rfc/rfc33_gtiff_pixelispoint.html).
- Distinguish the stored value, scale and offset, unit, color interpretation,
  nodata, and any mask or alpha. A valid black pixel can have value zero.
  Preserve the distinction between validity and display opacity through
  resampling. Check whether georeferencing or a mask comes from an internal
  tag or sidecar. GDAL's GTiff driver documents `GEOREF_SOURCES` and its
  ordered precedence. [GDAL GTiff driver](https://gdal.org/en/stable/drivers/raster/gtiff.html).
- A COG uses TIFF tiling and an ordered layout that supports selective
  retrieval of relevant image data, including lower-resolution subfiles
  where applicable. Overviews have their own TIFF image file directories
  (IFDs). A tiled TIFF with overviews can still fail layout validation.
  Validate separately that the final HTTP endpoint honors range requests.
  [OGC COG 1.0](https://docs.ogc.org/is/21-026/21-026.html).
- Choose lossless compression for values that must round-trip. For imagery
  intended only for display, test JPEG on suitable byte imagery and verify
  transparency through the target decoder. For LERC, set and verify the
  allowed error in sample units. Driver options and available codecs depend
  on the build. When compressed output could exceed classic TIFF's 4 GiB
  limit, explicitly choose `BIGTIFF=YES` if the consumer accepts BigTIFF.
  [GDAL COG creation options](https://gdal.org/en/stable/drivers/raster/cog.html#creation-options).

## NITF and NSIF

Identify the desired image segment before translation. When GDAL exposes
a `SUBDATASETS` list, use the matching `NITF_IM:<index>:<path>` entry.
Segment type, compression support, display bands, metadata, and geolocation
vary by producer and build. Check each supported subtype against fixtures.

Distinguish image corner coordinates (`IGEOLO`), higher-precision geolocation
in applicable TREs or RPF data, and the RPC sensor model. Check which model
the reader exposes. Use RPC with an explicit height or DEM policy if the
product needs orthorectification. Verify TREs, segments, and provenance
required by downstream consumers before choosing what to retain outside
the converted raster. [NITF driver](https://gdal.org/en/stable/drivers/raster/nitf.html),
[pinned NITF reader](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/frmts/nitf/nitfdataset.cpp),
[NITF fixtures](https://github.com/OSGeo/gdal/blob/18642a1c44c884bbfaf5442ea9a25e25d0e8113e/autotest/gdrivers/nitf.py).

## Other imagery inputs

| Input | Inspect first |
|---|---|
| JPEG 2000 | A raw codestream and a JP2 container expose different metadata. Check available drivers and georeferencing precedence for GeoJP2, GMLJP2, and sidecars. [JP2OpenJPEG](https://gdal.org/en/stable/drivers/raster/jp2openjpeg.html) |
| MrSID or ECW | Confirm that the deployed build includes the relevant SDK and that its license covers the intended mode of use. [MrSID](https://gdal.org/en/stable/drivers/raster/mrsid.html), [ECW](https://gdal.org/en/stable/drivers/raster/ecw.html) |
| HDF5 or netCDF | Select the variable/subdataset and the intended time or vertical slice. Verify dimension order, geolocation or CF grid mapping, fill value, scale, and offset. [HDF5](https://gdal.org/en/stable/drivers/raster/hdf5.html), [netCDF](https://gdal.org/en/stable/drivers/raster/netcdf.html) |
| JPEG or PNG with a world file | Verify the matching sidecar and CRS separately. A world file gives the location of the first pixel center. Test channel order and alpha when encoding rendered tiles. [GDAL world file](https://gdal.org/en/stable/drivers/raster/wld.html) |

A format round-trip should check values or a justified tolerance, CRS and
pixel placement, nodata/mask behavior, and the metadata the consuming
application actually uses.
