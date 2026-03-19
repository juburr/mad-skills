# Google Earth Engine Reference

## Architecture Overview

### Cloud-Based Processing Model

Google Earth Engine (EE) is a cloud-based platform for planetary-scale geospatial analysis. All computation runs on Google's infrastructure, distributed across many machines. Users never download raw data for local processing; instead, they describe computations that execute server-side.

EE measures computational resources in **Earth Engine Compute Units (EECUs)**, an abstraction representing instantaneous processing power. A job consuming 10 EECU-hours may complete in minutes due to massive parallelism. EECUs do not correspond directly to CPU-seconds or wall-clock time.

### Client-Server Model

EE uses a client-server architecture where client libraries (Python and JavaScript) generate computation descriptions that the server executes. The key abstraction is the **proxy object**: any object prefixed with `ee.` is a server-side proxy that contains no actual data locally. It is a handle for an object on the server.

```
Client (your code)          Server (Google infrastructure)
--------------------        ----------------------------
ee.Image('LANDSAT/...')  -> Computation graph node
  .normalizedDifference() -> Additional graph node
  .reduceRegion()        -> Triggers execution, returns result
```

### Lazy Evaluation and Computation Graphs

Operations in EE are **lazily evaluated**. When you write `image.normalizedDifference(['B5', 'B4'])`, no computation occurs. Instead, the client library builds a **Directed Acyclic Graph (DAG)** representing the computation. Execution is triggered only when results are explicitly requested:

- **`print()` / `getInfo()`**: Requests a value from the server
- **`Map.addLayer()`**: Requests map tiles for display
- **`Export.image.toDrive()`**: Submits a batch export task

The server receives the serialized DAG, optimizes it, and distributes execution across its infrastructure. This deferred execution model enables EE to optimize the computation graph before running it.

### Client vs. Server Objects

Mixing client-side and server-side objects is a common source of errors:

| Client-Side (local) | Server-Side (ee proxy) |
|---------------------|----------------------|
| `'hello'` (str) | `ee.String('hello')` |
| `42` (number) | `ee.Number(42)` |
| `[1, 2, 3]` (list) | `ee.List([1, 2, 3])` |
| `True` (bool) | `ee.Number(1)` used as bool |
| `if/else` | `ee.Algorithms.If()` |
| `for` loop | `collection.map()` |

**Why mixing causes errors:** Client-side operations like `if`, `for`, and standard arithmetic cannot inspect the contents of server-side objects because their values are unknown until the server executes the computation. A client-side `if` statement checking an `ee.Boolean` will always evaluate as truthy (it is a non-null object), producing incorrect logic.

```javascript
// WRONG: client-side conditional on server object
var value = ee.Number(5);
if (value > 3) { /* always true - value is a proxy object, not 5 */ }

// CORRECT: server-side conditional
var result = ee.Algorithms.If(value.gt(3), 'big', 'small');
```

```python
# WRONG: client-side loop building server requests
for i in range(100):
    image = image.add(ee.Number(i))  # builds enormous graph

# CORRECT: server-side iteration
image_list = ee.List.sequence(0, 99)
result = image_list.iterate(lambda i, img: ee.Image(img).add(ee.Number(i)), image)
```

### Scale and Projection

**Scale is determined by the output, not the input.** When you request results (display, export, reduceRegion), you specify or imply a scale, and EE selects the appropriate level from pre-built image pyramids.

Image pyramids are created during ingestion by aggregating pixels at progressively coarser resolutions. EE selects the pyramid level with the closest scale less than or equal to the requested scale, then resamples (nearest neighbor by default).

**Projection follows a "pull" model.** The output projection propagates backward through the computation graph. Inputs are automatically reprojected to match the output projection:

- `Map.addLayer()` uses Web Mercator (EPSG:3857)
- `Export` functions use the specified CRS parameter
- `reduceRegion()` -- **always specify `scale`**. Without it, EE may use the image's native projection and nominal scale for simple images, but falls back to 1-degree resolution (~111 km pixels) for composites or ambiguous cases, producing incorrect results. When `scale` is given without `crs`, the image's native projection is used at that scale

Use `reproject()` with caution -- it forces all upstream operations into a specific projection and scale, which can trigger excessive computation if the forced scale is much finer than the display zoom level.

```javascript
// Scale specified explicitly in reduceRegion
var stats = image.reduceRegion({
  reducer: ee.Reducer.mean(),
  geometry: region,
  scale: 30,  // 30m Landsat resolution
  maxPixels: 1e9
});
```

```python
stats = image.reduceRegion(
    reducer=ee.Reducer.mean(),
    geometry=region,
    scale=30,
    maxPixels=1e9
).getInfo()
```

---

## Core API Concepts

### ee.Image

A single raster image consisting of one or more bands, each with a name, data type, scale, projection, and optional mask. Images also carry metadata as properties.

**Loading an image:**
```javascript
var image = ee.Image('LANDSAT/LC08/C02/T1_L2/LC08_044034_20140318');
```
```python
image = ee.Image('LANDSAT/LC08/C02/T1_L2/LC08_044034_20140318')
```

**Band math:**
```javascript
// Arithmetic operations
var ndvi = image.select('SR_B5').subtract(image.select('SR_B4'))
    .divide(image.select('SR_B5').add(image.select('SR_B4')));

// Shortcut for normalized difference
var ndvi = image.normalizedDifference(['SR_B5', 'SR_B4']).rename('NDVI');

// Expression-based math
var evi = image.expression(
    '2.5 * ((NIR - RED) / (NIR + 6 * RED - 7.5 * BLUE + 1))', {
      'NIR': image.select('SR_B5'),
      'RED': image.select('SR_B4'),
      'BLUE': image.select('SR_B2')
});
```

**Masking:**
```javascript
// Mask pixels below a threshold
var masked = image.updateMask(image.select('NDVI').gt(0.3));

// Cloud masking with QA band (Landsat 8 Collection 2)
function maskClouds(image) {
  var qa = image.select('QA_PIXEL');
  var cloudShadowBit = 1 << 4;
  var cloudBit = 1 << 3;
  var mask = qa.bitwiseAnd(cloudShadowBit).eq(0)
      .and(qa.bitwiseAnd(cloudBit).eq(0));
  return image.updateMask(mask);
}
```

```python
def mask_clouds(image):
    qa = image.select('QA_PIXEL')
    cloud_shadow_bit = 1 << 4
    cloud_bit = 1 << 3
    mask = (qa.bitwiseAnd(cloud_shadow_bit).eq(0)
            .And(qa.bitwiseAnd(cloud_bit).eq(0)))
    return image.updateMask(mask)
```

**Visualization:**
```javascript
Map.addLayer(image, {
  bands: ['SR_B4', 'SR_B3', 'SR_B2'],
  min: 7000,
  max: 30000
}, 'True Color');

Map.addLayer(ndvi, {
  min: -0.1,
  max: 0.8,
  palette: ['brown', 'yellow', 'green', 'darkgreen']
}, 'NDVI');
```

**Reducers on images:**
```javascript
// Statistics within a region
var stats = image.reduceRegion({
  reducer: ee.Reducer.mean(),
  geometry: roi,
  scale: 30,
  maxPixels: 1e9
});

// Statistics over a neighborhood (spatial filter)
var smoothed = image.reduceNeighborhood({
  reducer: ee.Reducer.mean(),
  kernel: ee.Kernel.square(3)  // 3-pixel radius
});
```

### ee.ImageCollection

A time series or stack of images, typically representing all acquisitions from a sensor over a region and time period.

**Loading and filtering:**
```javascript
var collection = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2')
    .filterDate('2020-06-01', '2020-09-01')
    .filterBounds(roi)
    .filter(ee.Filter.lt('CLOUD_COVER', 20));
```

```python
collection = (ee.ImageCollection('LANDSAT/LC08/C02/T1_L2')
    .filterDate('2020-06-01', '2020-09-01')
    .filterBounds(roi)
    .filter(ee.Filter.lt('CLOUD_COVER', 20)))
```

**Mapping (per-image processing):**
```javascript
// Add NDVI band to every image in collection
var addNDVI = function(image) {
  var ndvi = image.normalizedDifference(['SR_B5', 'SR_B4']).rename('NDVI');
  return image.addBands(ndvi);
};
var withNDVI = collection.map(addNDVI);
```

```python
def add_ndvi(image):
    ndvi = image.normalizedDifference(['SR_B5', 'SR_B4']).rename('NDVI')
    return image.addBands(ndvi)

with_ndvi = collection.map(add_ndvi)
```

**Reducing (temporal composites):**
```javascript
// Simple composites
var median = collection.median();
var mean = collection.mean();
var mosaic = collection.mosaic();  // last-on-top

// Quality mosaic: pick pixel with highest NDVI
var greenest = withNDVI.qualityMosaic('NDVI');
```

### ee.Geometry / ee.Feature / ee.FeatureCollection

Vector data types for defining regions of interest and storing analysis results.

```javascript
// Point
var point = ee.Geometry.Point([lon, lat]);

// Polygon
var polygon = ee.Geometry.Polygon([[[x1,y1],[x2,y2],[x3,y3],[x1,y1]]]);

// Buffer
var buffered = point.buffer(1000);  // 1km radius

// Feature with properties
var feature = ee.Feature(polygon, {name: 'study_area', area_km2: 42});

// FeatureCollection from asset
var countries = ee.FeatureCollection('FAO/GAUL/2015/level0');
var france = countries.filter(ee.Filter.eq('ADM0_NAME', 'France'));
```

```python
point = ee.Geometry.Point([lon, lat])
buffered = point.buffer(1000)
countries = ee.FeatureCollection('FAO/GAUL/2015/level0')
france = countries.filter(ee.Filter.eq('ADM0_NAME', 'France'))
```

### ee.Reducer

Statistical aggregation across time, space, bands, or feature attributes.

| Reducer | Use Case |
|---------|----------|
| `ee.Reducer.mean()` | Average value |
| `ee.Reducer.median()` | Median composite |
| `ee.Reducer.min()` / `max()` | Extreme values |
| `ee.Reducer.stdDev()` | Variability |
| `ee.Reducer.histogram()` | Value distribution |
| `ee.Reducer.linearRegression()` | Trend analysis |
| `ee.Reducer.percentile([25,75])` | Interquartile range |

**Reducer contexts:**
- **Temporal**: `imageCollection.reduce(reducer)` -- across images at each pixel
- **Spatial**: `image.reduceRegion(reducer, geometry, scale)` -- across pixels in a region
- **Neighborhood**: `image.reduceNeighborhood(reducer, kernel)` -- sliding window
- **Zonal**: `image.reduceRegions(featureCollection, reducer, scale)` -- per-feature stats
- **Grouped**: `reducer.group()` with `reduceRegion()` -- stats grouped by zone class

**Zonal statistics example:**
```javascript
// Mean NDVI per watershed
var zonalStats = ndvi.reduceRegions({
  collection: watersheds,
  reducer: ee.Reducer.mean(),
  scale: 30
});
```

```python
zonal_stats = ndvi.reduceRegions(
    collection=watersheds,
    reducer=ee.Reducer.mean(),
    scale=30
)
```

---

## Data Catalog

### Satellite Imagery

| Dataset | Asset ID | Resolution | Temporal | Key Bands |
|---------|----------|-----------|----------|-----------|
| Landsat 5 TM SR | `LANDSAT/LT05/C02/T1_L2` | 30m | 1984-2012 | SR_B1-B5, SR_B7, ST_B6 |
| Landsat 7 ETM+ SR | `LANDSAT/LE07/C02/T1_L2` | 30m | 1999-2024 | SR_B1-B5, SR_B7, ST_B6 |
| Landsat 8 OLI SR | `LANDSAT/LC08/C02/T1_L2` | 30m | 2013-present | SR_B1-B7, ST_B10 |
| Landsat 9 OLI-2 SR | `LANDSAT/LC09/C02/T1_L2` | 30m | 2021-present | SR_B1-B7, ST_B10 |
| Sentinel-2 SR | `COPERNICUS/S2_SR_HARMONIZED` | 10-60m | 2017-present | B1-B12, SCL, QA60 |
| Sentinel-2 TOA | `COPERNICUS/S2_HARMONIZED` | 10-60m | 2015-present | B1-B12, QA60 |
| Sentinel-1 GRD | `COPERNICUS/S1_GRD` | 10m | 2014-present | VV, VH |
| MODIS Terra SR | `MODIS/061/MOD09GA` | 500m | 2000-present | sur_refl_b01-b07 |
| MODIS NDVI | `MODIS/061/MOD13A2` | 1km | 2000-present | NDVI, EVI |
| VIIRS SR | `NOAA/VIIRS/001/VNP09GA` | 500m-1km | 2012-present | M1-M11, I1-I3 |

### Common Band Mappings for Spectral Indices

| Band Purpose | Landsat 8/9 | Sentinel-2 | MODIS |
|-------------|-------------|------------|-------|
| Blue | SR_B2 | B2 | sur_refl_b03 |
| Green | SR_B3 | B3 | sur_refl_b04 |
| Red | SR_B4 | B4 | sur_refl_b01 |
| NIR | SR_B5 | B8 | sur_refl_b02 |
| SWIR1 | SR_B6 | B11 | sur_refl_b06 |
| SWIR2 | SR_B7 | B12 | sur_refl_b07 |

### Derived Products and Elevation

| Dataset | Asset ID | Resolution |
|---------|----------|-----------|
| SRTM Elevation | `USGS/SRTMGL1_003` | 30m |
| ALOS DEM | `JAXA/ALOS/AW3D30/V3_2` | 30m |
| MODIS Land Cover | `MODIS/061/MCD12Q1` | 500m |
| Global Forest Change | `UMD/hansen/global_forest_change_2023_v1_11` | 30m |
| Dynamic World | `GOOGLE/DYNAMICWORLD/V1` | 10m |

### Climate and Weather

| Dataset | Asset ID | Resolution |
|---------|----------|-----------|
| ERA5 Monthly | `ECMWF/ERA5/MONTHLY` | ~27km |
| ERA5-Land Hourly | `ECMWF/ERA5_LAND/HOURLY` | ~9km |
| CHIRPS Precipitation | `UCSB-CHG/CHIRPS/DAILY` | ~5km |
| GRIDMET | `IDAHO_EPSCOR/GRIDMET` | ~4km |

### Asset Management

Custom data can be uploaded to EE as user assets with paths like `users/username/asset_name` or under a Cloud Project as `projects/project-id/assets/asset_name`. Assets can be images, image collections, tables, or folders with configurable sharing permissions.

---

## Visualization and Map Display

### Map.addLayer (Code Editor)

```javascript
Map.addLayer(image, {
  bands: ['SR_B4', 'SR_B3', 'SR_B2'],  // RGB band assignment
  min: 7000,                             // min display value
  max: 30000,                            // max display value
  gamma: 1.4                             // gamma correction
}, 'Layer Name', true, 0.8);             // name, shown, opacity
```

### Tile Serving Architecture

When `Map.addLayer()` is called, the client library serializes the computation graph as JSON and sends it to the EE server. The server returns a **tile URL template** (e.g., `https://earthengine.googleapis.com/v1/projects/.../maps/.../tiles/{z}/{x}/{y}`). As the user pans and zooms, the browser requests individual 256x256 tiles. The server processes only the pixels needed for each tile at the appropriate pyramid level for the current zoom, renders them with the specified visualization parameters, and returns PNG tiles.

This architecture means:
- No full-resolution processing occurs until tiles are requested
- Only visible tiles are computed (on-demand rendering)
- Zoom level determines the processing scale
- Tiles may be cached for repeated views

### Thumbnails

```javascript
var url = image.getThumbURL({
  bands: ['SR_B4', 'SR_B3', 'SR_B2'],
  min: 7000, max: 30000,
  region: roi,
  dimensions: 512
});
```

```python
url = image.getThumbURL({
    'bands': ['SR_B4', 'SR_B3', 'SR_B2'],
    'min': 7000, 'max': 30000,
    'region': roi.getInfo(),
    'dimensions': 512
})
```

### Export Workflows

**Export to Google Drive:**
```javascript
Export.image.toDrive({
  image: ndvi,
  description: 'NDVI_Export',
  folder: 'EE_Exports',
  fileNamePrefix: 'ndvi_2020',
  region: roi,
  scale: 30,
  crs: 'EPSG:4326',
  maxPixels: 1e13,
  fileFormat: 'GeoTIFF',
  formatOptions: { cloudOptimized: true }
});
```

```python
task = ee.batch.Export.image.toDrive(
    image=ndvi,
    description='NDVI_Export',
    folder='EE_Exports',
    fileNamePrefix='ndvi_2020',
    region=roi,
    scale=30,
    crs='EPSG:4326',
    maxPixels=1e13,
    fileFormat='GeoTIFF',
    formatOptions={'cloudOptimized': True}
)
task.start()
```

**Export to Cloud Storage:**
```javascript
Export.image.toCloudStorage({
  image: ndvi,
  description: 'NDVI_Export_GCS',
  bucket: 'my-bucket',
  fileNamePrefix: 'ndvi/2020_composite',
  region: roi,
  scale: 30,
  crs: 'EPSG:4326',
  maxPixels: 1e13,
  fileFormat: 'GeoTIFF',
  formatOptions: { cloudOptimized: true }
});
```

**Export as EE Asset:**
```javascript
Export.image.toAsset({
  image: ndvi,
  description: 'NDVI_Asset',
  assetId: 'projects/my-project/assets/ndvi_2020',
  region: roi,
  scale: 30,
  crs: 'EPSG:4326',
  maxPixels: 1e13
});
```

**Key export parameters:**
- `scale`: Output resolution in meters
- `crs`: Coordinate reference system (e.g., `'EPSG:4326'`, `'EPSG:32610'`)
- `region`: ee.Geometry defining the export extent
- `maxPixels`: Safety limit to prevent accidental large exports (default: 1e8)
- `fileFormat`: `'GeoTIFF'` (default), `'TFRecord'`
- `formatOptions`: `{cloudOptimized: true}` for COG output
- Batch exports run asynchronously and can exceed the 5-minute interactive timeout

---

## Client Libraries

### JavaScript API (Code Editor)

Used in the browser-based Code Editor at code.earthengine.google.com. Authentication and initialization are handled automatically. Syntax looks synchronous but all `ee.` operations are deferred.

```javascript
// Code Editor handles auth automatically
var image = ee.Image('USGS/SRTMGL1_003');
var elevation = image.select('elevation');
Map.addLayer(elevation, {min: 0, max: 3000, palette: ['blue','green','red']}, 'DEM');
print('Mean elevation:', elevation.reduceRegion({
  reducer: ee.Reducer.mean(),
  geometry: roi,
  scale: 90
}));
```

### Python API (ee)

Used in Jupyter notebooks, scripts, and server applications. Requires explicit authentication and initialization.

```python
import ee

ee.Authenticate()
ee.Initialize(project='my-project')

# Load and process
image = ee.Image('USGS/SRTMGL1_003')
stats = image.reduceRegion(
    reducer=ee.Reducer.mean(),
    geometry=roi,
    scale=90
).getInfo()  # .getInfo() fetches result to client
print(stats)
```

**Service account authentication (for servers):**
```python
import ee

credentials = ee.ServiceAccountCredentials(
    'my-service-account@project.iam.gserviceaccount.com',
    'path/to/private-key.json'
)
ee.Initialize(credentials, project='my-project')
```

### REST API

Direct HTTP access to EE computation endpoints. The client serializes the computation graph as a JSON Expression object and sends it via POST.

```
POST https://earthengine.googleapis.com/v1/projects/{project}/value:compute
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "expression": { /* serialized computation graph */ }
}
```

Endpoints:
- `value:compute` -- compute a scalar, dictionary, or other value
- `image:computePixels` -- compute raster pixels
- `table:computeFeatures` -- compute vector features
- `maps:create` -- create a tile map for visualization
- `thumbnails:create` -- generate a thumbnail image

### Earth Engine Apps

Published interactive web applications accessible via URL without requiring an EE account. Apps use the `ui` framework for widgets (buttons, sliders, panels, charts) and the `Map` object for interactive layers. Each app gets its own compute quota.

---

## Common Patterns for Imagery Analysis

### 1. NDVI Computation

```javascript
// Landsat 8/9
var ndvi_l8 = image.normalizedDifference(['SR_B5', 'SR_B4']).rename('NDVI');

// Sentinel-2
var ndvi_s2 = image.normalizedDifference(['B8', 'B4']).rename('NDVI');

// MODIS
var ndvi_mod = image.normalizedDifference(['sur_refl_b02', 'sur_refl_b01']).rename('NDVI');
```

```python
# Landsat 8/9
ndvi_l8 = image.normalizedDifference(['SR_B5', 'SR_B4']).rename('NDVI')

# Sentinel-2
ndvi_s2 = image.normalizedDifference(['B8', 'B4']).rename('NDVI')
```

### 2. Cloud Masking

**Landsat 8/9 Collection 2 (QA_PIXEL band):**
```javascript
function maskL8C2(image) {
  var qa = image.select('QA_PIXEL');
  var dilatedCloud = 1 << 1;
  var cirrus = 1 << 2;
  var cloud = 1 << 3;
  var cloudShadow = 1 << 4;
  var mask = qa.bitwiseAnd(dilatedCloud).eq(0)
      .and(qa.bitwiseAnd(cirrus).eq(0))
      .and(qa.bitwiseAnd(cloud).eq(0))
      .and(qa.bitwiseAnd(cloudShadow).eq(0));
  return image.updateMask(mask)
      .select('SR_B.*')
      .copyProperties(image, image.propertyNames());
}
```

**Sentinel-2 (QA60 band):**
```javascript
function maskS2clouds(image) {
  var qa = image.select('QA60');
  var cloudBitMask = 1 << 10;
  var cirrusBitMask = 1 << 11;
  var mask = qa.bitwiseAnd(cloudBitMask).eq(0)
      .and(qa.bitwiseAnd(cirrusBitMask).eq(0));
  return image.updateMask(mask);
}
```

**Sentinel-2 (Cloud Score+, recommended):**
```javascript
// Join Cloud Score+ to S2 collection for better cloud masking
var csPlus = ee.ImageCollection('GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED');
var s2 = ee.ImageCollection('COPERNICUS/S2_SR_HARMONIZED')
    .filterDate('2023-01-01', '2023-12-31')
    .linkCollection(csPlus, ['cs_cdf']);

var composite = s2.map(function(image) {
  return image.updateMask(image.select('cs_cdf').gte(0.6));
}).median();
```

### 3. Temporal Composites

```javascript
// Cloud-free median composite over a date range
var composite = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2')
    .filterDate('2020-06-01', '2020-09-01')
    .filterBounds(roi)
    .map(maskL8C2)
    .median();

// Greenest pixel composite (max NDVI)
var greenest = collection.map(addNDVI).qualityMosaic('NDVI');
```

```python
composite = (ee.ImageCollection('LANDSAT/LC08/C02/T1_L2')
    .filterDate('2020-06-01', '2020-09-01')
    .filterBounds(roi)
    .map(mask_l8_c2)
    .median())
```

### 4. Change Detection

```javascript
// Simple image differencing
var before = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2')
    .filterDate('2019-06-01', '2019-09-01').filterBounds(roi)
    .map(maskL8C2).median();
var after = ee.ImageCollection('LANDSAT/LC08/C02/T1_L2')
    .filterDate('2021-06-01', '2021-09-01').filterBounds(roi)
    .map(maskL8C2).median();

var ndviBefore = before.normalizedDifference(['SR_B5', 'SR_B4']);
var ndviAfter = after.normalizedDifference(['SR_B5', 'SR_B4']);
var change = ndviAfter.subtract(ndviBefore).rename('NDVI_change');

// Threshold for significant change
var significantLoss = change.lt(-0.2);
var significantGain = change.gt(0.2);
```

### 5. Zonal Statistics

```javascript
// Reduce imagery over feature collection geometries
var meanNDVI = ndvi.reduceRegions({
  collection: parcels,
  reducer: ee.Reducer.mean().combine({
    reducer2: ee.Reducer.stdDev(),
    sharedInputs: true
  }),
  scale: 30
});
```

```python
mean_ndvi = ndvi.reduceRegions(
    collection=parcels,
    reducer=ee.Reducer.mean().combine(
        reducer2=ee.Reducer.stdDev(),
        sharedInputs=True
    ),
    scale=30
)
```

### 6. Time Series Extraction

```javascript
// Chart NDVI over time at a point
var chart = ui.Chart.image.series({
  imageCollection: withNDVI.select('NDVI'),
  region: point,
  reducer: ee.Reducer.mean(),
  scale: 30
}).setOptions({title: 'NDVI Time Series'});
print(chart);
```

```python
# Python: extract time series to pandas DataFrame
import pandas as pd

region_values = with_ndvi.select('NDVI').getRegion(point, 30).getInfo()

# Convert to DataFrame
headers = region_values[0]
data = region_values[1:]
df = pd.DataFrame(data, columns=headers)
df['datetime'] = pd.to_datetime(df['time'], unit='ms')
df['NDVI'] = pd.to_numeric(df['NDVI'], errors='coerce')
```

---

## Architectural Patterns for Custom Imagery Servers

EE's architecture provides several patterns relevant to designing custom geospatial processing systems. The open-source Google Earth Enterprise codebase reveals concrete implementation details behind these patterns.

### Lazy Evaluation / Computation Graph

Operations build a DAG rather than executing immediately. The server optimizes and executes the graph only when results are requested. This pattern enables:
- **Query optimization**: reordering operations, eliminating dead branches
- **Parallel execution**: independent graph branches run concurrently
- **Caching**: intermediate results can be memoized across requests

### Scale-Dependent Processing with Image Pyramids

The output determines the processing resolution. Image pyramids pre-compute coarser representations, and the system selects the appropriate level based on the request. This avoids processing full-resolution data when a low-resolution preview suffices.

**Pyramid construction** works by minifying tiles: each parent tile is built by averaging 2x2 blocks of child pixels. The Earth Enterprise source reveals this pattern -- the `MinifyTile` operation takes a source tile and writes the averaged result into one quadrant of the parent tile, using a configurable averager function applied per-component (per-band):

```
Parent tile (256x256):
+---+---+
| 2 | 3 |    Each quadrant is filled by averaging 2x2 pixel blocks
+---+---+    from a child tile (also 256x256), producing 128x128
| 0 | 1 |    pixels in the parent quadrant.
+---+---+
```

**Zoom level calculation** determines the pyramid level from the requested output resolution. Given the requested pixel extent and the total map extent, the zoom level is computed as `zoom = ceil(log2(total_pixels_needed / 256))`, ensuring at least 1 tile pixel per requested pixel. The maximum zoom level is capped (24 levels in Earth Enterprise).

### Quadtree Tile Addressing

Tiles are addressed using a **quadtree path** -- a compact encoding where each level uses 2 bits to identify one of 4 children (quadrants 0-3). Up to 24 levels can be packed into a single 64-bit integer, with more significant bits representing higher (coarser) levels. This encoding enables:

- **O(1) parent/child navigation**: parent is a bit shift, child is shift + OR
- **Efficient ancestor testing**: compare path prefixes
- **Compact tile IDs**: a single uint64 encodes both position and zoom level
- **Direct spatial mapping**: quadtree path maps to (level, row, col) coordinates

The tile resampler uses these paths to extract a sub-quadrant from a parent tile when the exact child tile is unavailable: decompress the parent tile, extract the pixels for the child's quadrant, scale them up to fill the tile dimensions, and recompress.

### Tile-Based Distributed Processing

Images are partitioned into 256x256 pixel tiles that are processed independently across many machines. The WMS tile serving pipeline illustrates this flow:

1. **Calculate zoom level** from the requested bounding box and output dimensions
2. **Calculate tile rectangles**: map the bounding box to tile-pixel space, then determine which tiles are needed (rounding outward to whole tile boundaries)
3. **Fetch tiles**: request each needed tile from the tile server using (x, y, z) coordinates; out-of-bounds tiles become black/transparent; east-west coordinates wrap around
4. **Stitch tiles**: paste fetched tiles into a composite image at their correct positions
5. **Crop and resize**: crop the composite to the exact requested extent, then resize to the requested pixel dimensions

This architecture enables horizontal scaling -- each tile fetch and render can be parallelized, and partial results can be served as they complete.

### On-Demand Rendering vs. Caching

Map tiles are rendered on demand when first requested, then cached for subsequent views. This balances storage costs against latency. Precomputing all possible tiles at all zoom levels would be prohibitively expensive for dynamic data.

The tile serving pipeline handles transparency and compositing at serve time: PNG tiles support per-pixel alpha transparency, while JPEG tiles render opaque. Background color handling and alpha thresholding are applied during tile stitching, not during storage.

### Catalog / Metadata Management

A central catalog indexes billions of images by spatial extent, temporal range, sensor, and quality attributes. Efficient catalog queries (spatial and temporal filtering) are critical for narrowing data before processing begins.

In the Earth Enterprise model, each published database exposes a `serverDefs` JSON manifest describing its layers -- including layer IDs, projection type, request types (imagery, vector, terrain), and versioning. Clients fetch this manifest to discover available layers and their tile request URL patterns. This separation of metadata from tile data enables dynamic layer discovery and multi-database publishing.

### Client SDK Design Patterns

- **Proxy objects**: Client objects are lightweight handles, not data containers
- **Deferred execution**: Method calls build descriptions, not results
- **Serializable computation**: The entire operation pipeline can be serialized as JSON
- **Server-side iteration**: `map()` over collections instead of client-side loops
- **Type safety at the boundary**: Explicit conversion between client and server types (`getInfo()`, `ee.Number()`)

These patterns are broadly applicable to any system that processes large-scale raster data on-demand, including custom tile servers, cloud-native geospatial platforms, and imagery analysis APIs.
