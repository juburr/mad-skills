---
name: geospatial-imagery
description: >-
  Guides geospatial imagery workflows including format conversion, GDAL operations,
  OGC protocol integration (WMS/WMTS/TMS/WCS), tile server development, imagery server
  architecture, front-end map client configuration, performance optimization, imagery
  sourcing, and spatial indexing. Use when working with raster imagery formats (GeoTIFF,
  COG, NITF, JPEG2000, MrSID), building or configuring imagery/tile servers, integrating
  mapping clients (Cesium, OpenLayers, Leaflet), optimizing geospatial data serving
  pipelines, sourcing satellite/aerial imagery, or designing spatial indexes and caches.
---

# Geospatial Imagery

## Quick Format Reference

| Format | GDAL Driver | Compression | Best For |
|---|---|---|---|
| GeoTIFF | `GTiff` | LZW, DEFLATE, ZSTD, JPEG, WebP, LERC | General purpose, archival |
| COG | `COG` (write) | Same as GeoTIFF | Cloud serving, HTTP range requests |
| NITF | `NITF` | JPEG, JPEG2000, VQ | Military/intelligence imagery |
| JPEG2000 | `JP2OpenJPEG` | Wavelet (lossy/lossless) | High compression ratio imagery |
| MrSID | `MrSID` | Wavelet | Large image archives (read-only without license) |
| ECW | `ECW` | Wavelet | Large image archives (licensing restrictions) |
| HDF5 | `HDF5` | GZIP, SZIP | Satellite science data (MODIS, Sentinel) |
| NetCDF | `netCDF` | DEFLATE | Climate/weather time-series |
| MBTiles | `MBTiles` | Per-tile (PNG/JPEG/WebP) | Portable tile archives |

For detailed format internals, compression options, and georeferencing metadata, read `references/formats.md`.

## GDAL Quick Reference

### Inspect

```bash
gdalinfo input.tif                    # Metadata, CRS, bounds, bands
gdalinfo -stats input.tif             # Compute and show statistics
gdalinfo -json input.tif              # JSON output
```

### Convert and Compress

```bash
# GeoTIFF to COG (lossless)
gdal_translate -of COG -co COMPRESS=DEFLATE -co PREDICTOR=YES input.tif output.tif

# GeoTIFF to COG (lossy, visual imagery)
gdal_translate -of COG -co COMPRESS=JPEG -co QUALITY=85 input.tif output.tif

# NITF to COG
gdal_translate -of COG -co COMPRESS=DEFLATE input.ntf output.tif
```

### Reproject

```bash
# To Web Mercator
gdalwarp -t_srs EPSG:3857 -r bilinear input.tif output.tif

# With target resolution (10m)
gdalwarp -t_srs EPSG:3857 -tr 10 10 -r cubic input.tif output.tif
```

### Build Overviews

```bash
gdaladdo -r average input.tif 2 4 8 16 32
```

### Generate Web Tiles

```bash
gdal2tiles.py -z 0-18 -w leaflet --processes=4 input.tif ./tiles/
```

### Virtual Rasters

```bash
# Lightweight mosaic (no data copy)
gdalbuildvrt mosaic.vrt *.tif

# Band combination
gdalbuildvrt -separate rgb.vrt red.tif green.tif blue.tif
```

### Cloud Access

```bash
# Read from S3
gdalinfo /vsis3/bucket/path/image.tif

# Read via HTTP (COGs)
gdalinfo /vsicurl/https://example.com/image_cog.tif
```

| Resampling Method | Use Case |
|---|---|
| `nearest` | Categorical data, classification maps |
| `bilinear` | Continuous data, general purpose |
| `cubic` | Smooth continuous data, visual quality |
| `lanczos` | Highest quality, sharpest results |
| `average` | Overview generation, downsampling |
| `mode` | Categorical data overviews |

For complete GDAL command reference, all creation options, compression comparison tables, Python bindings, and the unified CLI (3.11+), read `references/gdal.md`.

## OGC Protocol Quick Reference

### WMS (Web Map Service)

Returns rendered map images. Two versions in common use:

| Difference | WMS 1.1.1 | WMS 1.3.0 |
|---|---|---|
| CRS parameter | `SRS` | `CRS` |
| EPSG:4326 axis order | lon, lat | **lat, lon** |
| Feature info params | `X`, `Y` | `I`, `J` |

**GetMap request (1.3.0):**
```
/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap
  &LAYERS=imagery&STYLES=&CRS=EPSG:3857
  &BBOX=-10018754,5009377,-9783940,5244191
  &WIDTH=256&HEIGHT=256&FORMAT=image/png
```

The EPSG:4326 axis order change in WMS 1.3.0 is the most common source of integration bugs. Use `CRS:84` for longitude-first order in 1.3.0.

### WMTS (Web Map Tile Service)

Pre-rendered tiles from a tile matrix set. Faster than WMS for tiled access.

**RESTful pattern:**
```
/wmts/rest/{Layer}/{Style}/{TileMatrixSet}/{TileMatrix}/{TileRow}/{TileCol}?FORMAT=image/png
```

### XYZ / TMS Tiles

| Scheme | URL Pattern | Y Origin |
|---|---|---|
| XYZ (Google/OSM) | `/{z}/{x}/{y}.png` | Top-left |
| TMS | `/{z}/{x}/{y}.png` | Bottom-left (Y flipped) |

**TMS to XYZ conversion:** `y_xyz = (2^z - 1) - y_tms`

### WCS (Web Coverage Service)

Returns raw raster data (not rendered images). Use for data download/analysis.

### Tile Math

```
# Lon/Lat to tile coordinates
x = floor((lon + 180) / 360 * 2^z)
y = floor((1 - ln(tan(lat_rad) + sec(lat_rad)) / pi) / 2 * 2^z)

# Ground resolution (meters/pixel at equator)
resolution = 156543.03 / 2^z
```

For complete protocol specifications, all parameters, version differences, tile matrix sets, and coordinate conversion formulas, read `references/protocols.md`.

## Imagery Server Architecture

### Serving Patterns

| Pattern | Latency | Storage | Freshness | Best For |
|---|---|---|---|---|
| Pre-rendered tiles | Lowest | High | Stale until regenerated | Static basemaps, CDN serving |
| On-the-fly rendering | Highest | None | Always current | Dynamic data, low-traffic layers |
| Cache-on-demand | Cold: high, warm: low | Medium | Configurable TTL | Most production deployments |
| COG-based (range requests) | Medium | Source only | Always current | Cloud-native, serverless |

### GeoServer Architecture (Reference)

GeoServer uses a layered architecture worth understanding for any imagery server:

- **Catalog model**: Workspace > Store > Resource > Layer hierarchy
- **Rendering pipeline**: Request parsing > style evaluation > data reading > rendering > encoding
- **GeoWebCache**: Embedded tile cache with metatiling, disk/S3/Azure blob storage, LRU/LFU eviction
- **ImageMosaic**: Combines multiple raster files into a single logical layer with time/elevation dimensions

For GeoServer internals, module structure, GeoWebCache configuration, and JAI/ImageN processing chain, read `references/geoserver.md`.

### Google Earth Engine Architecture (Reference)

Earth Engine's patterns inform modern imagery server design:

- **Lazy evaluation**: Operations build a computation graph (DAG), executed only when results are needed
- **Scale-dependent processing**: Resolution determined by output, not input; automatic resampling
- **Tile-based distribution**: Work partitioned by spatial tiles across compute nodes
- **Client proxy objects**: `ee.Image` is a server-side handle, not local data

For Earth Engine API details, data catalog, common analysis patterns (NDVI, cloud masking, compositing), and export workflows, read `references/earth-engine.md`.

### Building a Custom Tile Server

Key components for a tile server implementation:

1. **URL routing**: Parse `/{z}/{x}/{y}.{format}` from request path
2. **Tile rendering**: Read source raster, extract tile extent, resample, encode
3. **Cache layer**: Multi-tier (in-memory LRU > disk > object storage)
4. **Cache headers**: `Cache-Control`, `ETag`, conditional `304 Not Modified` responses
5. **Request coalescing**: Singleflight pattern -- concurrent requests for the same tile share one render
6. **CORS**: Required for cross-origin tile requests from browser clients
7. **WMS compatibility**: Parse GetMap KVP parameters, handle axis order differences

**Go implementation notes:**
- Image processing: `image/png`, `image/jpeg`, `golang.org/x/image/tiff`
- GDAL bindings: `github.com/airbusgeo/godal` (recommended over lukeroth/gdal)
- Buffer pooling: `sync.Pool` for image encode buffers
- Request coalescing: `golang.org/x/sync/singleflight`
- HTTP router: `net/http` (1.22+ patterns) or chi/echo

For complete tile server implementation patterns, storage strategies, WMS endpoint construction, reference implementations (TiTiler, MapProxy, Martin, Tegola), and Go code examples, read `references/tile-servers.md`.

## Front-End Client Integration

### CesiumJS

```javascript
// WMS layer
const provider = new Cesium.WebMapServiceImageryProvider({
  url: "https://example.com/wms",
  layers: "imagery",
  parameters: { format: "image/png", transparent: true },
});
viewer.imageryLayers.addImageryProvider(provider);

// XYZ tiles
const xyz = new Cesium.UrlTemplateImageryProvider({
  url: "https://example.com/tiles/{z}/{x}/{y}.png",
});
viewer.imageryLayers.addImageryProvider(xyz);
```

### OpenLayers

```javascript
// WMS (tiled)
new ol.layer.Tile({
  source: new ol.source.TileWMS({
    url: "https://example.com/wms",
    params: { LAYERS: "imagery", FORMAT: "image/png" },
    serverType: "geoserver",
  }),
});

// XYZ tiles
new ol.layer.Tile({
  source: new ol.source.XYZ({
    url: "https://example.com/tiles/{z}/{x}/{y}.png",
  }),
});
```

### Leaflet

```javascript
// XYZ tiles
L.tileLayer("https://example.com/tiles/{z}/{x}/{y}.png", {
  maxZoom: 19,
  attribution: "Custom Imagery",
}).addTo(map);

// WMS
L.tileLayer.wms("https://example.com/wms", {
  layers: "imagery",
  format: "image/png",
  transparent: true,
}).addTo(map);
```

For complete provider/source class reference, constructor options, tiling schemes, projection handling, request scheduling, and retina/CORS/authentication patterns, read `references/clients.md`.

## Performance Optimization

### Data Preparation Checklist

1. **Convert to COG** with appropriate compression (DEFLATE for lossless, JPEG/WebP for lossy)
2. **Build overviews** at pyramid levels (2, 4, 8, 16, 32, 64) using `average` resampling
3. **Use internal tiling** at 256x256 or 512x512 (COG default: 512)
4. **Choose serving format** by content type:

| Content | Serve As | Why |
|---|---|---|
| Aerial/satellite imagery | JPEG or WebP | Lossy OK, small files |
| Imagery with transparency | PNG or WebP | Alpha channel support |
| Elevation/classification | PNG | Lossless preserves values |

### Caching Strategy

```
Client Cache (browser)
  └─> CDN / Edge Cache (CloudFront, CloudFlare)
      └─> Application Cache (in-memory LRU)
          └─> Disk / Object Store Cache (S3, local SSD)
              └─> Source Data (COG, database)
```

**Cache headers for tiles:**
```http
Cache-Control: public, max-age=86400, s-maxage=604800, stale-while-revalidate=3600
ETag: "v2-z12-x1234-y5678"
```

### Key Performance Patterns

- **Metatiling**: Render a 4x4 grid of tiles in one backend request, split for serving. Reduces redundant reads and fixes label/symbol clipping at tile edges.
- **Request coalescing**: Multiple concurrent requests for the same tile share one render operation (Go: `singleflight`).
- **Connection pooling**: Reuse GDAL dataset handles and database connections.
- **Buffer pooling**: Reuse image encoding buffers via `sync.Pool` (Go) to reduce GC pressure.
- **HTTP/2**: Allows browsers to multiplex many tile requests over a single connection.

### GeoServer-Specific Tuning

```bash
# JVM flags for tile serving workloads
JAVA_OPTS="-Xms4g -Xmx4g -XX:+UseG1GC \
  -Dorg.geotools.coverage.jaiext.enabled=true \
  -Dsun.java2d.renderer=org.marlin.pisces.MarlinRenderingEngine"
```

| Setting | Recommended Value | Purpose |
|---|---|---|
| JAI tile cache | 50-75% of heap | Image operation caching |
| Metatile size | 4x4 | Balance render cost vs cache size |
| Gutter pixels | 6-10 | Prevent label/symbol clipping |
| Overview policy | `SPEED` | Prefer overviews for faster rendering |

### Monitoring Targets

| Metric | Target |
|---|---|
| Tile latency (p95) | < 200ms |
| Cache hit ratio | > 85% |
| Throughput | > 500 tiles/sec per node |
| Error rate | < 0.1% |

For complete performance tuning guide including COG creation options, compression benchmarks, GeoServer JVM/JAI/GWC tuning, scaling patterns (horizontal, serverless, Kubernetes), benchmarking tools (wrk, vegeta, k6), and monitoring strategies, read `references/performance.md`.

## Tiling Pipeline

Understanding what happens under the hood when imagery is tiled and served:

1. **Ingest** raw image with georeferencing metadata (affine geotransform, CRS)
2. **Reproject** to target CRS (typically EPSG:3857 Web Mercator) -- datum transform + pixel resampling
3. **Compress** with selected codec (DEFLATE lossless, JPEG/WebP lossy)
4. **Generate overviews** at progressively lower resolutions (each level ~1/4 the pixels)
5. **Tile** into 256x256 or 512x512 pixel grid aligned to the tile matrix
6. **Store** as pre-rendered tiles, COG, or MBTiles archive
7. **Serve** via HTTP with cache headers, range requests (COG), or tile lookups

**COG range request flow**: Client computes tile z/x/y > selects correct IFD (overview level) > HTTP range request for tile offset/length from IFD directory > server returns compressed bytes > client decompresses and renders.

**Without GDAL**: Build pipelines using PROJ (reprojection), libtiff/libgeotiff (GeoTIFF I/O), codec libraries (libjpeg, libpng, libwebp). Rust: `proj`, `tiff`, `image`, `cogbuilder` crates. Go: `golang.org/x/image/tiff` + CGo GDAL bindings via `github.com/airbusgeo/godal`.

For the complete tiling pipeline narrative, GDAL internals from source code, non-GDAL alternatives, runtime vs build-time tradeoffs, COG range request walkthrough, and hot path analysis, read `references/tiling-pipeline.md`.

## Imagery Sources

### Quick Start: Test Dataset

For testing a custom tile server, download Natural Earth 1:50m raster (~260 MB):
```bash
curl -L -o NE1_50M_SR_W.zip \
  https://naciscdn.org/naturalearth/50m/raster/NE1_50M_SR_W.zip
unzip NE1_50M_SR_W.zip
gdal_translate -of COG -co COMPRESS=JPEG NE1_50M_SR_W.tif world_cog.tif
```

### Free Imagery for Development

| Source | Resolution | Coverage | Access |
|---|---|---|---|
| Natural Earth | 1:10m-1:110m | Global | Direct download |
| Sentinel-2 (Copernicus) | 10m | Global | Copernicus Data Space, AWS S3 |
| Landsat 8/9 (USGS) | 30m | Global | USGS Earth Explorer, AWS S3 |
| NAIP (USGS) | ~1m | US only | AWS S3 (`s3://naip-analytic/`) |
| NASA GIBS | Varies | Global | WMTS tiles (direct URL access) |
| Blue Marble | 500m | Global | NASA direct download |

### Commercial and Defense Providers

| Provider | Resolution | Specialty |
|---|---|---|
| Maxar (WorldView) | 30cm | Highest-resolution commercial optical |
| Planet (PlanetScope) | 3-5m daily | Daily global coverage |
| BlackSky | <1m | Rapid revisit, real-time monitoring |
| Capella Space | <50cm SAR | All-weather, day/night |
| Airbus (Pleiades Neo) | 30cm | European provider |

**Defense programs**: NGA manages GEOINT; NRO manages the EOCL commercial imagery contract. NIIRS scale (0-9) rates imagery interpretability -- NIIRS 5 (~1m GSD) identifies vehicles, NIIRS 7 (~0.2m GSD) identifies equipment details.

For complete satellite specs, download instructions, commercial/defense provider details, NIIRS scale, STAC catalogs, and licensing information, read `references/sources.md`.

## Indexing and Databases

### Spatial Index Selection

| Use Case | Recommended | Why |
|---|---|---|
| Tile metadata/footprints | PostGIS (GiST) | R-tree spatial indexing, complex queries |
| Tile cache | MBTiles / filesystem / S3 | Simple key-value, high throughput |
| In-memory hot cache | Redis | Fast TTL, LRU eviction |
| Imagery catalog/discovery | PostGIS + STAC API | Spatial + temporal search |
| Embedded/portable | SQLite / GeoPackage | Zero dependencies |
| Cloud-scale | S3 + CDN | Serverless, auto-scaling |

### Key Patterns

- **PostGIS**: GiST indexes on geometry columns enable fast `ST_Intersects` queries to find imagery covering a tile request
- **STAC (SpatioTemporal Asset Catalog)**: Standard API for imagery search/discovery by space, time, and properties
- **GeoServer ImageMosaic**: Uses shapefile or database index to track granule footprints, timestamps, and resolution
- **Earth Enterprise**: File-based quadtree index with 2 bits/level packed into uint64, bucket-based lookup for O(1) tile addressing
- **PMTiles**: Single-file archive using Hilbert curve ordering for spatial locality in HTTP range requests

### Caching Tiers

| Tier | Storage | Latency | Contents |
|---|---|---|---|
| L1: In-memory | RAM | <1ms | Hot tiles, index structures |
| L2: Local disk/SSD | SSD | 1-10ms | Warm tiles, rendered cache |
| L3: Object storage | S3 | 20-100ms | Cold tiles, COG sources |
| L4: Database | PostGIS | 5-50ms | Metadata, footprints, search |

For complete PostGIS indexing patterns, Earth Enterprise index internals from source code, STAC catalogs, MBTiles/PMTiles/GeoPackage details, caching strategies, and database selection guide, read `references/indexing.md`.

## Reference Files

| File | Contents | Load When |
|---|---|---|
| `references/formats.md` | File format internals, compression options, georeferencing, GDAL drivers | Working with specific formats, choosing formats, debugging format issues |
| `references/gdal.md` | GDAL command reference, workflows, creation options, Python bindings, unified CLI | Running GDAL operations, converting/processing imagery |
| `references/protocols.md` | WMS, WMTS, TMS, XYZ, WCS, OGC API Tiles specs, parameters, tile math | Implementing or debugging OGC protocol endpoints or client connections |
| `references/geoserver.md` | GeoServer architecture, catalog model, rendering pipeline, GeoWebCache, JAI | Configuring GeoServer, understanding imagery server architecture patterns |
| `references/earth-engine.md` | Earth Engine API, computation model, data catalog, analysis patterns | Working with Earth Engine, designing computation graph architectures |
| `references/clients.md` | CesiumJS, OpenLayers, Leaflet provider/source configuration and options | Connecting front-end map clients to imagery servers |
| `references/tile-servers.md` | Custom tile server patterns, storage, WMS endpoints, Go implementation | Building a tile server, choosing storage/caching strategies |
| `references/tiling-pipeline.md` | Under-the-hood tiling narrative, GDAL internals, non-GDAL alternatives, COG range requests | Understanding what tile servers do internally, building without GDAL |
| `references/performance.md` | COG optimization, caching strategies, GeoServer tuning, scaling, monitoring | Optimizing imagery serving performance, load testing |
| `references/sources.md` | Satellite/aerial systems, free datasets, commercial/defense providers, NIIRS, STAC | Sourcing imagery, finding test data, understanding provider landscape |
| `references/indexing.md` | PostGIS, Earth Enterprise indexes, STAC, MBTiles, Redis, caching tiers | Designing spatial indexes, choosing databases, caching strategies |
