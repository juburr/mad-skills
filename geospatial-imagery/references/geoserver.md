# GeoServer and GeoWebCache

## Trace a raster publication

1. Identify the workspace, coverage store, coverage resource, and published
   layer. The store configures the reader, the coverage describes a raster
   resource, and the layer exposes that resource with styles and publication
   settings. Check native vs declared CRS, the projection policy, bounds,
   and dimensions before debugging rendering.
2. Follow WMS request parsing into the map content. `GetMapKvpRequestReader`
   resolves requested layers, styles, filters, and dimensions. The
   rendered-image output path configures GeoTools `StreamingRenderer` and
   encodes the requested map format. Compare WMS with WCS when diagnosing
   differences between styled pixels and coverage samples.
3. For ImageMosaic, examine the granule index, footprints, configured
   ordering, and attributes for time or elevation. Verify that the reader
   selects the expected granules for both the extent and requested
   dimension value. Test missing values, default dimension selection,
   and overlapping granules with different validity masks.

[GeoServer coverage store interface](https://github.com/geoserver/geoserver/blob/8f0bce3a25f9961159d46ce0beaa46f6460a750c/src/main/src/main/java/org/geoserver/catalog/CoverageStoreInfo.java),
[WMS request reader](https://github.com/geoserver/geoserver/blob/8f0bce3a25f9961159d46ce0beaa46f6460a750c/src/wms-core/src/main/java/org/geoserver/wms/map/GetMapKvpRequestReader.java),
[rendered output](https://github.com/geoserver/geoserver/blob/8f0bce3a25f9961159d46ce0beaa46f6460a750c/src/wms-core/src/main/java/org/geoserver/wms/map/RenderedImageMapOutputFormat.java),
[ImageMosaic time and elevation](https://github.com/geoserver/geoserver/blob/8f0bce3a25f9961159d46ce0beaa46f6460a750c/doc/en/user/tutorials/imagemosaic_timeseries/imagemosaic_time-elevationseries.md).

Raster styling can set channels, color maps, contrast, and opacity.
Verify that the numeric values driving a color map are the ones expected by
the style and that invalid pixels remain transparent where required.
Use the coverage store REST API for the deployed version when automating
publication. Inspect the store and coverage after upload, then verify a
request for the published layer. [Coverage store REST API](https://github.com/geoserver/geoserver/blob/8f0bce3a25f9961159d46ce0beaa46f6460a750c/doc/en/user/rest/api/coveragestores.md).

## Diagnose cached imagery

- Determine whether the request reaches WMTS/TMS, the GeoWebCache WMS
  service, or GeoServer WMS with direct integration. The direct WMS path
  requires an eligible cached layer and a request whose format, size,
  CRS, alignment, and parameters fit the tile layer. Whether
  `tiled=true` is required is configurable.
- Compare the request to the exact gridset origin, extent, resolution,
  tile size, and matrix labels. `GWC.findBestMatchingGrid` checks grid
  alignment for direct WMS integration. WMTS converts from top-down
  rows before checking the layer's internal grid coverage.
- Check style, `TIME`, `ELEVATION`, and other active parameter filters
  when requests vary the render. Set a seed and invalidation policy for
  data and style revisions. Try an uncached render before investigating
  grid-alignment, seeding, or cached output.
- Use metatiles and a gutter when there is a measured seam, labeling,
  or render-amortization benefit. Test the resulting edge pixels and
  memory use. Check GeoServer's render limits and its raster reader
  settings in the deployed version.

[GeoServer direct integration](https://github.com/geoserver/geoserver/blob/8f0bce3a25f9961159d46ce0beaa46f6460a750c/doc/en/user/geowebcache/using.md),
[GeoServer integration source](https://github.com/geoserver/geoserver/blob/8f0bce3a25f9961159d46ce0beaa46f6460a750c/src/gwc/src/main/java/org/geoserver/gwc/GWC.java),
[GeoWebCache WMTS source](https://github.com/GeoWebCache/geowebcache/blob/da254e37117d409d4f13c356a2d542c314978f21/geowebcache/wmts/src/main/java/org/geowebcache/service/wmts/WMTSService.java#L467-L526),
[WMS rendering limits](https://github.com/geoserver/geoserver/blob/8f0bce3a25f9961159d46ce0beaa46f6460a750c/doc/en/user/services/wms/configuration.md).
