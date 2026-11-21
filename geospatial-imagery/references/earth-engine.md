# Google Earth Engine imagery workflows

Use this guide for the hosted Earth Engine computation and catalog APIs.
For Google Earth Enterprise databases and packets, use the indexing
reference from the skill entry point.

- Filter collections by region, time, and product metadata before large
  operations. Confirm band IDs, scaling, QA masks, and per-band resolution
  against the specific catalog entry. A collection reducer such as
  `median()` reduces each matching band across images. Apply validity
  and cloud masking appropriate to the product before the reducer.
- Earth Engine objects build a computation evaluated on the server.
  Use server-side operations for collections. Keep client-side
  `getInfo()` to small results such as inspecting one projection or
  a scalar. Use bounded regions and an explicit projection or scale
  when aggregating values. Visualization, reducers, and exports can
  request different resolutions.
- Preview rendered output with `Map.addLayer` in the Code Editor. Check
  the analytic values separately at the intended grid. For an export
  aligned to a particular raster, supply the reference band's CRS and
  `crsTransform`. For GeoTIFF exports to a supported destination,
  `formatOptions: {cloudOptimized: true}` requests a COG.
  Validate the exported file's footprint, grid, values, and masks.

[Client/server evaluation](https://developers.google.com/earth-engine/guides/client_server),
[scale](https://developers.google.com/earth-engine/guides/scale),
[projections](https://developers.google.com/earth-engine/guides/projections),
[image exports](https://developers.google.com/earth-engine/guides/exporting_images).

For example, for a selected and masked Sentinel-2 surface reflectance
image with bands `B8` (near-infrared) and `B4` (red):

```js
const ndvi = maskedS2.normalizedDifference(["B8", "B4"]).rename("NDVI");
Map.addLayer(ndvi, { min: -0.2, max: 0.8 }, "NDVI");
```

Apply the product's scaling and offsets as required before computing
indices. `normalizedDifference` masks pixels where either input is
negative. Use an explicit expression with a denominator and validity
policy when negative sample values are meaningful.
[Sentinel-2 SR Harmonized](https://developers.google.com/earth-engine/datasets/catalog/COPERNICUS_S2_SR_HARMONIZED),
[normalizedDifference API](https://developers.google.com/earth-engine/apidocs/ee-image-normalizeddifference).
